#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-200
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail "FS-310 NixOS bridge networks do not invent host IPs" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          rendered = import (repoRoot + "/s88/ControlModule/render/systemd-host-network.nix") {
            inherit lib;
            hostPlan = {
              hostHasUplinks = false;
              deploymentHost.bridgeNetworks = {
                explicit-dynamic = {
                  ipv4.method = "dhcp";
                  ipv6.method = "slaac";
                };
                explicit-static = {
                  hostAddresses = [ "192.0.2.1/24" ];
                };
              };
              bridges = {
                "rt--pppo-bcdf82" = {
                  originalName = "rt--pppo-bcdf82";
                  renderedName = "rt--pppo-bcdf82";
                };
                explicit-dynamic = {
                  originalName = "explicit-dynamic";
                  renderedName = "explicit-dynamic";
                };
                explicit-static = {
                  originalName = "explicit-static";
                  renderedName = "explicit-static";
                };
              };
              transitBridges = { };
              uplinks = { };
            };
          };
          networks = rendered.bridgeNetworks;
          implicit = networks."30-rt--pppo-bcdf82";
          dynamic = networks."30-explicit-dynamic";
          static = networks."30-explicit-static";
          allNetworks = builtins.toJSON networks;
          require = cond: msg: if cond then true else throw msg;
        in
          require (implicit.address == [ ])
            "implicit CPM/runtime bridge must not receive renderer-default host address"
          && require (implicit.networkConfig.DHCP == "no")
            "implicit CPM/runtime bridge must not enable DHCP without explicit bridge contract"
          && require ((implicit.networkConfig.IPv6AcceptRA or false) == false)
            "implicit CPM/runtime bridge must not enable SLAAC without explicit bridge contract"
          && require (builtins.match ".*10[.]11[.]0[.]1/24.*" allNetworks == null)
            "renderer output must not contain hardcoded 10.11.0.1/24"
          && require (dynamic.address == [ ])
            "explicit DHCP/SLAAC bridge must not receive static host address"
          && require (dynamic.networkConfig.DHCP == "ipv4")
            "explicit bridge ipv4.method=dhcp must render DHCP=ipv4"
          && require ((dynamic.networkConfig.IPv6AcceptRA or false) == true)
            "explicit bridge ipv6.method=slaac must render IPv6AcceptRA=true"
          && require (dynamic.networkConfig.LinkLocalAddressing == "ipv6")
            "explicit SLAAC bridge must keep IPv6 link-local addressing enabled"
          && require ((dynamic.dhcpV4Config.UseDNS or null) == false)
            "explicit bridge DHCP must not import resolver policy from DHCP"
          && require (static.address == [ "192.0.2.1/24" ])
            "explicit bridge hostAddresses must still render"
          && require (static.networkConfig.DHCP == "no")
            "static bridge hostAddresses must not imply DHCP"
      '

echo "PASS FS-310 NixOS bridge networks do not invent host IPs"
