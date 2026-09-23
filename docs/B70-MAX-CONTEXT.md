# B70 SYCL — maximum context length

Date: 2026-09-23
Image under test: `ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70@sha256:30159fab5d8283553b1aa06a25b117d18a703d138cd8d48d7914e4010405d1ca` (b11117, the issue #20 candidate)
Config: golden `docs/GOLDEN-CONFIG.md` §2–§3, **only `--ctx-size` varied** — q8_0 KV, Q8_0 MTP draft, MTP3, `--flash-attn on`, mmproj on CPU, 999 GPU layers.

## Answer

| Bound | Value | Nature |
|---|---|---|
| **Model's native training context** | **262 144 (256 K)** | hard ceiling — from GGUF metadata, `qwen35.context_length = 262144` |
| **256 K with q4_0 main KV** | **WORKS — 220 022-token request served** | measured, see "256 K IS reachable" below |
| Largest context with the *golden* (q8_0) KV | 229 376 (224 K) | measured, but marginal (passed once, failed on retry) |
| First size that failed with q8_0 KV | 245 760 (240 K) | measured — `Failed to allocate physical memory` |
| **Shipped production config** | 131 072 (128 K) | `docs/GOLDEN-CONFIG.md`, unchanged |

**256 K is reachable — but the lever is the MAIN KV type, not the draft quant.** With `q8_0` main KV
the practical ceiling is ~224 K (VRAM-bound, not model-bound). Shrinking the MTP draft to Q4 frees
~1.2 GiB and changes nothing; halving the main KV (`q4_0`) makes 256 K work. See
["256 K IS reachable"](#256-k-is-reachable--but-not-by-shrinking-the-draft-measured-2026-09-23).

## What was measured

Each point: start the container, wait for `/v1/models = 200`, then issue a **real** chat completion
(not just a health probe — the load succeeding is not sufficient, see below).

| `--ctx-size` | Loads? | Serves a request? | main KV | draft KV | Result |
|---|---|---|---|---|---|
| 131 072 (128 K) | yes | **yes** | 4352 MiB | 272 MiB | baseline — full suite passed |
| 163 840 (160 K) | yes | **yes** | — | — | OK |
| 196 608 (192 K) | yes | **yes** | — | — | OK |
| **229 376 (224 K)** | yes | **yes** | 7616 MiB | 476 MiB | **OK — highest working** |
| 245 760 (240 K) | yes | **NO** | 8160 MiB | 510 MiB | **`Failed to allocate physical memory`** |
| 262 144 (256 K) | yes | **NO** | 8704 MiB | 544 MiB | **SIGSEGV, ExitCode=139** |

### The failure is a load-vs-serve gap, and that is the trap

At 245 760 and 262 144 the server **loads the model successfully, reports `model loaded`, and starts
listening** — `/v1/models` returns 200. It then dies on the **first real request**:

```
SYCL error: CHECK_TRY_ERROR(phys.emplace(dev, ctx, reserve_size)): Exception caught in this line of code.
  in function alloc at /app/llama.cpp/ggml/src/ggml-sycl/ggml-sycl.cpp:1861
Failed to allocate physical memory.
  in function alloc at /app/llama.cpp/ggml/src/ggml-sycl/ggml-sycl.cpp:1861
  ggml_sycl_pool_vmm::alloc
  ggml_sycl_op_mul_mat_sycl
```

**A health check is not a context-length test.** `--ctx-size` that is too large produces a server that
looks healthy and only fails when work arrives. Anything validating a long-context config must send a
real completion.

### Why VRAM, not the model, is the binding constraint

The model's own limit is `qwen35.context_length = 262144`, so 256 K is *architecturally* allowed.
The card cannot back it. Measured accounting at the golden config:

| Component | At 128 K | At 224 K | At 256 K |
|---|---|---|---|
| Main model (SYCL0, single buffer) | 17402.38 MiB | 17402.38 MiB | 17402.38 MiB |
| MTP draft model | 1718.71 MiB | 1718.71 MiB | 1718.71 MiB |
| Main KV (q8_0) | 4352.00 MiB | 7616.00 MiB | 8704.00 MiB |
| Draft KV (q8_0) | 272.00 MiB | 476.00 MiB | 544.00 MiB |
| Recurrent state (RS) | 2394.00 MiB | 2394.00 MiB | 2394.00 MiB |
| Compute buffer | 732.28 MiB | 1372.28 MiB | 1372.28 MiB |
| **Total** | **~26.9 GiB** | **~30.9 GiB** | **~32.1 GiB** |

The card reports **32 656 MiB** total, but the largest single allocation is capped upstream as a
workaround for an open compute-runtime bug — the same mechanism the memory-splitting check watches.
KV for the main model is **34.0 KiB/token** (measured: 4352 MiB / 131072) plus **2.125 KiB/token**
for the draft, so every extra 1024 tokens of context costs ~36 MiB.

Two things to note about the arithmetic:

- The **compute buffer grows with context** (732 → 1372 MiB between 128 K and 224 K), so the cost per
  token is not purely KV.
- `n_slots` changed from **1 to 4** and `kv_unified` from `'false'` to `'true'` at these larger
  sizes. llama.cpp reshapes the slot layout when the context gets large; that changes the KV
  allocation geometry, so the headroom is not a smooth function of `--ctx-size`.

Because of that, **the boundary should be treated as approximate**: 229 376 worked, 245 760 did not,
and the true edge lies between them. It was not bisected further (see below).

## Important caveat: results above 229 376 are confounded by a device failure

Partway through this probe the **B70 wedged at the driver level** and the measurements after that
point are not trustworthy. Specifically:

- A probe at **229 376 first reported OK, then on a re-run reported LOAD_FAILED** — non-deterministic,
  which is itself the signal that the card was already degrading.
- A stale container from an earlier probe kept holding the device, and `docker rm -f` could not
  remove it; the `llama-server` process and the `xe_page_fault_work_queue` kworker were stuck in
  **D-state** and unkillable even as root.
- The `xe` driver then declared the device dead:
  ```
  xe 0000:0c:00.0: [drm] Tile0: GT0: Schedule enable failed to respond
  xe 0000:0c:00.0: [drm] Tile0: GT0: Check job timeout: seqno=690707, lrc_seqno=690707, guc_id=0, not started
  xe 0000:0c:00.0: [drm] *ERROR* CRITICAL: Xe has declared device 0000:0c:00.0 as wedged.
  xe 0000:0c:00.0: [drm] device wedged, needs recovery
  ```
- An FLR reset (`/sys/class/drm/card1/device/reset`) reported `reset done` but did not clear it.
- A PCI unbind/rebind left the device **unbound with no driver**, and SYCL now sees only the CPU:
  `sycl-ls` → no GPU platforms.

**So the "224 K works / 240 K fails" boundary is measured, but the 224 K point was observed both
passing and failing.** The honest reading:

- **128 K–192 K: solid.** 131 072 is the shipping production config and passed the entire 8-task
  suite with zero crashes; 160 K and 192 K each loaded and served a real request cleanly.
- **224 K: marginal.** Served once, failed to load on retry. Not a safe production value.
- **240 K and 256 K: fail.** Reproducible allocation failure / SIGSEGV.

**A defensible maximum for production is 192 K (196 608)** — the highest value that behaved
deterministically. **224 K should not be relied on** without re-measuring on a healthy card.

This is consistent with the `b70-backend-test` skill's note that GPU dropout on this card is
**PCIe link-training instability** (B450 board), not a driver or image defect.

> **Correction (2026-09-23).** An earlier revision of this document claimed the PCIe link had
> degraded to `2.5GT/s x1` and inferred a physical-layer failure. **That was wrong** — the numbers
> were read from the B70 endpoint (`0c:00.0`), which always reports `2.5GT/s x1` on this host because
> it describes the internal switch-to-endpoint link, not the host-facing link. The authoritative
> reading is the **Intel PCIe switch upstream port `0a:00.0`**, which showed `16GT/s x8` both before
> and after the wedge — **the link never degraded.** See
> [`B70-PCIE-LINK-RATE.md`](B70-PCIE-LINK-RATE.md) for the topology and the correct command.
>
> The wedge is therefore a **driver/GPU hang** (`xe` declared the device wedged after job timeouts),
> not a link-training event. The reboot requirement stands, but for the driver-hang reason, not a
> link reason.

A `xe`-wedged device with unkillable D-state processes requires a **host reboot** to clear; the FLR
reset and PCI rebind both failed to recover it.


## 256 K IS reachable — but not by shrinking the draft (measured 2026-09-23)

After the reboot, three configs were tested at `--ctx-size 262144`. All three **loaded**
successfully; the difference is whether they **served** a request.

| # | MTP weights | MTP KV | **Main KV** | mmproj | Result |
|---|---|---|---|---|---|
| A | Q8_0 | q8_0 | **q8_0** | CPU | ❌ SIGSEGV on 1st request (baseline) |
| B | **Q4_0** | **q4_0** | **q8_0** | **VRAM** | ❌ **SIGSEGV on 1st request** |
| C | **Q4_0** | **q4_0** | **q4_0** | **VRAM** | ✅ **WORKS — 220 022-token request served** |

### The key result: shrinking the draft does nothing

Config **B** is exactly the change that was proposed (MTP model + MTP KV to Q4, main KV left at
q8_0, mmproj moved into VRAM). It **fails identically to the baseline**, and the numbers explain why:

| Component | A (Q8_0 draft) | B (Q4_0 draft) | Δ |
|---|---|---|---|
| Main model | 17402.38 MiB | 17402.38 MiB | — |
| **Draft weights** | 1718.71 MiB | **774.71 MiB** | **−944 MiB** |
| **Main KV (q8_0, 256 K)** | 8704.00 MiB | **8704.00 MiB** | **— (untouched)** |
| Draft KV | 272.00 MiB | 288.00 MiB | +16 MiB (q4_0 KV is *larger* here) |
| RS | 2394.00 MiB | 2394.00 MiB | — |
| Compute | 1372.28 MiB | 1372.28 MiB | — |
| **Total** | **32135 MiB** | **30935 MiB** | −1200 MiB |

**Config B's total (30 935 MiB) is *below* the measured known-good 224 K total (30 979 MiB) — and it
still crashes.** That is the proof that total VRAM is not the constraint. The failure is
`ggml_sycl_pool_vmm::alloc` (ggml-sycl.cpp:1861), and what fails is the **single 8704 MiB main-KV
allocation**. Shrinking a 1719 MiB *weight* buffer does not help a 8704 MiB *KV* allocation.

> Also note the draft KV went **up** slightly (272 → 288 MiB) when moved to q4_0 at this context —
> so "Q4 everything on the draft" is not even a reliable saving on the KV side.

### The lever that actually works: main KV

Config **C** changes only the main KV type, halving the offending allocation:

```
llama_kv_cache:      SYCL0 KV buffer size =  4608.00 MiB   (q4_0 @256K; was 8704.00 with q8_0)
```

**Verified working, not just loading:**

- Real completion returns `content: "ok"`.
- 3 consecutive requests OK; `RestartCount=0`, `OOMKilled=false`, **zero** crash signatures.
- **A 220 022-token prompt was served correctly** — the full window genuinely exercised, not just
  allocated. (A separate 180 516-token prefill ran at **387.9 t/s**, so long-context prefill stays
  usable: 465 s for 180 K tokens.)
- A 40 022-token request ran at **592.3 t/s** prefill.

### Recommendation for 256 K

Use **config C**: `--cache-type-k q4_0 --cache-type-v q4_0` (main) + Q4_0 MTP draft with
`--spec-draft-type-k/v q4_0`, mmproj in VRAM. Do **not** bother with the draft-only change — it is
measurably useless for this problem.

Caveats: main KV at q4_0 costs KV precision versus the golden q8_0 (this is the trade the Vulkan
service already makes). Config C was validated for *usability and stability*, not run through the
full t1–t5/V1–V3 battery, so it is not yet a promotion candidate.

## Not measured (and why)

- **Exact boundary between 229 376 and 245 760** — the card wedged before it could be bisected.
- **Whether 224 K is genuinely stable** — needs a re-run on a healthy card; it is currently
  ambiguous in both directions.
- **Per-task performance at long context** — no decode/prefill numbers were taken at these sizes;
  this probe only established whether a context size is *usable*, not how fast it is.
- **Full-suite quality at 256 K with q4_0 KV** — config C served a 220 K-token prompt cleanly, but
  the t1–t5/V1–V3 battery has not been run against it, so answer quality at q4_0 KV is unverified.
- **Dropping the draft entirely** — no longer needed, since config C reaches 256 K with speculation
  intact.

## Practical guidance

1. **Keep production at 128 K** (`docs/GOLDEN-CONFIG.md` §3). It is the validated config.
2. **192 K (196 608)** is the highest context I would call safe on this card today, and it is worth
   re-validating before adopting.
3. **Do not set 240 K or 256 K.** They load and then crash on first use — the failure mode looks like
   a healthy server.
4. **If 256 K is genuinely needed**, the draft model is the thing to drop: `--spec-draft-model` off
   frees ~1.7 GiB of weights plus its KV, which is roughly the 1.2 GiB by which 256 K overran. That
   trades speculative decoding for context and should be measured as its own config.
5. **Before trusting any long-context number from this report above 192 K, re-measure on a
   rebooted card.**

## Evidence

| File | Contents |
|---|---|
| `test-issue20/ctx-probe/xe_wedge_dmesg.txt` | `dmesg` showing the job timeouts and the wedged declaration |
| `test-issue20/ctx-probe/switch_0a000_full.txt` | `lspci -vv` of the Intel PCIe switch upstream port — the authoritative link reading |
| `test-issue20/probe_ctx.sh`, `/tmp/probe4.sh` (on home-ai) | the probe harness |

## See also

- [`B70-PCIE-LINK-RATE.md`](B70-PCIE-LINK-RATE.md) — why the B70 endpoint's link fields are
  misleading and the Intel PCIe switch upstream port (`0a:00.0`) is the one to read.

