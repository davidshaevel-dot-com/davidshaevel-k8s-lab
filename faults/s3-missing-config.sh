# The new revision reads a ConfigMap key that does not exist.
fault_supports() { return 0; }
fault_describe() { echo "Missing config: the web container gained env FEATURE_FLAGS from ConfigMap web-config key FEATURE_FLAGS, which does not exist (CreateContainerConfigError)."; }
fault_plant() {
  k patch deployment web --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"FEATURE_FLAGS","valueFrom":{"configMapKeyRef":{"name":"web-config","key":"FEATURE_FLAGS"}}}]}]'
}
fault_heal() {
  k patch deployment web --type json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/env"}]' 2>/dev/null || true
  # A fix that added the key would make the next draw of this fault a no-op.
  k patch configmap web-config --type json -p '[{"op":"remove","path":"/data/FEATURE_FLAGS"}]' 2>/dev/null || true
}
