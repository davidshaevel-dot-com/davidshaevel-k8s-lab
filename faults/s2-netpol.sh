# The NetworkPolicy that lets the app reach the database allows the wrong port.
fault_supports() { return 0; }
fault_describe() { echo "NetworkPolicy: db-egress was changed to allow TCP 5433 instead of 5432, so default-deny drops the app's database traffic."; }
fault_plant() { k patch networkpolicy db-egress --type json -p '[{"op":"replace","path":"/spec/egress/0/ports/0/port","value":5433}]'; }
fault_heal() { k patch networkpolicy db-egress --type json -p '[{"op":"replace","path":"/spec/egress/0/ports/0/port","value":5432}]' 2>/dev/null || true; }
