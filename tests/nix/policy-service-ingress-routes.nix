let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  system = "x86_64-linux";

  containers = flake.lib.containers.buildForBox {
    boxName = "s-router-hetzner-anywhere";
    inherit system;
    intentPath = builtins.getEnv "INTENT_PATH";
    inventoryPath = builtins.getEnv "INVENTORY_PATH";
  };

  cfg = (lib.nixosSystem {
    inherit system;
    modules = [ containers."c-router-policy".config ];
  }).config;

  networks = cfg.systemd.network.networks or { };
  ruleset = cfg.networking.nftables.ruleset or "";

  tableForIngress =
    networkName:
    let
      rules = (networks.${networkName} or { }).routingPolicyRules or [ ];
      matches = builtins.filter
        (
          rule:
          (rule.Table or null) != null
          && (rule.Table or null) != 254
          && (rule.SuppressPrefixLength or null) == null
        )
        rules;
    in
    if matches == [ ] then null else (builtins.head matches).Table;

  hasRoute =
    destination: gateway: table:
    table != null
    && builtins.any
      (
        networkName:
        builtins.any
          (
            route:
            (route.Table or null) == table
            && (route.Destination or null) == destination
            && (route.Gateway or null) == gateway
          )
          ((networks.${networkName} or { }).routes or [ ])
      )
      (builtins.attrNames networks);

  upClientEwTable = tableForIngress "10-up-client-ew";

  checks = {
    nft_allows_sitec_dns_from_east_west =
      lib.hasInfix
        "iifname \"up-client-ew\" oifname \"downstream-dmz\" meta l4proto udp udp dport { 53 } accept comment \"allow-east-west-to-sitec-dmz-dns\""
        ruleset;
    route_v4_sitec_dns_from_east_west =
      hasRoute "10.90.10.0/24" "10.80.0.8" upClientEwTable;
    route_v6_sitec_dns_from_east_west =
      hasRoute "fd42:dead:cafe:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:8" upClientEwTable;
  };
in
{
  ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
  failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
  inherit checks upClientEwTable;
}
