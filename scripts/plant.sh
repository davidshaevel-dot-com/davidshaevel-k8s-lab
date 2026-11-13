#!/usr/bin/env bash
# make plant SCENARIO=<n>: plant one fault, chosen at random, without saying which.
. "$(dirname "$0")/lib.sh"

scenario=${1:-${SCENARIO:-}}
[ -n "$scenario" ] || die "usage: make plant SCENARIO=<2|3>"
case "$scenario" in 2 | 3) ;; *) die "scenario $scenario has no fault scripts (use 2 or 3)" ;; esac
state_exists && die "a fault is already planted; run 'make reveal' or 'make heal' first"

env_name=$(lab_env)
candidates=()
while IFS= read -r f; do candidates+=("$f"); done < <(fault_files "$scenario" "$env_name")
[ "${#candidates[@]}" -gt 0 ] || die "no faults available for scenario $scenario on $env_name"

if [ -n "${LAB_FAULT:-}" ]; then # testing hook: force one fault
  chosen=""
  for f in "${candidates[@]}"; do [ "$(basename "$f" .sh)" = "$LAB_FAULT" ] && chosen=$f; done
  [ -n "$chosen" ] || die "that fault is not available for scenario $scenario on $env_name"
else
  chosen=${candidates[$((RANDOM % ${#candidates[@]}))]}
fi

k get namespace "$LAB_NS" >/dev/null 2>&1 || die "the app is not deployed; run 'make deploy' first"

state_set scenario "$scenario"
state_set fault "$(basename "$chosen" .sh)"
state_set planted_at "$(date +%s)"

# Everything the fault does goes to a log, not the terminal: its output would
# give it away. The log is base64-encoded like the state file (a stray cat or
# grep -r must not spoil a run), owner-only, and never traced (no secrets).
log="$LAB_STATE_DIR/last-plant.log"
rm -f "$log" # a rewrite would keep an older, wider mode
if ! (umask 077; (. "$chosen"; fault_plant) 2>&1 | base64 > "$log"); then
  echo "Planting failed (details, which name the fault: base64 -d < $log)." >&2
  echo "Run 'make heal' to restore the healthy state, then try again." >&2
  exit 1
fi

echo "Scenario $scenario: a fault has been planted. Start your timer."
echo
cat "$(scenario_dir "$scenario")/scenario.txt"
