#!/usr/bin/env bash
# Run the direct (non-agent) tasks serially and record per-task window markers.
# Window marker = the number of completed requests on the server, counted by
# `draft acceptance` lines (exactly one per finished request). This is robust
# where a line-count window is not (with -v a request body is one huge line).
set -uo pipefail
cd "$(dirname "$0")"
RUNDIR=$(cat CURRENT_RUNDIR)
export RUNDIR
export B70_BASE=http://192.0.2.101:18082
export B70_MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf
WIN="$RUNDIR/logs/windows.txt"
ONGPU=<workspace>/scripts/on-gpu.sh

reqs() { "$ONGPU" 'docker logs b70-dev-test-b11540 2>&1 | grep -c "draft acceptance"' 2>/dev/null | tr -d '\r' | tail -1; }

for task in "$@"; do
  before=$(reqs)
  echo "$task START utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_before=$before" | tee -a "$WIN"
  python3 runner.py "$task" 2>&1 | tail -3
  after=$(reqs)
  echo "$task END   utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_after=$after" | tee -a "$WIN"
done
echo "DONE" | tee -a "$WIN"
