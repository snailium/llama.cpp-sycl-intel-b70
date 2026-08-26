# 2026-08-21 — GPU Dropout Incident

## Summary

The discrete B70 disappeared from the PCIe bus after a reboot (`lspci` no longer showed it). Root cause: **B450 motherboard PCIe link-training instability** — the board can drop the card from the bus. This is a board-level issue, **unrelated to any riser/extension cable**, and can be triggered by a plain reboot (not only heavy load).

- **Date/Time:** crash ~05:22, reboot completed ~05:28.
- **Container:** `b70-qwen27b-ggmlorg-mtp` (exit 255).

## Symptoms

- Repeated `traps: llama-server[...] general protection fault ... in libc.so.6`.
- Very high container memory usage (10.9G–25.5G peaks + significant swap).
- Post-reboot: B70 **completely missing from `lspci`** (only the onboard NIC + AMD iGPU remain); `sycl-ls` no longer sees the card; `/dev/dri` only has the iGPU, so the `xe` module has nothing to drive.

## Recovery (unchanged)

1. Power off completely.
2. Physically remove the B70.
3. Boot the system (runs on the iGPU).
4. Shut down cleanly.
5. Re-insert the B70 into the motherboard slot.
6. Power on → B70 reappears.

This remove → boot-without-it → shutdown → reinsert → boot cycle forces a clean PCIe link-training cycle. **The card must be physically reseated; a normal power cycle alone does not clear the bad link state.**

## Root cause

**B450 motherboard PCIe link-training instability.** The board can lose the B70 from the bus; a reboot does not reliably re-standardize the link, so the physical reseat sequence is required to force proper re-enumeration. Experience since the incident shows the dropout can also be triggered by a plain reboot — it is **not** specific to heavy/stress loads, and it is **unrelated to riser/extension cables**.

## Mitigations

- `pcie_aspm=off` in the kernel cmdline (`GRUB_CMDLINE_LINUX_DEFAULT="pcie_aspm=off"` + `update-grub` + reboot) — applied as a stability mitigation on the B450.
- Use the physical reseat recovery whenever the card drops off the bus.
- Monitor `dmesg | grep -iE 'xe|pcie|fault'` for early signs after incidents.

## Files

- This report: `benchmark/incidents/2026-08-21-gpu-dropout.md`
- Platform / PCIe section of the tuning guide: `docs/B70-TUNING.md` §9.

**Status as of writing:** root cause identified as B450 link-training instability; recovery procedure unchanged and documented.