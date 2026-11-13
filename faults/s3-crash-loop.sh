# The new revision carries a configuration value the app cannot parse.
fault_supports() { return 0; }
fault_describe() { echo "Crash loop: the web container gained env DB_CONNECT_TIMEOUT=5s; the app requires an integer and exits at startup."; }
fault_plant() { k set env deployment/web -c web DB_CONNECT_TIMEOUT=5s; }
fault_heal() { k patch deployment web --type json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/env"}]' 2>/dev/null || true; }
