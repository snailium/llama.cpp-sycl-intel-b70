#!/usr/bin/env bash
# V1-V3 (+T1 control) with mmproj ON THE GPU. Same image (b11706), one flag flipped.
set -uo pipefail
ROOT=<workspace>
T31="$ROOT/test-issue31"
ONGPU="$ROOT/scripts/on-gpu.sh"
C=b70-mmproj-gpu-test
W="$T31/logs/windows-gpu-mmproj.txt"
lines(){ "$ONGPU" "docker logs $C 2>&1 | wc -l" 2>/dev/null | tr -d '\r' | tail -1; }
for t in t1 v1 v2 v3; do
  b=$(lines)
  echo "$t START utc=$(date -u +%FT%TZ) before=$b" | tee -a "$W"
  ( cd "$T31" && RUN="$T31" BASE=http://192.0.2.101:18082 python3 run_direct.py "$t" ) > "$T31/logs/${t}_gpu_run.log" 2>&1
  echo "  $t rc=$?"
  a=$(lines)
  echo "$t END   utc=$(date -u +%FT%TZ) after=$a" | tee -a "$W"
  cp "$T31/results/${t}_result.json" "$T31/results/${t}_gpu_result.json" 2>/dev/null
  cp "$T31/results/${t}_output."* "$T31/results/" 2>/dev/null
done
echo "GPU-MMPROJ DONE utc=$(date -u +%FT%TZ)" | tee -a "$W"
