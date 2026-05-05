#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hits_file="$(mktemp)"
trap 'rm -f "${hits_file}"' EXIT

if rg -n 'nebula|wireguard|openvpn|extraForwardRules|extraInputRules|ip route|ip rule|iptables|ip6tables|brctl|ip link add.*bridge|macvlan' \
  "${repo_root}/s88" "${repo_root}/lib" \
  --glob '*.nix' >"${hits_file}"; then
  cat >&2 <<'EOF'
FATAL network-renderer-nixos overlay materialization boundary is not implemented yet.

This red failure may be removed only after network-renderer-nixos materializes
routes, nftables/firewall, DNS, bridges, macvlan, and overlay-facing interfaces
only from explicit CPM/provider output.

Required conditions before removing this failure:

  - no provider-name inference such as Nebula/WireGuard/OpenVPN in generic NixOS renderer code
  - renderer APIs may accept intentPath/inventoryPath only to invoke the upstream pipeline
  - nftables emission is allowed only from explicit CPM/provider contracts
  - no raw iptables/ip-route/ip-rule/bridge/macvlan policy glue in renderer-local profiles
  - overlay/core/access/firewall/DNS contracts come from CPM or provider renderer modules
  - missing CPM/provider fields fail closed instead of being repaired locally

Current boundary hits:
EOF
  cat "${hits_file}" >&2
  exit 1
fi

echo "PASS overlay-materialization-contract"
