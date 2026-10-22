#!/usr/bin/env bash
# Run the agent tasks (A1-A3) serially through the isolated harness, one
# disposable DSH_HOME per RUN (never production ~/.dsh), then capture the task's
# own session record for grading and metrics.
#
# Prompts come from logs/prompts.json, extracted from the pinned skill file at
# run time -- never transcribed here (Rule 5c).
set -uo pipefail
ISSUE30=<workspace>/test-issue30
RUNDIR="$ISSUE30/run/20261016-issue30"
TEST_HOME="$RUNDIR/dsh-home"
HARNESS=ghcr.io/snailium/dsh-container/dsh@sha256:8ae9360ede0369dcaf37c203e849500dd9b5b5e71c4193951817dcfc4746c521
ONGPU=<workspace>/scripts/on-gpu.sh
WIN="$ISSUE30/logs/windows.txt"
LOGS="$ISSUE30/logs"
SESS="$TEST_HOME/sessions/--workspace--"
CONTAINER=b70-dev-test-v070

reqs() { "$ONGPU" "docker logs $CONTAINER 2>&1 | grep -c 'draft acceptance'" 2>/dev/null | tr -d '\r' | tail -1; }
lines() { "$ONGPU" "docker logs $CONTAINER 2>&1 | wc -l" 2>/dev/null | tr -d '\r' | tail -1; }

for key in "$@"; do
  prompt=$(python3 -c "import json;print(json.load(open('$LOGS/prompts.json'))['$key'])")
  before=$(lines)
  ls "$SESS" > "$LOGS/.sess_before_$key" 2>/dev/null || true
  echo "$key START utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) logline_before=$before" | tee -a "$WIN"

  timeout 3600 docker run --rm --network host \
    -e DSH_MODE=headless -e DSH_TEST_PROFILE=headless_lc \
    -e DSH_TRIM_AUTO_TUNE=1 \
    -e DSH_HOME=/dsh-home -e B70_API_KEY=test -e HOME=/root \
    -v "$TEST_HOME:/dsh-home" -v "$TEST_HOME/workspace:/workspace" \
    "$HARNESS" "$prompt" > "$LOGS/${key}_run.log" 2>&1
  rc=$?
  [ "$rc" = "124" ] && echo "TIMEOUT 1h (killed)" >> "$LOGS/${key}_run.log"
  echo "  $key harness rc=$rc"

  after=$(lines)
  echo "$key END   utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) logline_after=$after" | tee -a "$WIN"

  ls "$SESS" > "$LOGS/.sess_after_$key" 2>/dev/null || true
  for d in $(comm -13 <(sort "$LOGS/.sess_before_$key" 2>/dev/null) <(sort "$LOGS/.sess_after_$key" 2>/dev/null)); do
    z="$SESS/$d/session.v4.jsonl.zstd"
    if [ -f "$z" ]; then
      cp "$z" "$LOGS/${key}.session.jsonl.zstd"
      zstd -dc "$z" > "$LOGS/${key}.session.jsonl" 2>/dev/null
      echo "  $key session: $d -> $(du -h "$LOGS/${key}.session.jsonl" | cut -f1) decompressed"
    fi
  done
done
echo "AGENT TASKS DONE" | tee -a "$WIN"
