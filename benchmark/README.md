# Benchmarks

This directory contains performance and stability benchmarks for llama.cpp SYCL on Intel Arc Pro B70.

## Guidelines

- One file per significant test run / date / config.
- Include at minimum:
  - Exact model + quant (main + draft if using speculative)
  - Context size
  - KV cache type (`--cache-type-k/v`)
  - Draft settings (`--spec-type`, draft model, n-max)
  - Key metrics: decode t/s, prompt t/s, draft acceptance rate, wall time for agentic tasks
  - Full command / container launch flags
  - Comparison when available (e.g. vs vLLM)
- For dsh/agentic tasks, record both EXIT status and draft acceptance per task.

## Files

- [B70_llamacpp_sycl_20260820.md](./B70_llamacpp_sycl_20260820.md) — dsh t3/t4/t5 + single-shot benchmarks with Qwen3.8-27B-Q4_K_M + 2B draft + q8_0 KV (2026-08-20)

## Future runs

When adding new benchmarks:
1. Copy this format.
2. Name files as `B70_<config>_<YYYYMMDD>.md` or similar.
3. Update the main README.md "Benchmarks" section with a link.
4. Consider adding raw logs or harness sessions as attachments if useful.

See also: `docs/B70-TUNING.md` for tuning notes and `examples/qwen27b-server.sh` for launch examples.

- **[当前推荐配置 / Current recommended] `results/2026-09-01-mtp3-ab.md`** — **MTP3 (`--spec-draft-n-max 3`) is the recommended production config for agent/dsh load** on B70. A/B vs MTP4 (same `server-dev-b10731`, 128k + q8_0 KV + Q8_0 draft): MTP3 decode t/s higher on every agent task (T3 19.6 vs 17.6, T4 34.5 vs 26.7, T5 28.8 vs 25.5), draft-acc up (0.58 vs 0.51), and wall clock dramatically shorter (t3 23.6→15.5min, t5 14.7→11min). MTP4's 4th position collapses under agent loads (pos4 acc 0.38–0.50) → drop to MTP3. Launcher: `examples/qwen27b-server.sh` (now MTP3). (2026-09-01)

- [B70_llamacpp_nodraft_vision_20260820.md](./B70_llamacpp_nodraft_vision_20260820.md) — **独立报告**：无 draft + 多模态 (mmproj-BF16) + 128k ctx，dsh t3/t4/t5 全通 (2026-08-20/21)。核心结论：移除低 acceptance draft 后 t3/t4 明显更快，多模态对纯文本/工具调用无干扰。
- [B70_gpu_dropout_20260821.md](./B70_gpu_dropout_20260821.md) — **GPU dropout incident report** (B70 disappeared after reboot). Detailed comparison with prior incidents, symptoms, log evidence, and mitigations. (2026-08-21)

- [B70_llamacpp_mtp3q8_96k_20260821.md](./B70_llamacpp_mtp3q8_96k_20260821.md) — **定稿配置**：MTP3 (`n-max=3, p-min=0.1`) + 96k ctx + KV q8_0 + BF16 MTP draft + mmproj。**首次 5/5 全通**（t1~t5）。核心结论：KV q8_0 解决 MTP + 长上下文宿主 OOM；真实 decode ≈33-35 t/s，acceptance 0.57~0.85。PCIe ASPM 关闭防止掉卡。(2026-08-21)

- [B70_llamacpp_mtp4_128k_q8_20260821.md](./B70_llamacpp_mtp4_128k_q8_20260821.md) — **最终盖棺定论报告**：MTP4 + 128K + KV q8_0 + 全 ggml-org 栈（主模型 + mmproj + BF16 MTP）。**首次 5 文本全通（5/5） + 3 真实图像测试**。TTFT ~0.88s，decode 36~41 t/s，agent 长链 acceptance 0.50~0.58。视觉质量与双卡 3060 27b 一致但较慢。**(2026-08-21) ⚠️ agent 负载已被 MTP3 取代（见 results/2026-09-01-mtp3-ab.md）；保留作为满上下文极限 fallback。**

> 注：在 `B70_llamacpp_mtp4_128k_q8_20260821.md` 末尾新增了「与 vLLM-MTP 的速度差异分析」章节，解释了为什么 vLLM-MTP 在单发短任务上显著更快，以及在真实 agent 长链负载下的实际权衡。
