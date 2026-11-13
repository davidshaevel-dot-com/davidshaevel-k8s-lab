#!/usr/bin/env bash
# make reveal: say which fault is planted (after you have written your diagnosis).
. "$(dirname "$0")/lib.sh"

if ! state_exists; then
  echo "No fault is planted."
  exit 0
fi
fault=$(state_get fault)
f="$LAB_ROOT/faults/$fault.sh"
[ -f "$f" ] || die "unknown fault in state: $fault"
planted_at=$(state_get planted_at)
elapsed=$(( ($(date +%s) - ${planted_at:-$(date +%s)}) / 60 ))
echo "Scenario $(state_get scenario), fault: $fault"
echo "  $(. "$f"; fault_describe)"
variant=$(state_get variant)
[ -n "$variant" ] && echo "  variant: $variant"
echo "  planted $elapsed minute(s) ago"
echo
echo "Walkthrough: $(scenario_dir "$(state_get scenario)")/walkthrough.md"
echo "Restore the healthy state with: make heal"
