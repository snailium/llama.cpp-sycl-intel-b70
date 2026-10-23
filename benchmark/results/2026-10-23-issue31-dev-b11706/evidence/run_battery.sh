#!/usr/bin/env bash
# Full battery for issue #31 (dev b11706) — SERIAL, one task at a time.
#
# Order matches the issue #30 run (T1 -> T2 -> V1 -> V2 -> V3 -> A1 -> A2 -> A3)
# so the two runs are directly comparable. Prompts are the pinned ones, verified
# verbatim against the skill (sha256 8af83da1...) before the run.
#
# Every task gets a `docker logs | wc -l` window marker so metrics can be sliced
# to exactly that task's requests.
set -uo pipefail
ROOT=<workspace>
T31="$ROOT/test-issue31"
ND="$T31/run/dev11706"
HARNESS=ghcr.io/snailium/dsh-container/dsh@sha256:ae65d5e032253236f1d93d3146d491b4734cd333cfc37a1feec84e1fa7a11519
ONGPU="$ROOT/scripts/on-gpu.sh"
CONTAINER=b70-dev-test-b11706
WIN="$T31/logs/windows.txt"
LOGS="$T31/logs"
SESS="$ND/dsh-home/sessions/--workspace--"

mkdir -p "$LOGS" "$T31/results"
lines() { "$ONGPU" "docker logs $CONTAINER 2>&1 | wc -l" 2>/dev/null | tr -d '\r' | tail -1; }

direct() {
  local key=$1
  local before after
  before=$(lines)
  echo "$key START utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) logline_before=$before" | tee -a "$WIN"
  ( cd "$T31" && RUN="$T31" BASE=http://192.0.2.101:18082 python3 run_direct.py "$key" ) \
      > "$LOGS/${key}_run.log" 2>&1
  echo "  $key rc=$?"
  after=$(lines)
  echo "$key END   utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) logline_after=$after" | tee -a "$WIN"
}

agent() {
  local key=$1 prompt before after
  prompt=$(python3 -c "import json,sys;print(json.load(open('$T31/logs/prompts.json'))['$key'])")
  before=$(lines)
  ls "$SESS" > "$LOGS/.sess_before_$key" 2>/dev/null || true
  echo "$key START utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) logline_before=$before" | tee -a "$WIN"

  timeout 3600 docker run --rm --network host \
    -e DSH_MODE=headless -e DSH_TEST_PROFILE=headless_lc \
    -e DSH_TRIM_AUTO_TUNE=1 \
    -e DSH_HOME=/dsh-home -e B70_API_KEY=test -e HOME=/root \
    -v "$ND/dsh-home:/dsh-home" -v "$ND/dsh-home/workspace:/workspace" \
    "$HARNESS" "$prompt" > "$LOGS/${key}_run.log" 2>&1
  local rc=$?
  [ "$rc" = "124" ] && echo "TIMEOUT 1h (killed)" >> "$LOGS/${key}_run.log"
  echo "  $key harness rc=$rc"

  after=$(lines)
  echo "$key END   utc=$(date -u +%FT%TZ) epoch=$(date -u +%s) logline_after=$after" | tee -a "$WIN"

  ls "$SESS" > "$LOGS/.sess_after_$key" 2>/dev/null || true
  for d in $(comm -13 <(sort "$LOGS/.sess_before_$key" 2>/dev/null) <(sort "$LOGS/.sess_after_$key" 2>/dev/null)); do
    local z="$SESS/$d/session.v4.jsonl.zstd"
    if [ -f "$z" ]; then
      cp "$z" "$LOGS/${key}.session.jsonl.zstd"
      zstd -dc "$z" > "$LOGS/${key}.session.jsonl" 2>/dev/null
      echo "  $key session: $d -> $(du -h "$LOGS/${key}.session.jsonl" | cut -f1)"
    fi
  done
}

# ---- direct tasks ----
direct t1
direct t2
direct v1
direct v2
direct v3
# ---- agent tasks ----
agent a1_security
agent a2_hostinfo
agent a3_snowfall

echo "BATTERY DONE utc=$(date -u +%FT%TZ)" | tee -a "$WIN"
