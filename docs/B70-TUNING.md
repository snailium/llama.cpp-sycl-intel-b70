# Intel Arc Pro B70 + llama.cpp SYCL Tuning Guide (Community)

This guide is specific to **Arc Pro B70 (32 GB Battlemage / BMG-G31)** using the community SYCL Docker or a matching build.

## 1. Host prerequisites (Linux)

- Recent kernel with good Xe support (Ubuntu 24.04/26.04 + 6.8+ or 7.x recommended).
- Intel GPU driver / compute-runtime installed on the **host** (the container brings its own user-space but Level Zero must see the device).
- Add user to groups:

```bash
sudo usermod -aG render,video $USER
# log out / in
```

- Verify:

```bash
sycl-ls
# Expect something like:
# [level_zero:gpu][level_zero:0] ... Intel(R) Arc(TM) Pro B70 Graphics
```

## 2. Key build options (already set in our Dockerfile)

- `-DGGML_SYCL=ON`
- `-DGGML_SYCL_F16=ON` (default in this image)
- `-DGGML_SYCL_DEVICE_ARCH=bmg-g31` ← **Very important for B70**
- `-DGGML_BACKEND_DL=ON`
- No `GGML_SYCL_DISABLE_OPT`

The AOT flag pre-compiles kernels for Battlemage and greatly reduces cold-start problems.

## 3. Runtime environment variables (mandatory for stability)

```bash
export ONEAPI_DEVICE_SELECTOR=level_zero:0
export SYCL_CACHE_PERSISTENT=0     # Xe2 + 2026 oneAPI has a known SIGSEGV with =1 on first JIT
export ZES_ENABLE_SYSMAN=1
# export GGML_SYCL_DISABLE_OPT=1   # NEVER for plain llama.cpp SYCL (50%+ perf loss)
```

## 4. Recommended server flags for 27B-class models (Qwen3 / Qwen3.6 etc.)

```bash
./llama-server \
  -m /models/Qwen3-27B-Q4_K_M.gguf \
  --n-gpu-layers 999 \
  --ctx-size 32768 \
  --flash-attn \
  # KV cache: omit or use f16 explicitly
  # --cache-type-k f16 --cache-type-v f16
  --port 8080 --host 0.0.0.0
```

Avoid `--cache-type-k q8_0` on B70 — there is a known low-bandwidth kernel path.

MTP / speculative decoding:
- Use a draft model GGUF + the appropriate `--draft` / `--draft-model` flags supported by your build of llama-server.
- Nothing in this image disables the speculative paths.

Flash Attention:
- Use `--flash-attn`. The SYCL backend supports it (added upstream ~2026.03). Memory savings are significant on 27B+ at large context.

## 5. Common pitfalls on B70

- Old compute-runtime / IGC → device not enumerated or very slow kernels.
- Using the default published intel/ggml images without rebuilding → old oneAPI + missing B70 fixes.
- Setting `GGML_SYCL_DISABLE_OPT=1` (was only for certain IPEX-LLM workarounds).
- Large context + Q8_0 KV → either OOM or 2x slower.
- Not passing the render device correctly into the container.

## 6. Verifying a good run

Inside container:

```bash
sycl-ls
./llama-server --version
```

Look for:
- Device shows as B70
- No immediate "SYCL error" or memset / kernel launch failures
- Model loads with reasonable `llm_load_tensors` buffer sizes (should fit in 32 GB VRAM for 27B Q4/Q5)

## 7. Updating for newer B70 support

1. Check https://github.com/intel/compute-runtime/releases and https://github.com/intel/intel-graphics-compiler/releases for newer packages.
2. Update the ARG defaults in `.devops/intel.Dockerfile`.
3. Rebuild and test with a 27B model + flash-attn + MTP draft if available.
4. Open a PR with benchmark numbers (pp/tg for your quant + context).

## 8. Multi-GPU notes

B70 multi-GPU works with `--split-mode layer` or model routing (separate servers per card). Community reports mixed results with row split; layer split or explicit device assignment is more reliable today.

---

Keep all features on. Measure, then decide. Report back exact versions + numbers so the community pins stay current.
