#!/usr/bin/env bash
# fix.sh — the eval-driven fix loop.
#
# Runs the pytest eval suite, and if anything fails, pipes the failure
# block into a coding agent (Claude Code by default, or GitHub Copilot
# via `gh copilot suggest` as a fallback). The agent is instructed to
# edit ONLY the AI code in temporal-tx-agent/ai/ and re-run the
# offline evals until they pass.
#
# Usage:
#   ./fix.sh                    # use claude CLI
#   AGENT=copilot ./fix.sh      # use gh copilot suggest
#
# This is the "close the loop" step for the demo: the failing eval
# output is the signal, the coding agent is the fixer.

set -uo pipefail

cd "$(dirname "$0")/.."

AGENT="${AGENT:-claude}"
OUT="$(mktemp -t temporal-tx-eval-XXXXXX).log"

echo "==> Running eval suite..."
pytest evals/ -v --tb=short 2>&1 | tee "$OUT"
STATUS=${PIPESTATUS[0]}

if [ "$STATUS" -eq 0 ]; then
  echo "==> Evals green. Nothing to fix."
  rm -f "$OUT"
  exit 0
fi

echo ""
echo "==> Evals red. Handing failure block to $AGENT..."
echo ""

PROMPT=$(cat <<EOF
The eval suite for the temporal transaction AI agent just failed. Full
pytest output is below.

You may only edit files under \`temporal-tx-agent/ai/\` (that's
where the AI prompts, decision thresholds, and model wiring live). Do
NOT touch the tests in \`evals/\`, the Temporal workflows, the
Couchbase code, or the FastAPI layer. If a fix would require changes
outside \`ai/\`, explain why and stop.

Once you've made edits, re-run \`python record_from_scenarios.py\`
followed by \`pytest evals/test_temporal_tx_coverage.py -v\` and iterate
until every test passes.

--- pytest output ---
$(cat "$OUT")
EOF
)

case "$AGENT" in
  claude)
    if ! command -v claude >/dev/null 2>&1; then
      echo "claude CLI not found. Install Claude Code or run: AGENT=copilot ./fix.sh" >&2
      exit 2
    fi
    echo "$PROMPT" | claude
    ;;
  copilot)
    if ! command -v gh >/dev/null 2>&1; then
      echo "gh CLI not found." >&2
      exit 2
    fi
    echo "$PROMPT" | gh copilot suggest -t shell
    ;;
  *)
    echo "Unknown AGENT=$AGENT (use claude or copilot)" >&2
    exit 2
    ;;
esac

rm -f "$OUT"
