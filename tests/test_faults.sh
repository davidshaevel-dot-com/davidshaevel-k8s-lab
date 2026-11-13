#!/usr/bin/env bash
# Tests for the fault machinery that need no cluster: kubectl and az are stubs.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
# Stubs print the kind of noise real tools print, so we can prove it is suppressed.
for tool in kubectl az docker kind terraform; do
  cat > "$WORK/bin/$tool" <<STUB
#!/usr/bin/env bash
echo "$tool \$*" >> "$WORK/calls.log"
echo "deployment.apps/web patched (stub $tool \$*)"
exit 0
STUB
  chmod +x "$WORK/bin/$tool"
done
# kubectl stub: answers the "which web pod is Ready" query like a healthy
# cluster and, like the real tool, reads stdin for `exec -i` and `apply -f -`.
cat > "$WORK/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
echo "kubectl $*" >> "$(dirname "$0")/../calls.log"
echo "deployment.apps/web patched (stub kubectl $*)"
case "$*" in *Ready*) echo "web-0 True" ;; esac
case " $* " in *" -i "* | *" -f - "*) cat >/dev/null ;; esac
exit 0
STUB

run() { # run a lab script with stubs and an isolated state dir
  env PATH="$WORK/bin:$PATH" LAB_STATE_DIR="$WORK/state" LAB_ENV="$ENVIRONMENT" "$@" 2>&1 </dev/null
}

echo "fault contract"
ids=()
for f in "$ROOT"/faults/s*.sh; do
  id=$(basename "$f" .sh)
  ids+=("$id")
  out=$(bash -c ". '$f'; for fn in fault_supports fault_plant fault_heal fault_describe; do declare -F \$fn >/dev/null || echo missing:\$fn; done")
  assert_eq "" "$out" "$id defines plant/heal/supports/describe"
done
count() { # scenario env -> number of faults that support env
  local n=0 f
  for f in "$ROOT"/faults/s"$1"-*.sh; do
    if bash -c ". '$f'; fault_supports $2"; then n=$((n + 1)); fi
  done
  echo "$n"
}
assert_eq 6 "$(count 2 aks)" "scenario 2 has six faults on aks"
assert_eq 5 "$(count 2 kind)" "scenario 2 has five faults on kind (network security group is Azure-only)"
assert_eq 6 "$(count 3 aks)" "scenario 3 has six faults on aks"
assert_eq 6 "$(count 3 kind)" "scenario 3 has six faults on kind"

for ENVIRONMENT in kind aks; do
  for scenario in 2 3; do
    echo "plant hides the fault (env=$ENVIRONMENT scenario=$scenario)"
    for f in "$ROOT"/faults/s"$scenario"-*.sh; do
      id=$(basename "$f" .sh)
      bash -c ". '$f'; fault_supports $ENVIRONMENT" || continue
      rm -rf "$WORK/state" "$WORK/calls.log"
      desc=$(bash -c ". '$f'; fault_describe")
      out=$(run env LAB_FAULT="$id" "$ROOT/scripts/plant.sh" "$scenario")
      status=$?
      assert_eq 0 "$status" "$id: plant exits 0"
      assert_not_contains "$out" "$id" "$id: plant output omits the fault id"
      assert_not_contains "$out" "${id#s?-}" "$id: plant output omits the fault name"
      assert_not_contains "$out" "$desc" "$id: plant output omits the description"
      assert_not_contains "$out" "stub" "$id: plant output omits tool output"
      assert_contains "$out" "Start your timer" "$id: plant says a fault is planted"
      state=$(cat "$WORK/state/state" 2>/dev/null)
      assert_not_contains "$state" "$id" "$id: state on disk does not spell out the fault id"

      out=$(run "$ROOT/scripts/plant.sh" "$scenario")
      [ $? -ne 0 ] && pass "$id: a second plant is refused" || fail "$id: a second plant is refused"

      out=$(run "$ROOT/scripts/reveal.sh")
      assert_contains "$out" "$id" "$id: reveal names the fault"
      assert_contains "$out" "$desc" "$id: reveal describes the fault"

      out=$(run "$ROOT/scripts/heal.sh")
      assert_eq 0 "$?" "$id: heal exits 0"
      assert_not_contains "$out" "stub" "$id: heal output omits tool output"
      out=$(run "$ROOT/scripts/reveal.sh")
      assert_contains "$out" "No fault is planted" "$id: heal clears the planted state"
    done
  done
done

echo "review fixes"
ENVIRONMENT=aks
rm -rf "$WORK/state" "$WORK/calls.log"
run env LAB_FAULT=s3-quota "$ROOT/scripts/plant.sh" 3 >/dev/null
[ -s "$WORK/state/last-plant.log" ] && pass "plant keeps its output in .lab/last-plant.log" || fail "plant keeps its output in .lab/last-plant.log"
run "$ROOT/scripts/heal.sh" >/dev/null
[ -s "$WORK/state/last-heal.log" ] && pass "heal keeps its output in .lab/last-heal.log" || fail "heal keeps its output in .lab/last-heal.log"
calls=$(cat "$WORK/calls.log")
assert_contains "$calls" "az network nsg rule delete" "heal undoes every fault, not only the recorded one"
assert_contains "$calls" "--server-side" "apply is server-side"
client_side=$(grep -E '^kubectl .* apply ' "$WORK/calls.log" | grep -v -- '--server-side' || true)
assert_eq "" "$client_side" "no client-side apply (it writes the last-applied annotation)"

# A failing `terraform output` must stop deploy before anything is applied.
cp "$WORK/bin/terraform" "$WORK/terraform.ok"
printf '#!/usr/bin/env bash\necho "terraform $*" >> "%s/calls.log"\ncase "$*" in *output*) echo "No outputs found" >&2; exit 1 ;; esac\n' "$WORK" > "$WORK/bin/terraform"
rm -f "$WORK/calls.log"
run "$ROOT/scripts/deploy.sh" --apply-only >/dev/null
[ $? -ne 0 ] && pass "deploy fails when terraform output fails" || fail "deploy fails when terraform output fails"
grep -q 'apply.*-k' "$WORK/calls.log" && fail "deploy applies nothing when terraform output fails" || pass "deploy applies nothing when terraform output fails"
cp "$WORK/terraform.ok" "$WORK/bin/terraform"

echo "revision history"
assert_contains "$(cat "$ROOT/k8s/base/deployment.yaml")" "revisionHistoryLimit: 0" "old ReplicaSets (earlier faults) are not kept"

echo "plant chooses at random"
ENVIRONMENT=kind
seen=""
for _ in $(seq 1 40); do
  rm -rf "$WORK/state"
  run "$ROOT/scripts/plant.sh" 3 >/dev/null
  seen="$seen $(run "$ROOT/scripts/reveal.sh" | sed -n 's/.*\(s3-[a-z-]*\).*/\1/p' | head -1)"
done
distinct=$(echo "$seen" | tr ' ' '\n' | sort -u | grep -c .)
[ "$distinct" -ge 4 ] && pass "40 plants hit at least 4 different faults ($distinct)" || fail "40 plants hit at least 4 different faults" "got $distinct:$seen"

echo "plant validates input"
out=$(run "$ROOT/scripts/plant.sh" 9); [ $? -ne 0 ] && pass "unknown scenario is refused" || fail "unknown scenario is refused"
out=$(run "$ROOT/scripts/plant.sh"); [ $? -ne 0 ] && pass "missing scenario is refused" || fail "missing scenario is refused"
ENVIRONMENT=kind
rm -rf "$WORK/state"
out=$(run env LAB_FAULT=s2-nsg "$ROOT/scripts/plant.sh" 2); [ $? -ne 0 ] && pass "an Azure-only fault is refused on kind" || fail "an Azure-only fault is refused on kind"

finish
