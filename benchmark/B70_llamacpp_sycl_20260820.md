# llama.cpp+SYCL on B70 —— dsh 三任务重测汇总(2026-08-20)

> 环境基准：B70 容器 `b70-llama-draft-128k`
> 后端：llama.cpp SYCL（`llama.cpp-sycl-b70:server`，端点 :18080/v1）
> 模型：主 Qwen3.8-27B-Q4_K_M.gguf + draft Qwen3.5-2B-Q4_K_M.gguf（draft-simple, n_max 4）
> 本次配置变更（用户重配）：**KV 缓存 fp16 → q8_0，draft 4B → 2B**，仍 128K 上下文

---

## 1. 修复背景（为什么重测）

此前容器灾难级慢（**0.2 t/s decode**），根因：
`n_ctx=131072 × n_slots=4` 的 **fp16 统一 KV 缓存 ~33GB > 32GB VRAM** → KV 溢出到宿主 RAM → SYCL host↔device 传输拖死（日志：`failed to fit params to free device memory: n_gpu_layers already set to 999, abort`）。

修复 = KV→q8_0（减半）+ draft 4B→2B。对照 vLLM qw38 侧用的是 `--kv-cache-dtype fp8` 才塞进 128K；llama.cpp 等效 = `--cache-type-k/v q8_0`。

**修复后实测**：decode **13.4 t/s** / prompt 62.9 t/s / 显存 20GB(30GB 无溢出) / CPU ~100%；小请求可达 21 t/s。

> ⚠️ 读日志口径注意：llama.cpp 每块 `eval time` 批处理 token/s（33-143 t/s）是**并行投机批吞吐**，非客户端实际速率；客户端感知 = 流式 `tg` ~9-13 t/s。

---

## 2. 单发基准（干净可对比 decode t/s，对标 vLLM 的 C1 测速）

| 项 | 值 |
|---|---|
| decode | **13.38 t/s**（400 tok / 29.9s） |
| prompt | 62.9 t/s（75 tok） |
| draft acceptance | 0.314（161 accepted / 512 generated） |
| 小请求(96 tok) | ~21 t/s（draft acceptance 0.676） |

> vs vLLM-MTP：83.7 t/s(BF16 draft) / 112 t/s(INT4 draft) → llama.cpp 单发约慢 ~6×。

---

## 3. dsh 三任务结果（headless_lc profile, 2026-08-20）

| 任务 | 时长 | 结果 | draft acceptance |
|---|---|---|---|
| t3 安全审查(mqtt2ha) | **40m51s** | ✅ EXIT=0 | **0.338**（12 样本） |
| t4 宿主机JSON | **4m11s** | ✅ EXIT=0 | **0.449**（4 样本） |
| t5 YOW降雪 | **29m27s** | ✅ EXIT=0 | **0.497**（34 样本） |

### draft acceptance rate 明细（新增指标，grep llama.cpp 日志 `draft acceptance`）

| 场景 | rate | 样本 |
|---|---|---|
| 单发小测(96 tok) | 0.676 | 1 |
| 单发长文(400 tok) | 0.314 | 1 |
| t3 | 0.338 | 12 |
| t4 | 0.449 | 4 |
| t5 | 0.497 | 34 |

2B draft 的 acceptance 波动 0.31–0.68、典型 0.34–0.50，mean len 2.3–3.7（低接受率→更多重算→拉低有效 t/s）。

### 提取方法
```bash
docker logs --timestamps b70-llama-draft-128k 2>&1 | grep 'draft acceptance'
# 再按 UTC 时间窗口（docker 日志为 UTC，本地 EDT 减 4h）分段汇总各任务
```

---

## 4. 与 vLLM-MTP 对比（同机同任务同方法）

| 任务 | **llama.cpp SYCL (q8+draft2B)** | vLLM-MTP (qw38) | 判定 |
|---|---|---|---|
| t3 安全审查 | ✅ 40m51s (draft 0.338) | ✅ 31m48s | llama.cpp 慢 ~28% |
| t4 宿主JSON | ✅ 4m11s (draft 0.449) | ✅ 1m51s | llama.cpp 慢 ~2.3× |
| t5 YOW降雪 | ✅ **29m27s** (draft 0.497) | ❌ 崩 2/2 (7s/6s) | **llama.cpp 完胜** |
| 单发 decode | **13.4 t/s** | 83.7(BF16)/112(INT4) t/s | vLLM 快 ~6× |

补充：
- non-MTP vLLM t5 = 32m23s（llama.cpp 29m27s 相当）
- vLLM-MTP 崩溃根因 = `causal_conv1d` 混 spec/non-spec token（`vllm-project/vllm-xpu-kernels#510`）

---

## 5. 核心结论

**llama.cpp SYCL 是第一个把 dsh 三任务全部确定跑通的 B70 后端（3/3 EXIT=0）** —— 正好补上 vLLM-MTP 在 t5 崩 2/2 的坑。代价是单发解码显著慢于 vLLM。

**务实分工**：
- 长 agent / 工具链 → **优先 llama.cpp**（确定性成功 > 速度）
- 能容忍偶发崩、要吞吐的重 benchmark → vLLM-MTP
- llama.cpp GGUF+SYCL 达不到 vLLM 83 t/s 的早期预判成立

**B70 后端稳定性现状**：llama.cpp(3/3稳定) > vLLM non-MTP(可用但慢) > vLLM-MTP(快但 agent 负载崩)。

---

## 6. 参考资料

- 原始输出：`workspace/dsh_results/B70_lc_t3_20260820.md` / `B70_lc_t4_20260820.md` / `B70_lc_t5_20260820.md`
- 后端启动配置：镜像 `llama.cpp-sycl-b70:server`，端口 18080→8080，模型 id `/models/Qwen3.8-27B-Q4_K_M.gguf`
- 调用：`dsh --profile headless_lc \"<task>\"`（provider `lc` → :18080/v1，ctx 131072）
- 本次关键调优：`--cache-type-k q8_0 --cache-type-v q8_0`（解决 128k KV 显存溢出）
- Draft：Qwen3.5-2B-Q4_K_M.gguf（vocab 匹配）
