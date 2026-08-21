# llama.cpp SYCL on B70 —— 无draft + 多模态(128K)独立报告(2026-08-20/21)

> **独立报告,不合并**对应上轮 `B70_llamacpp_sycl_20260820.md`(draft2B 配置)。本报告为一个独立配置变体,nodraft+mmproj+128K。
> 后端：llama.cpp SYCL 容器 **`b70-qwen27b-vision`**(端点 :18080/v1)。
> 模型：主 Qwen3.8-27B-Q4_K_M.gguf + **mmproj-Qwen3.8-27B-bf16.gguf(视觉,931MB)**。
> 配置差异(相对上轮)：**draft 投机已拆**(无 `-md`/spec-type)、**加多模态 mmproj**、ctx 由 131072 维持(用户本轮再给 128K)。
> 启动命令：`-m /models/Qwen3.8-27B-Q4_K_M.gguf --mmproj /models/mmproj-Qwen3.8-27B-bf16.gguf --no-mmproj-offload --image-min-tokens 1024 --n-gpu-layers 999 --ctx-size 131072 --flash-attn on`。

---

## 1. 冒烟验证(启动后)
- 端点 `/v1/models` 正常，模型 id `/models/Qwen3.8-27B-Q4_K_M.gguf`
- 定时文本：decode **23.2 t/s**(200 tok / 8.6s)；无 KV 溢出、容器 CPU 100%、内存正常
- 验证结论：**视觉投影器 mmproj 不影响纯文本/工具调用**(无 draft 单流正常)

---

## 2. dsh 三任务结果(profile headless_lc, 2026-08-20)

| 任务 | 时长 | 结果 | decode tokens | **token rate** |
|---|---|---|---|---|
| t3 安全审查(mqtt2ha) | **21m04s** | ✅ EXIT=0 | ~56.7k | **~44.8 tok/s** |
| t4 宿主机JSON | **3m20s** | ✅ EXIT=0 | ~16.2k | **~81.0 tok/s** |
| t5 YOW降雪 | **1h07m02s** | ✅ EXIT=0 | ~92.9k | **~23.1 tok/s** |

> token rate = llama.cpp 日志 `eval time` 聚合 decode token 数 ÷ 任务整轮耗时(含思考/间隔)。
> 单流持续稳态 decode ≈ **15–23 t/s**(t5 长连续生成落到 ~23；t3/t4 短突发较高)。
> 无 draft → **本轮无 draft acceptance rate 指标**(那是带投机才有)。

---

## 3. 环回检测(应对"是否卡死/死循环"疑虑)
解析 dsh 会话 `session.jsonl.zstd`(1.2 万行)——**非死循环**：
- 89 次工具调用 = 88 bash + 1 web_search，横跨 83 步；**相邻无重复命令**
- t5 慢的根因 = agent 选了 ECCC `api.weather.gc.ca` 官方 API 死磕路线，反复试 STN_ID/PROVINCE_CODE 查询格式(真实试错、非卡死)
- 结论：**低效过度探索**(agent 行为方差)而非引擎卡死

---

## 4. t5 结果质量(严谨,双源交叉)
- YOW 实测降雪 **258.6 cm**(截至 2026-08-18, 逐日序列 + ERA5 交叉验证)
- 气候均补未来 135 天 ~74.8 cm → 全窗 2025-11-01~2026-12-31 最佳估计 **~333 cm(±33 cm)**
- 产出: report.md / yow_daily_snow_*.csv / yow_obs.csv / yow_era5.json / ottawa_ccn.csv

---

## 5. 与各配置/后端对比(dsh 三任务时长)

| 任务 | **本轮 nodraft+mmproj(128K)** | 上轮 draft2B(128K) | vLLM-MTP | vLLM non-MTP |
|---|---|---|---|---|
| t3 | **21m04s** ✅ | 40m51s ✅ | 31m48s ✅ | 3h00m ❌(撞ctx) |
| t4 | **3m20s** ✅ | 4m11s ✅ | 1m51s ✅ | 17m/16m58s |
| t5 | **1h07m02s** ✅ | 29m27s ✅ | 崩2/2 ❌ | 32m23s ✅ |

**关键洞察**：
1. **拆 draft 让 t3/t4 更快**(21m vs 40m;3m20 vs 4m11)——2B draft 在 acceptance 0.34~0.50 下是**净拖累**,拆掉反而提速。
2. **t5 慢 = agent 选了重 API 探索路线**(88 次 bash 铲 ECCC),非引擎回退(token 量 9.3 万可见)。
3. 多模态容器跑纯文本 dsh = 3/3 稳定,视觉投影器零干扰。
4. **llama.cpp 仍是 B70 上唯一 dsh 三任务全通的稳定后端**(vLLM-MTP 在 t5 崩)。

---

## 6. 存档
- 原始输出：`workspace/dsh_results/B70_lc_vis_t{3,4,5}_20260820.md`
- 会话流：``[redacted local harness session path]``
- 取证方法(循环检测/工具调用)：`zstd -dc <session> > /tmp/s.jsonl` 后按 `type: tool/call` + `data.arguments.command` 解析
