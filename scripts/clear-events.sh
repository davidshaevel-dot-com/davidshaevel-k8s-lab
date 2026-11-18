#!/usr/bin/env bash
# make clear-events: delete every Event in the lab namespace, so the next run's
# `describe` output and event lists start clean. A lab convenience only: on a real
# cluster, events are evidence and are left alone. Nothing else calls this script.
. "$(dirname "$0")/lib.sh"

ctx=$(lab_context)
out=$(k delete events --all 2>&1) || die "could not delete the events in namespace $LAB_NS (context $ctx): $out"
n=$(printf '%s\n' "$out" | grep -c '^event' || true)
info "Cleared $n event(s) in namespace $LAB_NS (context $ctx)"
