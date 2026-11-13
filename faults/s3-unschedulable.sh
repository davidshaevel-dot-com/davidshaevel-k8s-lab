# The new revision asks for nodes that do not exist.
fault_supports() { return 0; }
fault_describe() { echo "Unschedulable: the web Deployment gained nodeSelector agentpool=gpupool, which no node carries."; }
fault_plant() { k patch deployment web --type merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"agentpool":"gpupool"}}}}}'; }
fault_heal() { k patch deployment web --type json -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' 2>/dev/null || true; }
