     1|#!/usr/bin/env bash
     2|set -euo pipefail
     3|
     4|repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
     5|source "${repo_root}/tests/lib/test-common.sh"
     6|
     7|example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
     8|intent_path="${example_root}/intent.nix"
     9|inventory_path="${example_root}/inventory-nixos.nix"
    10|tmp_dir="$(mktemp -d)"
    11|
    12|result_json="$(mktemp)"
    13|eval_stderr="$(mktemp)"
    14|trap 'rm -rf "${tmp_dir}"; rm -f "${result_json}" "${eval_stderr}"' EXIT
    15|
    16|mutated_intent="${tmp_dir}/intent.nix"
    17|mutated_inventory="${tmp_dir}/inventory-nixos.nix"
    18|
    19|cat >"${mutated_intent}" <<EOF
    20|import ${intent_path}
    21|EOF
    22|
    23|cat >"${mutated_inventory}" <<EOF
    24|let
    25|  base = import ${inventory_path};
    26|  hostile = base.realization.nodes."espbranch-site-b-b-router-access-hostile";
    27|  hostileServices = hostile.services;
    28|  hostileDns = hostileServices.dns;
    29|in
    30|base // {
    31|  endpoints = base.endpoints // {
    32|    sitec-dns-alt = {
    33|      ipv4 = [ "10.90.10.53" ];
    34|      ipv6 = [ "fd42:dead:cafe:10::53" ];
    35|    };
    36|  };
    37|  realization = base.realization // {
    38|    nodes = base.realization.nodes // {
    39|      "espbranch-site-b-b-router-access-hostile" = hostile // {
    40|        services = hostileServices // {
    41|          dns = hostileDns // {
    42|            forwarders = [
    43|              "10.90.10.53"
    44|              "fd42:dead:cafe:10::53"
    45|            ];
    46|          };
    47|        };
    48|      };
    49|    };
    50|  };
    51|}
    52|EOF
    53|
    54|nix_eval_json_or_fail \
    55|  cross-site-dns-service-render \
    56|  "${result_json}" \
    57|  "${eval_stderr}" \
    58|  env REPO_ROOT="${repo_root}" \
    59|    INTENT_PATH="${intent_path}" \
    60|    INVENTORY_PATH="${inventory_path}" \
    61|    MUTATED_INTENT_PATH="${mutated_intent}" \
    62|    MUTATED_INVENTORY_PATH="${mutated_inventory}" \
    63|    nix eval \
    64|    --extra-experimental-features 'nix-command flakes' \
    65|    --impure --json --expr '
    66|      let
    67|        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
    68|        lib = flake.inputs.nixpkgs.lib;
    69|        system = "x86_64-linux";
    70|        build = boxName:
    71|          import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
72|            inherit boxName system;
    73|            intentPath = builtins.getEnv "INTENT_PATH";
    74|            inventoryPath = builtins.getEnv "INVENTORY_PATH";
    75|
};
    76|        configFor = containers: name:
    77|          (flake.inputs.nixpkgs.lib.nixosSystem {
    78|            inherit system;
    79|            modules = [ containers.${name}.config ];
    80|          }).config;
    81|        branch = build "s-router-test";
    82|        siteC = build "s-router-hetzner-anywhere";
    83|   import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
85|            boxName = "s-router-test";
    86|            inherit system;
    87|            intentPath = builtins.getEnv "MUTATED_INTENT_PATH";
    88|            inventoryPath = builtins.getEnv "MUTATED_INVENTORY_PATH";
    89|
}ED_INVENTORY_PATH";
    89|          };
    90|        hostileAccess = configFor branch "b-router-access-hostile";
    91|        coreNebula = configFor branch "b-router-core-nebula";
    92|        mutatedHostileAccess = configFor mutatedBranch "b-router-access-hostile";
    93|        sitecDns = configFor siteC "c-router-access-dmz";
    94|        hostileUnbound = hostileAccess.services.unbound.settings;
    95|        mutatedHostileUnbound = mutatedHostileAccess.services.unbound.settings;
    96|        sitecUnbound = sitecDns.services.unbound.settings;
    97|        hostileServer = hostileUnbound.server;
    98|        sitecServer = sitecUnbound.server;
    99|        hostileForwardZone = builtins.head hostileUnbound.forward-zone;
   100|        mutatedHostileForwardZone = builtins.head mutatedHostileUnbound.forward-zone;
   101|        sitecForwardZone = builtins.head sitecUnbound.forward-zone;
   102|        hostileNftScript = hostileAccess.systemd.services.nft-allow-dns-service.script;
   103|        coreNebulaNftScript = coreNebula.systemd.services.nft-allow-dns-service.script;
   104|        sitecNftScript = sitecDns.systemd.services.nft-allow-dns-service.script;
   105|        hostileRules = hostileAccess.networking.nftables.ruleset;
   106|        sitecRules = sitecDns.networking.nftables.ruleset;
   107|        has = lib.hasInfix;
   108|        hasMember = value: values: builtins.elem value values;
   109|        noMember = value: values: !(builtins.elem value values);
   110|        checks = {
   111|          hostile_listens_on_tenant_dns_v4 =
   112|            hasMember "10.70.10.1" hostileServer.interface;
   113|          hostile_listens_on_tenant_dns_v6 =
   114|            hasMember "fd42:dead:feed:70::1" hostileServer.interface;
   115|          hostile_forwards_to_sitea_dns_v4 =
   116|            hasMember "10.20.10.1" hostileForwardZone.forward-addr;
   117|          hostile_forwards_to_sitea_dns_v6 =
   118|            hasMember "fd42:dead:beef:10::1" hostileForwardZone.forward-addr;
   119|          hostile_does_not_invent_sitec_dns_v4 =
   120|            noMember "10.90.10.1" hostileForwardZone.forward-addr;
   121|          hostile_does_not_invent_sitec_dns_v6 =
   122|            noMember "fd42:dead:cafe:10::1" hostileForwardZone.forward-addr;
   123|          mutated_hostile_forwards_to_inventory_endpoint_v4 =
   124|            hasMember "10.90.10.53" mutatedHostileForwardZone.forward-addr;
   125|          mutated_hostile_forwards_to_inventory_endpoint_v6 =
   126|            hasMember "fd42:dead:cafe:10::53" mutatedHostileForwardZone.forward-addr;
   127|          mutated_hostile_does_not_keep_default_sitec_dns_v4 =
   128|            noMember "10.90.10.1" mutatedHostileForwardZone.forward-addr;
   129|          mutated_hostile_does_not_keep_default_sitec_dns_v6 =
   130|            noMember "fd42:dead:cafe:10::1" mutatedHostileForwardZone.forward-addr;
   131|          mutated_hostile_does_not_keep_sitea_dns_v4 =
   132|            noMember "10.20.10.1" mutatedHostileForwardZone.forward-addr;
   133|          mutated_hostile_does_not_keep_sitea_dns_v6 =
   134|            noMember "fd42:dead:beef:10::1" mutatedHostileForwardZone.forward-addr;
   135|          hostile_dns_nft_opens_ipv4 =
   136|            has "ip daddr 10.70.10.1 udp dport 53 accept comment \"allow-dns-service\"" hostileNftScript;
   137|          hostile_dns_nft_opens_ipv6 =
   138|            has "ip6 daddr fd42:dead:feed:70::1 udp dport 53 accept comment \"allow-dns-service\"" hostileNftScript;
   139|          hostile_direct_dns_leak_drop =
   140|            has "iifname \"tenant-hostile\" udp dport 53 drop comment \"deny-direct-dns-egress\"" hostileNftScript
   141|            || has "type filter hook forward priority filter; policy drop;" hostileRules;
   142|          hostile_forward_chain_defaults_drop =
   143|            has "type filter hook forward priority filter; policy drop;" hostileRules;
   144|          core_nebula_blocks_public_dns_forward_leak_v4 =
   145|            has "insert rule inet router forward iifname \"upstream\" ip daddr 1.1.1.1/32 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" coreNebulaNftScript;
   146|          core_nebula_blocks_public_dns_forward_leak_v6 =
   147|            has "insert rule inet router forward iifname \"upstream\" ip6 daddr 2606:4700:4700::1111/128 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" coreNebulaNftScript;
   148|          sitec_dns_listens_on_service_v4 =
   149|            hasMember "10.90.10.1" sitecServer.interface;
   150|          sitec_dns_listens_on_service_v6 =
   151|            hasMember "fd42:dead:cafe:10::1" sitecServer.interface;
   152|          sitec_dns_forwards_to_public_v4 =
   153|            hasMember "1.1.1.1" sitecForwardZone.forward-addr
   154|            && hasMember "9.9.9.9" sitecForwardZone.forward-addr;
   155|          sitec_dns_forwards_to_public_v6 =
   156|            hasMember "2606:4700:4700::1111" sitecForwardZone.forward-addr
   157|            && hasMember "2620:fe::fe" sitecForwardZone.forward-addr;
   158|          sitec_dns_egress_uses_service_source_v4 =
   159|            hasMember "10.90.10.1" (sitecServer."outgoing-interface" or [ ]);
   160|          sitec_dns_egress_uses_service_source_v6 =
   161|            hasMember "fd42:dead:cafe:10::1" (sitecServer."outgoing-interface" or [ ]);
   162|          sitec_dns_nft_opens_ipv4 =
   163|            has "ip daddr 10.90.10.1 udp dport 53 accept comment \"allow-dns-service\"" sitecNftScript;
   164|          sitec_dns_nft_opens_ipv6 =
   165|            has "ip6 daddr fd42:dead:cafe:10::1 udp dport 53 accept comment \"allow-dns-service\"" sitecNftScript;
   166|          sitec_dns_nft_allows_service_egress =
   167|            has "allow-dns-service-egress" sitecNftScript;
   168|          sitec_dns_nft_drops_public_dns_output_leak =
   169|            has "deny-public-dns-output-leak" sitecNftScript;
   170|          sitec_direct_dns_leak_drop =
   171|            has "iifname \"transit\" udp dport 53 drop comment \"deny-direct-dns-egress\"" sitecNftScript
   172|            || has "iifname \"transit\" ip daddr 1.1.1.1/32 udp dport 53 drop comment \"deny-public-dns-forward-leak\"" sitecNftScript
   173|            || has "type filter hook forward priority filter; policy drop;" sitecRules;
   174|          sitec_forward_chain_defaults_drop =
   175|            has "type filter hook forward priority filter; policy drop;" sitecRules;
   176|        };
   177|      in
   178|      {
   179|        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
   180|        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
   181|        inherit checks;
   182|      }
   183|    '
   184|
   185|assert_json_checks_ok cross-site-dns-service-render "${result_json}"
   186|
   187|echo "PASS cross-site-dns-service-render"
   188|