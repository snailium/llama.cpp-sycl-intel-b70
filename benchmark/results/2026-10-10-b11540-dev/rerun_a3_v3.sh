#!/usr/bin/env bash
# A3 retest #3: harness sha256:a415474b (repeat-tool-breaker 0.8.7 -> 0.11.3).
# Same backend container, same prompt, same golden config. Harness is the only variable.
set -uo pipefail
R3=$(cat <workspace>/test-issue29/run/CURRENT_R3)
TH="$R3/dsh-home"
HARNESS=ghcr.io/snailium/dsh-container/dsh@sha256:a415474b95eae95d342921223bd6a46d3f82b762c1a30ba9a63b88ee296e4e20
ONGPU=<workspace>/scripts/on-gpu.sh
WIN="$R3/logs/windows.txt"
SESS="$TH/sessions/--workspace--"

reqs() { "$ONGPU" 'docker logs b70-dev-test-b11540 2>&1 | grep -c "draft acceptance"' 2>/dev/null | tr -d '\r' | tail -1; }

prompt=$(python3 -c "import json;print(json.load(open('$R3/logs/prompts.json'))['a3_snowfall'])")
before=$(reqs)
ls "$SESS" > "$R3/logs/.sess_before" 2>/dev/null || true
echo "a3_snowfall START utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_before=$before" | tee -a "$WIN"

timeout 3600 docker run --rm --network host \
  -e DSH_MODE=headless -e DSH_TEST_PROFILE=headless_lc \
  -e DSH_TRIM_AUTO_TUNE=1 \
  -e DSH_HOME=/dsh-home -e B70_API_KEY=test -e HOME=/root \
  -v "$TH:/dsh-home" -v "$TH/workspace:/workspace" \
  "$HARNESS" "$prompt" > "$R3/logs/a3_snowfall_run.log" 2>&1
rc=$?
[ "$rc" = "124" ] && echo "TIMEOUT 1h (killed)" >> "$R3/logs/a3_snowfall_run.log"
echo "  harness rc=$rc"

after=$(reqs)
echo "a3_snowfall END   utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_after=$after" | tee -a "$WIN"

ls "$SESS" > "$R3/logs/.sess_after" 2>/dev/null || true
for d in $(comm -13 <(sort "$R3/logs/.sess_before" 2>/dev/null) <(sort "$R3/logs/.sess_after" 2>/dev/null)); do
  z="$SESS/$d/session.v4.jsonl.zstd"
  if [ -f "$z" ]; then
    cp "$z" "$R3/logs/a3_snowfall.session.v4.jsonl.zstd"
    zstd -dc "$z" > "$R3/logs/a3_snowfall.session.jsonl" 2>/dev/null
    echo "  session: $d"
  fi
done
echo DONE | tee -a "$WIN"
