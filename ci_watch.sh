#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# ci_watch.sh  —  push → watch GitHub Actions → show logs → repeat
#
# Usage:
#   bash ci_watch.sh [commit_message]
#
# Set GITHUB_PERSONAL_ACCESS_TOKEN as a Replit Secret before running.
#
# What it does:
#   1. Commits & pushes all pending changes (calls push_to_github.sh)
#   2. Waits for GitHub Actions to start the triggered run
#   3. Streams job status until every job is done
#   4. On failure: prints the full log of every failed step, then exits 1
#      so you can fix the code and run again.
#   5. On success: prints the artifact download URLs and exits 0.
#
# Set SKIP_PUSH=1 to skip the push step and just watch the latest run.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
REPO="TITANICBHAI/FocusFlow-jvm-Test"
BRANCH="main"
POLL_INTERVAL=12   # seconds between status polls
MAX_WAIT=3600      # give up after 1 hour

API="https://api.github.com/repos/${REPO}"
# ─────────────────────────────────────────────────────────────────────────────

require_token() {
  if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    echo "❌  GITHUB_PERSONAL_ACCESS_TOKEN is not set."
    echo "    Add it as a Replit Secret, then re-run."
    exit 1
  fi
}

gh_api() {
  # gh_api <method> <path> [extra curl args...]
  local method="$1"; shift
  local path="$1";   shift
  curl -fsSL \
    -X "$method" \
    -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@" \
    "${API}${path}"
}

# Print a coloured status badge
badge() {
  local status="$1" conclusion="${2:-}"
  case "$status" in
    completed)
      case "$conclusion" in
        success)   echo -e "\e[32m✔ success\e[0m" ;;
        failure)   echo -e "\e[31m✘ failure\e[0m" ;;
        cancelled) echo -e "\e[33m⊘ cancelled\e[0m" ;;
        skipped)   echo -e "\e[90m— skipped\e[0m" ;;
        *)         echo -e "\e[33m? $conclusion\e[0m" ;;
      esac ;;
    in_progress) echo -e "\e[34m⟳ running\e[0m" ;;
    queued)      echo -e "\e[90m… queued\e[0m" ;;
    *)           echo "$status" ;;
  esac
}

# ── 1. Push ───────────────────────────────────────────────────────────────────
require_token

if [ "${SKIP_PUSH:-0}" != "1" ]; then
  echo ""
  echo "═══════════════════════════════════════════"
  echo " STEP 1 — Pushing to GitHub"
  echo "═══════════════════════════════════════════"
  bash push_to_github.sh "${1:-}"
  PUSH_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  echo ""
  echo "⏱  Pushed at $PUSH_TIME — waiting for Actions to queue a run…"
else
  echo "ℹ  SKIP_PUSH=1 — skipping push, watching latest run instead."
  PUSH_TIME=$(date -u -d "5 minutes ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

# ── 2. Find the triggered run ─────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo " STEP 2 — Waiting for GitHub Actions run"
echo "═══════════════════════════════════════════"

RUN_ID=""
WAITED=0
while [ -z "$RUN_ID" ]; do
  sleep $POLL_INTERVAL
  WAITED=$((WAITED + POLL_INTERVAL))
  if [ $WAITED -gt 120 ]; then
    echo "❌  No run appeared within 2 minutes. Check the repo's Actions tab."
    exit 1
  fi

  # Grab the most recent run on main, triggered after our push
  RUN_ID=$(gh_api GET "/actions/runs?branch=${BRANCH}&per_page=5" \
    | python3 -c "
import sys, json, datetime
runs = json.load(sys.stdin).get('workflow_runs', [])
push_time = datetime.datetime.fromisoformat('${PUSH_TIME}'.replace('Z','+00:00'))
for r in runs:
    created = datetime.datetime.fromisoformat(r['created_at'].replace('Z','+00:00'))
    if created >= push_time - datetime.timedelta(seconds=30):
        print(r['id'])
        break
" 2>/dev/null || true)

  if [ -z "$RUN_ID" ]; then
    echo "  … no new run yet (${WAITED}s elapsed)"
  fi
done

echo "▶  Run ID: $RUN_ID"
echo "   https://github.com/${REPO}/actions/runs/${RUN_ID}"

# ── 3. Poll until done ────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo " STEP 3 — Watching run status"
echo "═══════════════════════════════════════════"

ELAPSED=0
LAST_STATUS=""
while true; do
  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  RUN_JSON=$(gh_api GET "/actions/runs/${RUN_ID}")
  STATUS=$(echo "$RUN_JSON"     | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])")
  CONCLUSION=$(echo "$RUN_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('conclusion') or '')")
  WF_NAME=$(echo "$RUN_JSON"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['name'])")

  if [ "$STATUS $CONCLUSION" != "$LAST_STATUS" ]; then
    echo "  [$WF_NAME]  $(badge "$STATUS" "$CONCLUSION")  (+${ELAPSED}s)"
    LAST_STATUS="$STATUS $CONCLUSION"
  fi

  if [ "$STATUS" = "completed" ]; then
    break
  fi

  if [ $ELAPSED -gt $MAX_WAIT ]; then
    echo "❌  Timed out after ${MAX_WAIT}s."
    exit 1
  fi
done

# ── 4. Print job summary ──────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo " STEP 4 — Job summary"
echo "═══════════════════════════════════════════"

JOBS_JSON=$(gh_api GET "/actions/runs/${RUN_ID}/jobs")
FAILED_JOB_IDS=()

echo "$JOBS_JSON" | python3 -c "
import sys, json
jobs = json.load(sys.stdin)['jobs']
for j in jobs:
    icon = '✔' if j['conclusion'] == 'success' else ('✘' if j['conclusion'] == 'failure' else '–')
    print(f\"  {icon} {j['name']}  [{j['conclusion'] or j['status']}]\")
    for s in j.get('steps', []):
        if s['conclusion'] not in ('success', 'skipped', None):
            print(f\"      ✘ step: {s['name']}  ({s['conclusion']})\")
"

# Collect IDs of failed jobs
FAILED_JOB_IDS=($(echo "$JOBS_JSON" | python3 -c "
import sys, json
jobs = json.load(sys.stdin)['jobs']
for j in jobs:
    if j['conclusion'] == 'failure':
        print(j['id'])
"))

# ── 5. Print logs of failed jobs ──────────────────────────────────────────────
if [ ${#FAILED_JOB_IDS[@]} -gt 0 ]; then
  echo ""
  echo "═══════════════════════════════════════════"
  echo " STEP 5 — Failed job logs"
  echo "═══════════════════════════════════════════"
  for JOB_ID in "${FAILED_JOB_IDS[@]}"; do
    JOB_NAME=$(echo "$JOBS_JSON" | python3 -c "
import sys,json
jobs=json.load(sys.stdin)['jobs']
for j in jobs:
    if str(j['id']) == '${JOB_ID}':
        print(j['name'])
        break
")
    echo ""
    echo "──── Log: $JOB_NAME (job $JOB_ID) ────"
    # Logs come back as a zip of text files; curl -L follows redirect
    LOG_URL="https://api.github.com/repos/${REPO}/actions/jobs/${JOB_ID}/logs"
    LOG_RAW=$(curl -fsSL \
      -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -L "$LOG_URL" 2>/dev/null || true)

    if [ -z "$LOG_RAW" ]; then
      echo "  (no log text returned — check the Actions UI)"
    else
      # Show last 200 lines; most errors are at the bottom
      echo "$LOG_RAW" | tail -200
    fi
    echo "──────────────────────────────────────────"
  done

  echo ""
  echo "❌  Run FAILED.  Fix the issues above, then run:  bash ci_watch.sh"
  exit 1
fi

# ── 6. List artifacts ─────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo " STEP 6 — Build artifacts"
echo "═══════════════════════════════════════════"

gh_api GET "/actions/runs/${RUN_ID}/artifacts" | python3 -c "
import sys, json
arts = json.load(sys.stdin).get('artifacts', [])
if not arts:
    print('  (no artifacts uploaded)')
else:
    for a in arts:
        size_mb = a['size_in_bytes'] / 1_048_576
        print(f\"  📦 {a['name']}  ({size_mb:.1f} MB)\")
        print(f\"     https://github.com/${REPO}/actions/runs/${RUN_ID}/artifacts/{a['id']}\")
"

echo ""
echo "✅  Run PASSED."
exit 0
