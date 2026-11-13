# The postgres Service exists but routes to nothing.
fault_supports() { return 0; }
fault_describe() { echo "Service with no endpoints: the postgres Service no longer selects the database (kind: selector changed to app.kubernetes.io/name=postgresql; AKS: the EndpointSlice was detached from the Service)."; }
fault_plant() {
  case "$(lab_env)" in
    kind) k patch service postgres --type merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"postgresql"}}}' ;;
    aks) k label endpointslice postgres-1 kubernetes.io/service-name=postgres-primary --overwrite ;;
  esac
}
fault_heal() {
  case "$(lab_env)" in
    kind) k patch service postgres --type merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"postgres"}}}' ;;
    aks) k label endpointslice postgres-1 kubernetes.io/service-name=postgres --overwrite 2>/dev/null || true ;;
  esac
}
