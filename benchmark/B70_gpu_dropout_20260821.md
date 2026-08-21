# B70 GPU Dropout Incident — 2026-08-21

## Summary
Discrete B70 disappeared after reboot following heavy load with external MTP-BF16 draft model on a B450 platform.

**Date/Time**: Crash around 2026-08-21 05:22, reboot completed ~05:28.
**Container**: b70-qwen27b-ggmlorg-mtp (exit 255)
**Trigger**: ggml-org Qwen3.8-27B-Q4_K_M + mmproj-BF16 + MTP-BF16 (5.6 GB external) + 128k ctx + --spec-draft-n-max 4 + full offload

## Platform Clarification (Important)
- **Normal operation**: B70 is plugged **directly** into the B450 motherboard. No riser/extension is used in daily use.
- The extension cable was used **only** as a temporary tool during recovery attempts.
- Even with direct insertion, the card still drops off the bus after heavy loads.

## Symptoms
- Repeated `traps: llama-server[...] general protection fault ... in libc.so.6`
- Very high memory usage in containers (10.9G–25.5G peaks + significant swap)
- Post-reboot: B70 completely missing from `lspci` (only I211 at 03:00.0 + AMD iGPU)
- `sycl-ls` no longer sees the card

## Recovery Attempts
**Did not fully restore**:
- Using extension cable
- Changing PCIe slot

**Successful recovery** (user tested):
1. Physically remove the B70.
2. Boot the system (runs on iGPU).
3. Shut down cleanly.
4. Re-insert the GPU directly into the motherboard.
5. Power on → B70 reappears.

This "remove → boot without it → shutdown → reinsert → boot" sequence forces a clean PCIe link training cycle.

## Comparison with Previous Dropout Incidents

| Aspect                  | Previous Incidents                          | 2026-08-21 Incident                              |
|-------------------------|---------------------------------------------|--------------------------------------------------|
| Normal mounting         | Direct or riser (mixed reports)             | **Direct insertion** on B450                     |
| Trigger                 | Heavy speculative/MTP + high ctx            | Same (MTP-BF16 + 128k + n-max=4)                 |
| Kernel symptoms         | Xe Fault -ENOMEM, CAT, engine reset         | Repeated GPF in llama-server (libc)              |
| Memory evidence         | High VRAM pressure                          | Documented 10.9G–25.5G peaks + host swap         |
| Post-reboot state       | B70 missing in lspci                        | Identical                                        |
| Recovery                | Hard power cycle + extension trick          | Hard power cycle insufficient; required remove/boot/reinsert cycle |
| Platform note           | B450 + riser suspected in some cases        | Confirmed even with **direct slot** on B450      |

**Common pattern**: Adding the large external MTP-BF16 draft on top of 27B + 128k context reliably triggers link drops on this B450 platform.

**Key difference this time**: Clear confirmation that the riser is **not** required to reproduce the problem. The issue is in the B450 chipset's ability to recover the PCIe link after GPU-side faults.

## Root Cause
Heavy workload (especially external MTP-BF16) causes GPU/driver errors on the B70. On B450, the PCIe link enters a bad state that normal power cycles cannot clear. The "boot without the device" sequence is needed to force proper re-enumeration.

## Recommended Mitigations
- Treat external large MTP-BF16 drafts as high-risk on B450 + 32GB B70 with 128k context.
- Default to no external draft or very conservative settings (--spec-draft-n-max 2 or lower).
- For 128k, prefer q8_0 KV cache.
- Document and use the remove/boot/reinsert recovery when standard methods fail.
- Consider monitoring for early signs of link trouble (sudden performance collapse, repeated GPFs).

## Files
- This report: `benchmark/B70_gpu_dropout_20260821.md`
- Tuning guide: `docs/B70-TUNING.md` §9 (PCIe Link Training Issues)

**Status as of writing**: Recovery procedure documented. Recommend testing lighter configs after next clean boot.
