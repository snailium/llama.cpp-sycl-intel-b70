# Intel Arc Pro B70 + llama.cpp SYCL 实战知识与经验总结 (2026-08)

> 本文档汇总了在 B70 上部署/调试/实测 llama.cpp + SYCL 的全部核心经验。  
> 目标：任何 Hermes profile 都能快速找到稳定跑 27B（尤其是带 MTP）的正确做法。  
> 基于真实 dsh/agent 长链负载验证。

## 核心结论（2026-08 定稿）

- **推荐路线**：直接使用预编译容器 `llama.cpp-sycl-b70:server`（已锁定全套运行时）。**不要自己从源码编译**（见“版本三角”）。
- **定稿配置**（最稳、5/5 全通）：**MTP3 + 96K + KV q8_0 + BF16 MTP draft + mmproj**
  - `--spec-draft-n-max 3 --spec-draft-p-min 0.1 --ctx-size 98304 --cache-type-k q8_0 --cache-type-v q8_0 --n-gpu-layers 999 --flash-attn on`
- **极限配置**（满配验证）：MTP4 + 128K + KV q8_0 也能 5/5 全通，但 decode 提升不明显。
- **MTP 关键洞见**：
  - MTP 在 agent 负载下的 OOM **是 KV 缓存空间问题**，不是 draft 本身。**必须用 q8_0**。
  - 低质量 draft（如 2B）是净拖累（acceptance 0.3~0.5），高质量 BF16 MTP 才是真加速。
- **掉卡根因**：PCIe ASPM → 加 `pcie_aspm=off` + 物理恢复流程。
- **llama.cpp 比 vLLM 慢 2-3x 的真实原因**：llama.cpp SYCL 后端**并未真正使用 XMX**（源码 TODO 实锤，见下文）。

## 1. 推荐部署方式

**强烈推荐**使用项目预编译容器：

```bash
docker run -d \
  --name b70-qwen27b \
  --device /dev/dri \
  -v /models:/models:ro \
  -p 18080:8080 \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  --entrypoint /app/full/llama-server \
  llama.cpp-sycl-b70:server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --mmproj /models/mmproj-Qwen3.8-27B-BF16.gguf \
  ...其他参数
```

**不要尝试的路线**（均失败）：
- 用 oneAPI 2026.1 自己编译上游 llama.cpp → `ggml_sycl_init` 失败 + NEO 断言。
- IPEX-LLM 容器/Portable Zip → 驱动版本三角不匹配（libze_loader ABI 问题）。
- 手动加 Intel GPU 源 → key 403 或驱动不认 B70。

## 2. 版本三角（最重要背景知识）

B70 正常工作需要三者完全锁定：

| 组件                    | 所需版本                  |
|-------------------------|---------------------------|
| B70 新驱动              | libze_intel_gpu 1.15.39122 |
| 新驱动对应 loader       | libze_loader 1.32 (ur ABI 0.12) |
| 官方 portable (2025-07) | 老 loader ~1.18.5 (ABI 0.10) |

只有特定预编译容器把 ur 0.12 + libsycl + ze 1.32 + driver 1.15.39122 全部锁死，才能用。

## 3. 运行时环境变量（必须）

```bash
export ONEAPI_DEVICE_SELECTOR=level_zero:0
export SYCL_CACHE_PERSISTENT=0     # 必须！=1 会 SIGSEGV
export ZES_ENABLE_SYSMAN=1
```

## 4. 最终推荐启动参数

**定稿配置（MTP3/96K + q8_0）**：

```bash
--ctx-size 98304 \
--cache-type-k q8_0 --cache-type-v q8_0 \
--flash-attn on \
--spec-type draft-mtp \
--spec-draft-model /models/mtp-Qwen3.8-27B-BF16.gguf \
--spec-draft-n-max 3 \
--spec-draft-p-min 0.1 \
--n-gpu-layers 999
```

**极限满配（MTP4/128K + q8_0）**：把 `--ctx-size 131072 --spec-draft-n-max 4` 即可，同样用 q8_0。

**模型栈推荐**：全用 ggml-org（Q4_K_M + mmproj-BF16 + mtp-BF16）。

## 5. MTP 调优经验

- **低质量 draft 是净拖累**：2B draft acceptance 常 0.3~0.5，拉低整体速度。
- **高质量 MTP 才值得**：BF16 MTP acceptance 通常 0.57~0.91，短任务可 +30~60%。
- n-max 越高对 KV 压力越大。n-max=4 + fp16 KV 几乎必 t4 OOM。
- p-min 0.1 是 MTP4 时的较好中性起点。
- 真实速度要看客户端 tg 或 `timings`，日志里 `eval time` 的 token/s 因投机批处理而虚高。

## 6. 内存与稳定性核心

- **KV q8_0 是 MTP + 大上下文的生命线**。fp16 KV 下 MTP 5.9GB draft 会把 KV 空间挤掉，导致 agent 长链 t4 宿主 OOM。
- 宿主内存峰值比 VRAM 更危险（曾到 26GB+ + swap）。
- "failed to fit params... n_gpu_layers 999" 是常见警告，不致命。
- 掉卡几乎全是 PCIe ASPM 导致。加 `pcie_aspm=off` 后基本根除。
- 掉卡恢复必须物理操作（拔卡 → 核显开机 → 关机 → 插回 → 开机）。

## 7. XMX 现实（为什么慢）

llama.cpp SYCL 后端**目前并未真正使用 B70 的 XMX**（Intel 矩阵单元）：

源码证据（`ggml-sycl/common.hpp`）：
```cpp
// define for XMX in Intel GPU
// TODO: currently, it's not used for XMX really.
#if !defined(GGML_SYCL_FORCE_MMQ)
    #define SYCL_USE_XMX
#endif
```

`SYCL_USE_XMX` 只是选 MMQ vs DMMV kernel，不是真的调用 DPAS/XMX 指令。

这才是 llama.cpp 比 vLLM 慢 2-3x 的主要原因（vLLM 走了 XPU 专用 XMX kernel）。

## 8. 监控与调试

```bash
# xpu-smi 后台监控
nohup bash -c 'while true; do echo "=== $(date)"; xpu-smi stats -d 0; sleep 5; done' > ~/xpu-smi-monitor.log &

# 关键日志过滤
docker logs -f <容器> | grep -E "draft acceptance|making room|fit params|GPF|initializing"

journalctl -b -xe | grep -E "llama-server|Xe|GPF"
```

## 9. 常见坑

- 永远不要加 `GGML_SYCL_DISABLE_OPT`。
- 不要用默认 intel/ggml 镜像，必须用带 B70 AOT 的自定义镜像。
- fp16 KV + MTP + ≥96k 极高概率 OOM。
- 低接受率 draft（2B）会拖慢整体速度。
- 日志 token/s 不能直接当真实速度用。

## 10. 参考资料

- 本项目 `docs/B70-TUNING.md`
- `benchmark/B70_llamacpp_mtp4_128k_q8_20260821.md`（极限 5/5 + 视觉）
- `benchmark/B70_llamacpp_mtp3q8_96k_20260821.md`（定稿 5/5）
- `benchmark/B70_gpu_dropout_20260821.md`（掉卡完整记录）
- `examples/qwen27b-server.sh`（当前推荐启动脚本）

---

**最后提醒**：目前最可靠的做法是 **预编译容器 + MTP3/96K + KV q8_0 + 全 ggml-org 栈**。

任何新配置（更高 n-max、fp16 KV、更大 ctx）都必须先验证内存和掉卡风险。
