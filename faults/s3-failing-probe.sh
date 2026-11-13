# The new revision's readiness probe checks a path the app does not serve.
fault_supports() { return 0; }
fault_describe() { echo "Failing probe: the readiness probe path was changed from /readyz to /ready, which returns 404."; }
fault_plant() { k patch deployment web --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/ready"}]'; }
fault_heal() { :; } # the baseline re-apply restores the probe
