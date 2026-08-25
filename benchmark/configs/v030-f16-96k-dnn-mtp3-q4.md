# v030-f16-96k-dnn-mtp3-q4 — Recommended (DNN/XMX, stable)

**Recommended stable candidate**: F16 KV + 96k ctx + **MTP3/0.1** + **Q4_0 MTP draft**
on the oneDNN/XMX-enabled v0.3.0 image (`b70-u26-v30-dnn`, `GGML_SYCL_FA_ONEDNN=1`).

Replaces `v030-f16-96k-dnn-mtp4` (Q8 draft + MTP4) which left VRAM on the edge.
Same XMX prefill benefit, ~1.5 GB more VRAM headroom, faster decode, acceptance
recovered to the MTP3 level.

## Launch
```
GGML_SYCL_FA_ONEDNN=1
/app/llama-server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf --no-mmproj-offload --image-min-tokens 1024 \
  --n-gpu-layers 999 --ctx-size 98304 \
  --cache-type-k f16 --cache-type-v f16 --flash-attn on \
  --spec-draft-model /models/mtp-Qwen3.8-27B-Q4_0.gguf \
  --spec-type draft-mtp --spec-draft-n-max 3 --spec-draft-p-min 0.1 \
  --spec-draft-type-k f16 --spec-draft-type-v f16 \
  -v --host 0.0.0.0 --port 8080
```

## Key numbers (full-suite)
- prefill weighted **392 t/s** (q8_0 no-DNN baseline 212; R1-Q8-MTP4 430)
- decode weighted **26.2 t/s** (baseline 18.6; R1 22.2)
- draft acceptance block **0.5730** (≈ baseline 0.571; R1 0.475)
- TTFT med 2.5 s / max 22.3 s; Restarts=0, OOM=false