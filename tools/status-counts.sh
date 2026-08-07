#!/bin/sh
# Counts open/done task items in STATUS.md, and (with --check) verifies the
# dashboard's "N open · N done" figures against them.
#
# The dashboard numbers are only trustworthy if something recomputes them — a
# number nobody recomputes is a number that drifts. This script IS that
# something: the maintenance rules require `status-counts.sh --check` to pass
# before any tick is committed.
#
# The pattern counts task IDs only (P*/PI-/M-/D-/Q*), so the phase-status
# checkboxes never inflate the totals. It must stay identical to what the
# dashboard claims to count; if the ID scheme ever grows a new prefix, this
# pattern and the dashboard are one change, not two.

set -eu

# STATUS.md lives one directory above this script, wherever it is called from.
STATUS="$(cd "$(dirname "$0")/.." && pwd)/STATUS.md"

if [ ! -f "$STATUS" ]; then
  echo "status-counts: $STATUS not found" >&2
  exit 2
fi

ID_PATTERN='(P[0-9]+-|PI-|M-|D-|Q[0-9])'
# grep -c exits 1 on zero matches, which set -e would turn into a crash; a
# zero count is a legitimate answer here (|| true), not a failure.
open=$(grep -Ec "^- \[ \] \*\*${ID_PATTERN}" "$STATUS" || true)
done_=$(grep -Ec "^- \[x\] \*\*${ID_PATTERN}" "$STATUS" || true)

echo "open: $open   done: $done_"

[ "${1:-}" = "--check" ] || exit 0

# The dashboard line reads: **Phase 3 of 4** · **49 open · 54 done**
claimed=$(grep -Eo '[0-9]+ open · [0-9]+ done' "$STATUS" | head -1)
if [ -z "$claimed" ]; then
  echo "status-counts: no 'N open · N done' line found in the dashboard" >&2
  exit 1
fi

claimed_open=$(echo "$claimed" | grep -Eo '^[0-9]+')
claimed_done=$(echo "$claimed" | grep -Eo '[0-9]+ done' | grep -Eo '[0-9]+')

if [ "$claimed_open" != "$open" ] || [ "$claimed_done" != "$done_" ]; then
  echo "status-counts: DASHBOARD IS STALE" >&2
  echo "  dashboard says: $claimed_open open · $claimed_done done" >&2
  echo "  file contains:  $open open · $done_ done" >&2
  echo "  fix the dashboard in STATUS.md before committing." >&2
  exit 1
fi

echo "dashboard matches."
