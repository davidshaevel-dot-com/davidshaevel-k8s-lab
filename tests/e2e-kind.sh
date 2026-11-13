#!/usr/bin/env bash
# End-to-end run on a local kind cluster with the app deployed (make kind-up deploy).
# For every kind-capable fault: plant it (forced), confirm the symptom, reveal,
# heal, and confirm the app is healthy again. Usage: tests/e2e-kind.sh [fault-id...]
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
export LAB_ENV=kind
K="kubectl --context kind-${KIND_CLUSTER_NAME:-k8s-lab} -n lab"

wait_for() { # seconds command... : poll until the command succeeds
  local deadline=$((SECONDS + $1)); shift
  until "$@" >/dev/null 2>&1; do [ $SECONDS -ge $deadline ] && return 1; sleep 3; done
}
ready_pod() { $K get pods -l app.kubernetes.io/name=web -o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | awk '$2=="True"{print $1; exit}'; }
db_detail() { # body of POST /api/visits from inside a ready pod
  $K exec "$(ready_pod)" -c web -- python -c "
import urllib.request, urllib.error
try:
    print(urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8080/api/visits', method='POST'), timeout=15).read().decode())
except urllib.error.HTTPError as e:
    print(e.code, e.read().decode())"
}
db_fails_with() { db_detail | grep -Eq "$1"; }
pod_waiting() { $K get pods -l app.kubernetes.io/name=web -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' | grep -Eq "$1"; }
pod_unschedulable() { $K get pods -l app.kubernetes.io/name=web -o jsonpath='{.items[*].status.conditions[?(@.type=="PodScheduled")].reason}' | grep -q Unschedulable; }
readiness_404() { $K get events --field-selector reason=Unhealthy -o jsonpath='{.items[*].message}' | grep -q 'Readiness probe failed: HTTP probe failed with statuscode: 404'; }
quota_rejected() { $K get events --field-selector reason=FailedCreate -o jsonpath='{.items[*].message}' | grep -q 'exceeded quota: lab-quota'; }
one_replicaset() { [ "$($K get rs -l app.kubernetes.io/name=web --no-headers | wc -l | tr -d ' ')" = 1 ]; }
rollout_stuck() { ! $K rollout status deployment/web --timeout=15s; }

symptom() { # fault-id -> succeeds once that fault's symptom is visible
  case "$1" in
    s2-dns) db_fails_with '503 .*(Name or service not known|could not translate host name|nodename nor servname)' ;;
    s2-no-endpoints) db_fails_with '503 .*(Connection refused|timeout expired|timed out)' ;;
    s2-netpol) db_fails_with '503 .*(timeout expired|timed out)' ;;
    s2-wrong-port-or-secret) db_fails_with '503 .*(password authentication failed|Connection refused|timeout expired|timed out)' ;;
    s2-db-firewall) db_fails_with '503 .*pg_hba.conf rejects connection' ;;
    s3-image-pull) pod_waiting 'ErrImagePull|ImagePullBackOff' && rollout_stuck ;;
    s3-unschedulable) pod_unschedulable && rollout_stuck ;;
    s3-failing-probe) readiness_404 && rollout_stuck ;;
    s3-missing-config) pod_waiting CreateContainerConfigError && rollout_stuck ;;
    s3-quota) quota_rejected && rollout_stuck ;;
    s3-crash-loop) pod_waiting 'CrashLoopBackOff|Error' && rollout_stuck ;;
    *) return 1 ;;
  esac
}

if [ $# -gt 0 ]; then faults=("$@"); else
  faults=()
  for f in "$ROOT"/faults/s*.sh; do (. "$ROOT/scripts/lib.sh"; . "$f"; fault_supports kind) && faults+=("$(basename "$f" .sh)"); done
fi

cd "$ROOT"
make -s status >/dev/null || { echo "app is not healthy before the run; aborting"; exit 1; }
for id in "${faults[@]}"; do
  scenario=${id:1:1}
  echo "== $id (scenario $scenario)"
  start=$SECONDS
  out=$(LAB_FAULT=$id make -s plant SCENARIO="$scenario" 2>&1)
  assert_contains "$out" "Start your timer" "$id: planted"
  assert_not_contains "$out" "$id" "$id: plant output does not name the fault"
  if wait_for 150 symptom "$id"; then pass "$id: symptom confirmed after $((SECONDS - start))s"
  else fail "$id: symptom confirmed"; fi
  [ "$scenario" = 2 ] && echo "       app saw: $(db_detail 2>&1 | head -c 220)"
  annotated=$($K get deploy,sts,svc,cm,secret,netpol,pdb,resourcequota,endpointslice -o yaml | grep -c 'last-applied-configuration' || true)
  assert_eq 0 "$annotated" "$id: no object carries a last-applied annotation (it would show the healthy value)"
  assert_contains "$(make -s reveal)" "$id" "$id: reveal names it"
  make -s heal >/dev/null 2>&1; assert_eq 0 $? "$id: heal succeeded"
  if wait_for 120 make -s status; then pass "$id: healthy after heal"; else fail "$id: healthy after heal" "$(make -s status 2>&1 | tail -6)"; fi
  if wait_for 60 one_replicaset; then pass "$id: only the healthy ReplicaSet remains"; else fail "$id: only the healthy ReplicaSet remains" "$($K get rs 2>&1)"; fi
done
finish
