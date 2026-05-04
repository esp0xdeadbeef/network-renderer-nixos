#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-test-three-site"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"
tmp_dir="$(mktemp -d)"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -rf "${tmp_dir}"; rm -f "${result_json}" "${eval_stderr}"' EXIT

mutated_intent="${tmp_dir}/intent.nix"
mutated_inventory="${tmp_dir}/inventory-nixos.nix"

cat >"${mutated_intent}" <<EOF
let
  base = import ${intent_path};
  siteB = base.espbranch."site-b";
  contract = siteB.communicationContract;
  rewriteService =
    service:
    if service.name or null == "sitec-public-dns" then
      service // { providers = [ "sitec-dns-alt" ]; }
    else
      service;
in
base // {
  espbranch = base.espbranch // {
    "site-b" = siteB // {
      communicationContract = contract // {
        services = map rewriteService contract.services;
      };
    };
  };
}
EOF

cat >"${mutated_inventory}" <<EOF
let
  base = import ${inventory_path};
in
base // {
  endpoints = base.endpoints // {
    sitec-dns-alt = {
      ipv4 = [ "10.90.10.53" ];
      ipv6 = [ "fd42:dead:cafe:10::53" ];
    };
  };
}
EOF

nix_eval_json_or_fail \
  cross-site-dns-service-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    MUTATED_INTENT_PATH="${mutated_intent}" \
    MUTATED_INVENTORY_PATH="${mutated_inventory}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        system = "x86_64-linux";
        build = boxName:
          flake.lib.containers.buildForBox {
            inherit boxName system;
            intentPath = builtins.getEnv "INTENT_PATH";
            inventoryPath = builtins.getEnv "INVENTORY_PATH";
          };
        configFor = containers: name:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ containers.${name}.config ];
          }).config;
        branch = build "s-router-test";
        siteC = build "s-router-hetzner-anywhere";
        mutatedBranch =
          flake.lib.containers.buildForBox {
            boxName = "s-router-test";
            inherit system;
            intentPath = builtins.getEnv "MUTATED_INTENT_PATH";
            inventoryPath = builtins.getEnv "MUTATED_INVENTORY_PATH";
          };
        hostileAccess = configFor branch "b-router-access-hostile";
        mutatedHostileAccess = configFor mutatedBranch "b-router-access-hostile";
        mutatedBranchUpstream = configFor mutatedBranch "b-router-upstream-selector";
        sitecDns = configFor siteC "c-router-access-dmz";
        hostileUnbound = hostileAccess.services.unbound.settings;
        mutatedHostileUnbound = mutatedHostileAccess.services.unbound.settings;
        sitecUnbound = sitecDns.services.unbound.settings;
        hostileServer = hostileUnbound.server;
        sitecServer = sitecUnbound.server;
        hostileForwardZone = builtins.head hostileUnbound.forward-zone;
        mutatedHostileForwardZone = builtins.head mutatedHostileUnbound.forward-zone;
        sitecForwardZone = builtins.head sitecUnbound.forward-zone;
        hostileNftScript = hostileAccess.systemd.services.nft-allow-dns-service.script;
        sitecNftScript = sitecDns.systemd.services.nft-allow-dns-service.script;
        hostileRules = hostileAccess.networking.nftables.ruleset;
        sitecRules = sitecDns.networking.nftables.ruleset;
        mutatedBranchUpstreamNetworks = mutatedBranchUpstream.systemd.network.networks;
        mutatedCoreNebulaRoutes = mutatedBranchUpstreamNetworks."10-core-nebula".routes or [ ];
        has = lib.hasInfix;
        hasMember = value: values: builtins.elem value values;
        noMember = value: values: !(builtins.elem value values);
        hasRenderedRoute = routes: destination: gateway: table:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            routes;
        checks = {
          hostile_listens_on_tenant_dns_v4 =
            hasMember "10.70.10.1" hostileServer.interface;
          hostile_listens_on_tenant_dns_v6 =
            hasMember "fd42:dead:feed:70::1" hostileServer.interface;
          hostile_forwards_to_sitec_dns_v4 =
            hasMember "10.90.10.1" hostileForwardZone.forward-addr;
          hostile_forwards_to_sitec_dns_v6 =
            hasMember "fd42:dead:cafe:10::1" hostileForwardZone.forward-addr;
          hostile_does_not_forward_to_sitea_dns_v4 =
            noMember "10.20.10.1" hostileForwardZone.forward-addr;
          hostile_does_not_forward_to_sitea_dns_v6 =
            noMember "fd42:dead:beef:10::1" hostileForwardZone.forward-addr;
          mutated_hostile_forwards_to_inventory_endpoint_v4 =
            hasMember "10.90.10.53" mutatedHostileForwardZone.forward-addr;
          mutated_hostile_forwards_to_inventory_endpoint_v6 =
            hasMember "fd42:dead:cafe:10::53" mutatedHostileForwardZone.forward-addr;
          mutated_hostile_does_not_keep_default_sitec_dns_v4 =
            noMember "10.90.10.1" mutatedHostileForwardZone.forward-addr;
          mutated_hostile_does_not_keep_default_sitec_dns_v6 =
            noMember "fd42:dead:cafe:10::1" mutatedHostileForwardZone.forward-addr;
          mutated_route_to_inventory_endpoint_v4 =
            hasRenderedRoute mutatedCoreNebulaRoutes "10.90.10.53" "10.50.0.4" 2004;
          mutated_route_to_inventory_endpoint_v6 =
            hasRenderedRoute mutatedCoreNebulaRoutes "fd42:dead:cafe:10::53" "fd42:dead:feed:1000:0:0:0:4" 2004;
          hostile_dns_nft_opens_ipv4 =
            has "ip daddr 10.70.10.1 udp dport 53 accept comment \"allow-dns-service\"" hostileNftScript;
          hostile_dns_nft_opens_ipv6 =
            has "ip6 daddr fd42:dead:feed:70::1 udp dport 53 accept comment \"allow-dns-service\"" hostileNftScript;
          hostile_direct_dns_leak_drop =
            has "iifname \\\"tenant-hostile\\\" udp dport 53 drop comment \"deny-direct-dns-egress\"" hostileNftScript;
          hostile_forward_chain_defaults_drop =
            has "type filter hook forward priority filter; policy drop;" hostileRules;
          sitec_dns_listens_on_service_v4 =
            hasMember "10.90.10.1" sitecServer.interface;
          sitec_dns_listens_on_service_v6 =
            hasMember "fd42:dead:cafe:10::1" sitecServer.interface;
          sitec_dns_forwards_to_public_v4 =
            hasMember "1.1.1.1" sitecForwardZone.forward-addr
            && hasMember "9.9.9.9" sitecForwardZone.forward-addr;
          sitec_dns_forwards_to_public_v6 =
            hasMember "2606:4700:4700::1111" sitecForwardZone.forward-addr
            && hasMember "2620:fe::fe" sitecForwardZone.forward-addr;
          sitec_dns_nft_opens_ipv4 =
            has "ip daddr 10.90.10.1 udp dport 53 accept comment \"allow-dns-service\"" sitecNftScript;
          sitec_dns_nft_opens_ipv6 =
            has "ip6 daddr fd42:dead:cafe:10::1 udp dport 53 accept comment \"allow-dns-service\"" sitecNftScript;
          sitec_direct_dns_leak_drop =
            has "iifname \\\"tenant-dmz\\\" udp dport 53 drop comment \"deny-direct-dns-egress\"" sitecNftScript;
          sitec_forward_chain_defaults_drop =
            has "type filter hook forward priority filter; policy drop;" sitecRules;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok cross-site-dns-service-render "${result_json}"

echo "PASS cross-site-dns-service-render"
