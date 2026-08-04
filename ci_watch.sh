#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# ci_watch.sh  —  push → watch GitHub Actions → show logs → repeat
#
# Usage:
#   bash ci_watch.sh [commit_message]
#   SKIP_PUSH=1 bash ci_watch.sh     # just watch latest run, don't push
#
# Requires: GITHUB_PERSONAL_ACCESS_TOKEN set as a Replit Secret
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="TITANICBHAI/FocusFlow-jvm-Test"
BRANCH="main"
POLL_INTERVAL=15
MAX_WAIT=3600
API="https://api.github.com/repos/${REPO}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── helpers ───────────────────────────────────────────────────────────────────
require_token() {
  if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    echo "❌  GITHUB_PERSONAL_ACCESS_TOKEN is not set. Add it as a Replit Secret."
    exit 1
  fi
}

gh_get() {
  # gh_get <path> → saves to $TMP/response.json
  curl -fsSL \
    -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API}${1}" -o "$TMP/response.json"
}

gh_get_url() {
  # gh_get_url <full_url> → saves to $TMP/response.json
  curl -fsSL -L \
    -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${1}" -o "$TMP/response.json"
}

node_run() {
  node -e "$1" -- "$TMP/response.json"
}

# ── 1. Push ───────────────────────────────────────────────────────────────────
require_token

if [ "${SKIP_PUSH:-0}" != "1" ]; then
  echo ""
  echo "══════════════════════════════════════════"
  echo " STEP 1 — Pushing to GitHub"
  echo "══════════════════════════════════════════"
  bash push_to_github.sh "${1:-}"
  PUSH_EPOCH=$(date -u +%s)
  echo ""
  echo "⏱  Pushed. Waiting for Actions to queue a run…"
else
  echo "ℹ  SKIP_PUSH=1 — skipping push, watching latest run."
  PUSH_EPOCH=$(( $(date -u +%s) - 300 ))
fi

# ── 2. Find the triggered run ─────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " STEP 2 — Waiting for GitHub Actions run"
echo "══════════════════════════════════════════"

RUN_ID=""
WAITED=0
while [ -z "$RUN_ID" ]; do
  sleep $POLL_INTERVAL
  WAITED=$((WAITED + POLL_INTERVAL))
  if [ $WAITED -gt 180 ]; then
    echo "❌  No run appeared within 3 minutes. Check the repo's Actions tab."
    exit 1
  fi

  gh_get "/actions/runs?branch=${BRANCH}&per_page=5" || { echo "  … API error (${WAITED}s)"; continue; }

  RUN_ID=$(node_run "
const fs = require('fs');
const d = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const runs = d.workflow_runs || [];
const cutoff = ${PUSH_EPOCH} - 30;
for (const r of runs) {
  const t = Math.floor(new Date(r.created_at).getTime() / 1000);
  if (t >= cutoff) { process.stdout.write(String(r.id)); break; }
}
" 2>/dev/null || true)

  if [ -z "$RUN_ID" ]; then
    echo "  … no new run yet (${WAITED}s elapsed)"
  fi
done

echo "▶  Run #${RUN_ID}"
echo "   https://github.com/${REPO}/actions/runs/${RUN_ID}"

# ── 3. Poll until done ────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " STEP 3 — Watching run status"
echo "══════════════════════════════════════════"

ELAPSED=0
LAST_LINE=""
while true; do
  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  gh_get "/actions/runs/${RUN_ID}" || continue

  LINE=$(node_run "
const fs = require('fs');
const d = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
process.stdout.write(d.status + ' ' + (d.conclusion || '') + ' ' + d.name);
" 2>/dev/null || echo "unknown  ")

  STATUS=$(echo "$LINE" | awk '{print $1}')
  CONCLUSION=$(echo "$LINE" | awk '{print $2}')
  WF_NAME=$(echo "$LINE" | awk '{$1=$2=""; print substr($0,3)}')

  if [ "$LINE" != "$LAST_LINE" ]; then
    case "$STATUS/$CONCLUSION" in
      completed/success)   ICON="✔ success" ;;
      completed/failure)   ICON="✘ failure" ;;
      completed/cancelled) ICON="⊘ cancelled" ;;
      in_progress/)        ICON="⟳ running" ;;
      queued/)             ICON="… queued" ;;
      *)                   ICON="$STATUS/$CONCLUSION" ;;
    esac
    echo "  [${WF_NAME}]  ${ICON}  (+${ELAPSED}s)"
    LAST_LINE="$LINE"
  fi

  [ "$STATUS" = "completed" ] && break
  [ $ELAPSED -gt $MAX_WAIT ] && { echo "❌  Timed out."; exit 1; }
done

# ── 4. Job summary ────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " STEP 4 — Job summary"
echo "══════════════════════════════════════════"

gh_get "/actions/runs/${RUN_ID}/jobs"
cp "$TMP/response.json" "$TMP/jobs.json"

node -e "
const fs = require('fs');
const jobs = JSON.parse(fs.readFileSync('$TMP/jobs.json', 'utf8')).jobs || [];
for (const j of jobs) {
  const icon = j.conclusion === 'success' ? '✔' : (j.conclusion === 'failure' ? '✘' : '–');
  console.log('  ' + icon + ' ' + j.name + '  [' + (j.conclusion || j.status) + ']');
  for (const s of j.steps || []) {
    if (s.conclusion && s.conclusion !== 'success' && s.conclusion !== 'skipped') {
      console.log('      ✘ step: ' + s.name + '  (' + s.conclusion + ')');
    }
  }
}
"

FAILED_JOBS=$(node -e "
const fs = require('fs');
const jobs = JSON.parse(fs.readFileSync('$TMP/jobs.json', 'utf8')).jobs || [];
jobs.filter(j => j.conclusion === 'failure').forEach(j => console.log(j.id + ' ' + j.name));
" 2>/dev/null || true)

# ── 5. Print logs of failed jobs ──────────────────────────────────────────────
if [ -n "$FAILED_JOBS" ]; then
  echo ""
  echo "══════════════════════════════════════════"
  echo " STEP 5 — Failed job logs"
  echo "══════════════════════════════════════════"

  while IFS= read -r line; do
    JOB_ID=$(echo "$line" | awk '{print $1}')
    JOB_NAME=$(echo "$line" | cut -d' ' -f2-)
    echo ""
    echo "──── $JOB_NAME (job $JOB_ID) ────"
    LOG_URL="https://api.github.com/repos/${REPO}/actions/jobs/${JOB_ID}/logs"
    curl -fsSL -L \
      -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$LOG_URL" -o "$TMP/job_log.txt" 2>/dev/null || true
    if [ -s "$TMP/job_log.txt" ]; then
      tail -200 "$TMP/job_log.txt"
    else
      echo "  (no log text returned — check the Actions UI)"
    fi
    echo "──────────────────────────────────────────"
  done <<< "$FAILED_JOBS"

  echo ""
  echo "❌  Run FAILED. Fix the issues above, then:  bash ci_watch.sh"
  exit 1
fi

# ── 6. Artifacts ──────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " STEP 6 — Build artifacts"
echo "══════════════════════════════════════════"

gh_get "/actions/runs/${RUN_ID}/artifacts"
node -e "
const fs = require('fs');
const arts = JSON.parse(fs.readFileSync('$TMP/response.json', 'utf8')).artifacts || [];
if (!arts.length) { console.log('  (no artifacts uploaded)'); }
else arts.forEach(a => {
  const mb = (a.size_in_bytes / 1048576).toFixed(1);
  console.log('  📦 ' + a.name + '  (' + mb + ' MB)');
  console.log('     https://github.com/${REPO}/actions/runs/${RUN_ID}#artifacts');
});
"

echo ""
echo "✅  Run PASSED."
exit 0
