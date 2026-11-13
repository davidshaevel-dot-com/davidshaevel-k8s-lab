#!/usr/bin/env bash
# make heal: undo every fault this environment knows about, re-apply the healthy
# manifests and wait for the app to settle. Every fault's heal runs, not only the
# recorded one: a stale or lost state file, or two stacked plants, still converge.
. "$(dirname "$0")/lib.sh"

env_name=$(lab_env)
faults=()
for s in 2 3; do while IFS= read -r f; do faults+=("$f"); done < <(fault_files "$s" "$env_name"); done

# Fault output goes to a log, as in plant: heal can run before reveal (giving up),
# so neither its output nor its error messages name a fault.
mkdir -p "$LAB_STATE_DIR"
log="$LAB_STATE_DIR/last-heal.log"
: > "$log"
for f in "${faults[@]}"; do
  (. "$f"; set -x; fault_heal) >> "$log" 2>&1 || die "heal failed; details in $log (they name the fault)"
done
"$LAB_ROOT/scripts/deploy.sh" --apply-only
for f in "${faults[@]}"; do
  if (. "$f"; declare -F fault_heal_after_apply >/dev/null); then
    (. "$f"; set -x; fault_heal_after_apply) >> "$log" 2>&1 || die "heal failed; details in $log (they name the fault)"
  fi
done
state_clear
info "Healed. Check with: make status"
info "If your own fix added something the manifests do not remove (a ConfigMap key, an image tag), reset fully: kubectl delete namespace lab && make deploy"
