#!/usr/bin/env bash
# make heal: undo every fault this environment knows about, re-apply the healthy
# manifests and wait for the app to settle. Every fault's heal runs, not only the
# recorded one: a stale or lost state file, or two stacked plants, still converge.
. "$(dirname "$0")/lib.sh"

env_name=$(lab_env)
faults=()
for s in 2 3; do while IFS= read -r f; do faults+=("$f"); done < <(fault_files "$s" "$env_name"); done

# Fault output goes to a log, as in plant: heal can run before reveal (giving up),
# so neither its output nor its error messages name a fault. Collected raw in a
# private temp file, then stored base64-encoded and owner-only; never traced.
mkdir -p "$LAB_STATE_DIR"
log="$LAB_STATE_DIR/last-heal.log"
raw=$(mktemp)
trap 'rm -f "$log"; (umask 077; base64 < "$raw" > "$log"); rm -f "$raw"' EXIT
failed() { die "heal failed; details (they name the fault): base64 -d < $log"; }
for f in "${faults[@]}"; do
  (. "$f"; fault_heal) >> "$raw" 2>&1 || failed
done
"$LAB_ROOT/scripts/deploy.sh" --apply-only
for f in "${faults[@]}"; do
  if (. "$f"; declare -F fault_heal_after_apply >/dev/null); then
    (. "$f"; fault_heal_after_apply) >> "$raw" 2>&1 || failed
  fi
done
state_clear
info "Healed. Check with: make status"
info "If your own fix added something the manifests do not remove (a ConfigMap key, an image tag), reset fully: kubectl delete namespace lab && make deploy"
