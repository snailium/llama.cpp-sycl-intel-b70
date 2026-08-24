# 2026-08-21 — GPU Dropout Incident

## Summary

The discrete B70 disappeared from the PCIe bus after a reboot following heavy load with an external BF16 MTP draft model on a B450 platform.

- **Date/Time:** crash ~05:22, reboot completed ~05:28.
- **Container:** `b70-qwen27b-ggmlorg-mtp` (exit 255).
- **Trigger:** `Qwen3.8-27B-Q4_K_M` + `mmproj-BF16` + `MTP-BF16` (5.6 GB external) + 128k ctx + `--spec-draft-n-max 4` + full offload.

## Platform clarification (important)

- **Normal operation:** the B70 is plugged **directly** into the B450 motherboard slot; no riser/extension in daily use.
- An extension cable was used **only** as a temporary recovery tool.
- **Even with direct insertion, the card still drops off the bus after heavy load.**

## Symptoms

- Repeated `traps: llama-server[...] general protection fault ... in libc.so.6`.
- Very high container memory usage (10.9G–25.5G peaks + significant swap).
- Post-reboot: B70 **completely missing from `lspci`** (only the onboard NIC at 03:00.0 + AMD iGPU remaining).
- `sycl-ls` no longer sees the card.

## Recovery attempts

**Did not fully restore:**
- Using the extension cable.
- Changing the PCIe slot.

**Successful recovery (user-tested):**
1. Physically remove the B70.
2. Boot the system (runs on the iGPU).
3. Shut down cleanly.
4. Re-insert the GPU directly into the motherboard slot.
5. Power on → B70 reappears.

This remove → boot-without-it → shutdown → reinsert → boot cycle forces a clean PCIe link-training cycle.

## Comparison with previous dropout incidents

| Aspect | Previous incidents | 2026-08-21 incident |
|--------|--------------------|---------------------|
| Normal mounting | Direct or riser (mixed) | **Direct insertion** on B450 |
| Trigger | Heavy speculative/MTP + high ctx | Same (MTP-BF16 + 128k + n-max=4) |
| Kernel symptoms | Xe Fault -ENOMEM, CAT, engine reset | Repeated GPF in llama-server (libc) |
| Memory evidence | High VRAM pressure | Documented 10.9G–25.5G peaks + host swap |
| Post-reboot state | B70 missing in `lspci` | Identical |
| Recovery | Hard power cycle + extension trick | Hard power cycle insufficient; required remove/reboot/reinsert cycle |
| Platform note | B450 + riser suspected | Confirmed even with **direct slot** on B450 |

**Common pattern:** adding the large external MTP-BF16 draft on top of 27B + 128k context reliably triggers link drops on this B450 platform.

**Key difference this time:** clear confirmation that the **riser is not required** to reproduce the problem. The issue is the B450 chipset's ability to recover the PCIe link after GPU-side faults.

## Root cause

Heavy load (especially external MTP-BF16) causes GPU/driver faults on the B70. On B450 the PCIe link enters a bad state that a normal power cycle cannot clear; the "boot without the device" sequence is needed to force proper re-enumeration.

## Recommended mitigations

- Treat large external MTP-BF16 drafts as **high-risk** on B450 + 32GB B70 + 128k context.
- Default to **no external draft** or conservative settings (`--spec-draft-n-max 2` or lower).
- For 128k, **prefer q8_0 KV** (see `benchmark/METHODOLOGY.md` §4).
- Use the remove / boot / reinsert recovery when standard methods fail.
- Monitor for early link-trouble signs (sudden performance collapse, repeated GPFs).

## Files

- This report: `benchmark/incidents/2026-08-21-gpu-dropout.md`
- Platform / PCIe section of the tuning guide: `docs/B70-TUNING.md` §9.

**Status as of writing:** recovery procedure documented; recommend testing lighter configs after the next clean boot.