# llama.cpp + SYCL Tuning Guide for Intel Arc Pro B70

This guide is specific to the **Intel Arc Pro B70** (32 GB, BMG-G31 **Xe2**) using this repo's SYCL Docker image (or a matching build). For the reasoning and full benchmark numbers, see [`benchmark/`](../benchmark/README.md) and [`B70-SYCL-KNOWLEDGE.md`](./B70-SYCL-KNOWLEDGE.md).

## 1. Host prerequisites (Linux)

- Recent kernel with good Xe support (Ubuntu 24.04/26.04 + kernel 6.8+ or 7.x recommended).
- Intel GPU driver / compute-runtime is expected on the **host**. The container brings its own user-space, but **Level Zero must still enumerate the device**.
- Add your user to the GPU groups:

```bash
sudo usermod -aG render,video $USER
# then log out / back in
```

- **Stability flag (recommended, needed on B450):** add `pcie_aspm=off` to the kernel cmdline (`GRUB_CMDLINE_LINUX_DEFAULT="pcie_aspm=off"` + `update-grub` + reboot). See `benchmark/incidents/2026-08-21-gpu-dropout.md`.

- Verify:

```bash
sycl-ls
# Expect:
# [level_zero:gpu][level_zero:0] ... Intel(R) Arc(TM) Pro B70 Graphics
```

## 2. Key build options (already set in `.devops/intel.Dockerfile`)

- `-DGGML_SYCL=ON`
- `-DGGML_SYCL_F16=ON`
- `-DGGML_SYCL_DEVICE_ARCH=bmg-g31` ← **very important for B70**
- `-DGGML_BACKEND_DL=ON`
- **No** `GGML_SYCL_DISABLE_OPT`

The AOT flag (`bmg-g31`) pre-compiles kernels for Battlemage and avoids JIT/SIGSEGV at startup.

## 3. Mandatory runtime environment vars

```bash
export ONEAPI_DEVICE_SELECTOR=level_zero:0
export SYCL_CACHE_PERSISTENT=0     # Xe2 + 2026 oneAPI SIGSEGVs with =1 on first JIT
export ZES_ENABLE_SYSMAN=1
# Do NOT set GGML_SYCL_DISABLE_OPT (large SYCL perf loss)
```

## 4. KV cache: the single biggest stability lever

| KV type | Use when | Why |
|---------|----------|-----|
| f16 | short context, no MTP draft | fast, smallest overhead |
| **q8_0** (`--cache-type-k/v q8_0`) | **MTP + 96k–128k context** | halves KV; the only way the ≈5.9 GB MTP draft + large context fit in 32 GB without host-RAM overflow/OOM |

> Rule of thumb: **f16 KV + MTP + ≥96k → near-certain OOM.** Default to q8_0 when running speculative MTP at large context (see `benchmark/METHODOLOGY.md` §4).

## 5. Recommended server flags for 27B-class models

**Recommended (MTP3 + 96k + q8_0):**

```bash
./llama-server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --mmproj /models/mmproj-Qwen3.8-27B-BF16.gguf \
  --n-gpu-layers 999 \
  --ctx-size 98304 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --flash-attn on \
  --spec-type draft-mtp \
  --spec-draft-model /models/mtp-Qwen3.8-27B-BF16.gguf \
  --spec-draft-n-max 3 \
  --spec-draft-p-min 0.1 \
  --port 8080 --host 0.0.0.0
```

**Max context (MTP4 + 128k + q8_0):** replace `--ctx-size 98304` with `--ctx-size 131072` and `--spec-draft-n-max 4`. Matches `examples/qwen27b-server.sh`.

**MTP / speculative decoding:** use a draft-model GGUF with `--spec-draft-model` (`-md`) + `--spec-type draft-mtp`. Nothing in this image disables the speculative paths.

**Flash Attention:** `--flash-attn on` (or `auto`). SYCL support landed upstream ~2026.03; memory savings are significant on 27B+ at large context.

> **Quality of draft matters.** Only use a high-quality draft (e.g. BF16 MTP). A low-acceptance 2B draft (acceptance 0.31–0.50) is a **net slowdown**.

## 6. Common pitfalls on B70

- Old compute-runtime / IGC → device not enumerated or very slow kernels.
- Using the default published `intel/ggml` images without rebuilding → old oneAPI, no B70 fixes.
- Setting `GGML_SYCL_DISABLE_OPT=1`.
- `f16 KV + MTP + large ctx` → host OOM (use q8_0).
- Not passing the render device into the container (pass `/dev/dri` or the specific render device).
- **Reading the wrong throughput number** — llama.cpp's logged `eval time` token/s is inflated by speculative batching; read real speed from streamed `tg` or `timings`.

## 7. Verifying a good run

Inside the container:

```bash
sycl-ls
./llama-server --version
```

Look for:
- Device listed as B70.
- No immediate SYCL error / kernel-launch failure.
- Model loads with reasonable `llm_load_tensors` buffer sizes (a 27B Q4/Q5 fits in 32 GB).

**Card-alive check (strict):** a real `/v1/chat/completions` that returns text with `finish_reason=stop`. Check `dmesg` for `wedged / reset failed / GuC no reply` to detect an un-recovered card.

## 8. Updating for newer B70 support

1. Check [intel/compute-runtime releases](https://github.com/intel/compute-runtime/releases) and [intel-graphics-compiler releases](https://github.com/intel/intel-graphics-compiler/releases).
2. Update the ARG defaults in `.devops/intel.Dockerfile`.
3. Rebuild and test with a 27B model + flash-attn + MTP draft.
4. Open a PR with benchmark numbers (pp/tg for your quant + context).

The CI workflows auto-pick up dependency updates; see the **CI / Automatic builds** section in the project [`README.md`](../README.md).

## 9. B70 disappearance / PCIe link training (B450 etc.)

Some motherboards (notably ASUS ROG STRIX B450-F) can lose the B70 after heavy load, crash, or reboot: `lspci` no longer shows it.

**Recovery sequence that works:**
1. Power off completely.
2. Physically remove the B70.
3. Boot the system using the integrated GPU.
4. Shut down cleanly.
5. Re-insert the B70 (direct into the motherboard slot).
6. Boot again.

**Prevention / stability:**
- Prefer a direct motherboard slot (avoid risers/extenders in daily use — confirmed the dropout reproduces even with a direct slot).
- `pcie_aspm=off` in the kernel cmdline prevents recurrence on this platform.
- Monitor `dmesg | grep -iE 'xe|pcie|fault'` and `journalctl -b -1` after incidents.
- Record full timelines in `benchmark/incidents/` when it happens.

See [`benchmark/incidents/2026-08-21-gpu-dropout.md`](../benchmark/incidents/2026-08-21-gpu-dropout.md) for the detailed incident log and mainboard notes.

**Multi-GPU note (upstream):** a 26.x compute-runtime had a known issue in certain multi-GPU setups (see [ggml-org/llama.cpp#21747](https://github.com/ggml-org/llama.cpp/issues/21747)).

---

Keep all features on. Measure, then decide. Report exact versions + numbers so the community pins stay current.