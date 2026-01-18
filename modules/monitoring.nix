# Monitoring & Observability Module Group
#
# This module group provides monitoring and metrics infrastructure:
# - Prometheus (metrics collection and storage)
# - Grafana (metrics visualization and dashboards)
# - Node exporter (host metrics)
#
# Dependencies: core (for hosts, secrets)
# Optional: auth (for LDAP authentication in Grafana)

{ ... }: {
  imports = [
    ../lib/fudo/grafana.nix
    ../lib/fudo/node-exporter.nix
    ../lib/fudo/prometheus.nix
  ];
}
