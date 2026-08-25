# v030-f16-96k-dnn-mtp4 — oneDNN XMX prefill experiment (F16 KV, MTP4)

> **Superseded 2026-08-25** by [`v030-f16-96k-dnn-mtp3-q4`](./v030-f16-96k-dnn-mtp3-q4.md)
> (Q4 draft + MTP3: same XMX prefill, faster decode, +1.5GB VRAM headroom, acceptance
> recovered to 0.573).

Experimental candidate: **F16 KV + 96k ctx + MTP4/0.1** on the **oneDNN/XMX-enabled**
v0.3.0 image (`b70-u26-v30-dnn`, `-DGGML_SYCL_DNN=ON`), run with
`GGML_SYCL_FA_ONEDNN=1` to route eligible flash-attention prefills through the
XMX systolic path (llama.cpp #25222). Measured prefill ≈ 2× vs the q8_0 no-DNN
baseline, but **VRAM is on the edge (easy OOM)** → superseded by the safer
`v030-f16-96k-dnn-mtp3-q4` config.

## Launch
```
GGML_SYCL_FA_ONEDNN=1    # env, enables the onednn XMX dispatch
/app/llama-server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf --no-mmproj-offload --image-min-tokens 1024 \
  --n-gpu-layers 999 --ctx-size 98304 \
  --cache-type-k f16 --cache-type-v f16 --flash-attn on \
  --spec-draft-model /models/mtp-Qwen3.8-27B-Q8_0.gguf \
  --spec-type draft-mtp --spec-draft-n-max 4 --spec-draft-p-min 0.1 \
  --spec-draft-type-k f16 --spec-draft-type-v f16 \
  -v --host 0.0.0.0 --port 8080
```

## Key numbers
- prefill weighted **430 t/s** (q8_0 no-DNN baseline 212) — deep-ctx 487–580 t/s
- decode weighted **22.2 t/s** (baseline 18.6); short prompts <512 tok stay ~119 t/s (mmproj/CPU)
- draft acceptance block 0.475 / req-mean 0.578
- 0 crashes/restarts across the full suite

## VRAM caution
F16 KV (+ MTP4 + 96k) leaves little VRAM headroom — reproducible OOM risk under
long agent runs. Instead of F16 KV you pay ~2× KV memory vs q8_0; combined with
MTP4 the margin is thin on 32 GB.