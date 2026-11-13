#!/usr/bin/env bash
# make heal: undo the planted fault (or every fault, if the state was lost),
# re-apply the healthy manifests and wait for the app to settle.
. "$(dirname "$0")/lib.sh"

env_name=$(lab_env)
if state_exists; then
  faults=("$LAB_ROOT/faults/$(state_get fault).sh")
else
  info "No planted-fault state found; undoing every fault for $env_name"
  faults=()
  for s in 2 3; do while IFS= read -r f; do faults+=("$f"); done < <(fault_files "$s" "$env_name"); done
fi

# Kubernetes-side heals first, then re-apply the baseline, then anything that
# needs a running app (database-side heals run through a web pod).
# Fault output is silenced, as in plant: heal can run before reveal (giving up).
for f in "${faults[@]}"; do (. "$f"; fault_heal) >/dev/null 2>&1 || die "heal failed for $(basename "$f" .sh)"; done
"$LAB_ROOT/scripts/deploy.sh" --apply-only
for f in "${faults[@]}"; do
  if (. "$f"; declare -F fault_heal_after_apply >/dev/null); then
    (. "$f"; fault_heal_after_apply) >/dev/null 2>&1 || die "heal failed for $(basename "$f" .sh)"
  fi
done
state_clear
info "Healed. Check with: make status"
