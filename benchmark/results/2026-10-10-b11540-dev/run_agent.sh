#!/usr/bin/env bash
# Run the agent tasks (A1-A3) serially through the isolated harness, one
# disposable DSH_HOME per RUN (never production ~/.dsh), then capture the task's
# own session record for grading and metrics.
#
# Prompts come from logs/prompts.json, extracted from the pinned skill file at
# run time -- never transcribed here (Rule 5c).
set -uo pipefail
cd "$(dirname "$0")"
RUNDIR=$(cat CURRENT_RUNDIR)
TEST_HOME="$RUNDIR/dsh-home"
HARNESS=${HARNESS:-ghcr.io/snailium/dsh-container/dsh@sha256:c88327dd3686fa75b0195481a7a045e2f899345b8c79f54a6b23a8d57ddf29e5}
ONGPU=<workspace>/scripts/on-gpu.sh
WIN="$RUNDIR/logs/windows.txt"
SESS="$TEST_HOME/sessions/--workspace--"

reqs() { "$ONGPU" 'docker logs b70-dev-test-b11540 2>&1 | grep -c "draft acceptance"' 2>/dev/null | tr -d '\r' | tail -1; }

for key in "$@"; do
  prompt=$(python3 -c "import json;print(json.load(open('$RUNDIR/logs/prompts.json'))['$key'])")
  before=$(reqs)
  # snapshot the session dirs so we can identify the one this task creates
  ls "$SESS" > "$RUNDIR/logs/.sess_before_$key" 2>/dev/null || true
  echo "$key START utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_before=$before" | tee -a "$WIN"

  timeout 3600 docker run --rm --network host \
    -e DSH_MODE=headless -e DSH_TEST_PROFILE=headless_lc \
    -e DSH_TRIM_AUTO_TUNE=1 \
    -e DSH_HOME=/dsh-home -e B70_API_KEY=test -e HOME=/root \
    -v "$TEST_HOME:/dsh-home" -v "$TEST_HOME/workspace:/workspace" \
    "$HARNESS" "$prompt" > "$RUNDIR/logs/${key}_run.log" 2>&1
  rc=$?
  [ "$rc" = "124" ] && echo "TIMEOUT 1h (killed)" >> "$RUNDIR/logs/${key}_run.log"
  echo "  $key harness rc=$rc"

  after=$(reqs)
  echo "$key END   utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) req_after=$after" | tee -a "$WIN"

  # capture this task's session record(s)
  ls "$SESS" > "$RUNDIR/logs/.sess_after_$key" 2>/dev/null || true
  for d in $(comm -13 <(sort "$RUNDIR/logs/.sess_before_$key" 2>/dev/null) <(sort "$RUNDIR/logs/.sess_after_$key" 2>/dev/null)); do
    z="$SESS/$d/session.v4.jsonl.zstd"
    if [ -f "$z" ]; then
      cp "$z" "$RUNDIR/logs/${key}.session.jsonl.zstd"
      zstd -dc "$z" > "$RUNDIR/logs/${key}.session.jsonl" 2>/dev/null
      echo "  $key session: $d -> $(du -h "$RUNDIR/logs/${key}.session.jsonl" | cut -f1) decompressed"
    fi
  done
done
echo "DONE" | tee -a "$WIN"
