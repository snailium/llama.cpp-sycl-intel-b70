#!/usr/bin/env bash
# A3 on the LATEST dsh-container (0.2.1-rc.2) against the same v0.7.0 candidate.
#
# Same image, same golden config, same prompt, same tightened breaker config as
# the successful 0.2.0-rc.2 rerun -- the only change is the harness image:
#   0.2.0-rc.2 / breaker 0.11.4  ->  0.2.1-rc.2 / breaker 0.11.6
#
# The breaker row is still required: 0.11.6 ships the SAME limits as 0.11.4
# (window 16, exact/cmd/net/sink 12, host 16, onLimit ask), and replaying the
# first run's timed-out session through 0.11.6's own window accounting still
# peaks at 9 -- below the limit of 12, so the gate never fires.
set -uo pipefail
ISSUE30=<workspace>/test-issue30
RUNDIR="$ISSUE30/run/a3-rerun-latest"
TEST_HOME="$RUNDIR/dsh-home"
HARNESS=ghcr.io/snailium/dsh-container/dsh@sha256:ae65d5e032253236f1d93d3146d491b4734cd333cfc37a1feec84e1fa7a11519
ONGPU=<workspace>/scripts/on-gpu.sh
WIN="$RUNDIR/logs/windows.txt"
LOGS="$RUNDIR/logs"
SESS="$TEST_HOME/sessions/--workspace--"
CONTAINER=b70-dev-test-v070

mkdir -p "$LOGS"
lines() { "$ONGPU" "docker logs $CONTAINER 2>&1 | wc -l" 2>/dev/null | tr -d '\r' | tail -1; }

for key in "$@"; do
  # Rule 5c: the prompt is extracted at run time from the pinned skill, never transcribed.
  prompt=$(sed -n '133p' <dsh-skills>/backend-test-suite/SKILL.md | sed 's/^> //')
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
echo "RERUN DONE" | tee -a "$WIN"
