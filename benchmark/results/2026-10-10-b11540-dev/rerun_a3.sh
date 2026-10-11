#!/usr/bin/env bash
# A3 retest on the NEW harness (sha256:3c525ab3...), same backend, same prompt.
set -uo pipefail
R2=<workspace>/test-issue29/run/20261011-rerun-a3
TH="$R2/dsh-home"
HARNESS=ghcr.io/snailium/dsh-container/dsh@sha256:3c525ab3c5d9d9c95a89797d4452e5bfd73c32de47e5b5e4fb41a6cd02dce820
ONGPU=<workspace>/scripts/on-gpu.sh
WIN="$R2/logs/windows.txt"
SESS="$TH/sessions/--workspace--"

reqs() { "$ONGPU" 'docker logs b70-dev-test-b11540 2>&1 | grep -c "draft acceptance"' 2>/dev/null | tr -d '\r' | tail -1; }

prompt=$(python3 -c "import json;print(json.load(open('$R2/logs/prompts.json'))['a3_snowfall'])")
before=$(reqs)
ls "$SESS" > "$R2/logs/.sess_before" 2>/dev/null || true
echo "a3_snowfall START utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_before=$before" | tee -a "$WIN"

timeout 3600 docker run --rm --network host \
  -e DSH_MODE=headless -e DSH_TEST_PROFILE=headless_lc \
  -e DSH_TRIM_AUTO_TUNE=1 \
  -e DSH_HOME=/dsh-home -e B70_API_KEY=test -e HOME=/root \
  -v "$TH:/dsh-home" -v "$TH/workspace:/workspace" \
  "$HARNESS" "$prompt" > "$R2/logs/a3_snowfall_run.log" 2>&1
rc=$?
[ "$rc" = "124" ] && echo "TIMEOUT 1h (killed)" >> "$R2/logs/a3_snowfall_run.log"
echo "  harness rc=$rc"

after=$(reqs)
echo "a3_snowfall END   utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_after=$after" | tee -a "$WIN"

ls "$SESS" > "$R2/logs/.sess_after" 2>/dev/null || true
for d in $(comm -13 <(sort "$R2/logs/.sess_before" 2>/dev/null) <(sort "$R2/logs/.sess_after" 2>/dev/null)); do
  z="$SESS/$d/session.v4.jsonl.zstd"
  if [ -f "$z" ]; then
    cp "$z" "$R2/logs/a3_snowfall.session.v4.jsonl.zstd"
    zstd -dc "$z" > "$R2/logs/a3_snowfall.session.jsonl" 2>/dev/null
    echo "  session: $d"
  fi
done
echo DONE | tee -a "$WIN"
