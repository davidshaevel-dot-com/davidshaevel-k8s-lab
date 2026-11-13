# The app's database host name no longer resolves.
fault_supports() { return 0; }
fault_describe() { echo "Name resolution: the DB_HOST in ConfigMap web-config was changed to 'postgresql', a name that does not exist."; }
fault_plant() { set_config DB_HOST postgresql && restart_web; }
fault_heal() {
  if [ "$(k get configmap web-config -o jsonpath='{.data.DB_HOST}')" != postgres ]; then
    set_config DB_HOST postgres && restart_web
  fi
}
