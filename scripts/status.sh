#!/usr/bin/env bash
# make status: is the app healthy, end to end (rollout, endpoints, database)?
. "$(dirname "$0")/lib.sh"

env_name=$(lab_env)
echo "Environment: $env_name (context $(lab_context))"
k get deployments,statefulsets,pods -o wide 2>/dev/null || die "cannot reach the lab cluster"
echo

failures=0
check() { # name command...
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  ok    $name"; else echo "  FAIL  $name"; failures=$((failures + 1)); fi
}
rollout_complete() { k rollout status deployment/web --timeout=5s; }
has_endpoints() {
  [ -n "$(k get endpointslices -l kubernetes.io/service-name=web -o jsonpath='{.items[*].endpoints[?(@.conditions.ready==true)].addresses[0]}')" ]
}
http_in_pod() { # method path
  local pod
  pod=$(ready_web_pod)
  [ -n "$pod" ] || return 1
  k exec "$pod" -c web -- python -c "
import sys, urllib.request
req = urllib.request.Request('http://127.0.0.1:8080$2', method='$1')
sys.exit(0 if urllib.request.urlopen(req, timeout=10).status == 200 else 1)"
}

check "web rollout complete" rollout_complete
check "web Service has ready endpoints" has_endpoints
check "app answers /readyz" http_in_pod GET /readyz
check "app reads and writes PostgreSQL (POST /api/visits)" http_in_pod POST /api/visits
echo
if [ "$failures" -eq 0 ]; then echo "HEALTHY"; else echo "UNHEALTHY ($failures check(s) failed)"; exit 1; fi
