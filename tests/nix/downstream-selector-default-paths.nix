let
  repoRoot = builtins.getEnv "REPO_ROOT";
  boxName = builtins.getEnv "BOX_NAME";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  system = "x86_64-linux";

  containers = flake.lib.containers.buildForBox {
    inherit boxName system;
    intentPath = builtins.getEnv "INTENT_PATH";
    inventoryPath = builtins.getEnv "INVENTORY_PATH";
  };

  isDefault =
    route:
    (route.Destination or null) == "0.0.0.0/0"
    || (route.Destination or null) == "::/0"
    || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  isAccess = name: lib.hasPrefix "access-" name;
  isPolicy = name: lib.hasPrefix "policy-" name;

  parseAccept =
    index: line:
    let
      match = builtins.match ''[[:space:]]*iifname "([^"]+)" oifname "([^"]+)" accept( comment ".*")?[[:space:]]*'' line;
    in
    if match == null then
      null
    else
      {
        iif = builtins.elemAt match 0;
        oif = builtins.elemAt match 1;
        inherit index line;
      };

  tableForIngress =
    networks: iif:
    let
      rules = (networks."10-${iif}" or { }).routingPolicyRules or [ ];
      matches = builtins.filter (
        rule:
        (rule.Table or null) != null
        && (rule.Table or null) != 254
        && (rule.SuppressPrefixLength or null) == null
      ) rules;
    in
    if matches == [ ] then null else (builtins.head matches).Table;

  hasDefaultRoute =
    networks: oif: table:
    table != null
    && builtins.any (
      route:
      (route.Table or null) == table && isDefault route
    ) ((networks."10-${oif}" or { }).routes or [ ]);

  checkContainer =
    name: container:
    let
      cfg = (lib.nixosSystem {
        inherit system;
        modules = [ container.config ];
      }).config;
      networks = cfg.systemd.network.networks or { };
      lines = lib.splitString "\n" (cfg.networking.nftables.ruleset or "");
      accepts = lib.filter (entry: entry != null) (lib.imap0 parseAccept lines);
      accessPolicyAccepts = lib.filter (accept: isAccess accept.iif && isPolicy accept.oif) accepts;
      missingDefaults = lib.filter (
        accept:
        let table = tableForIngress networks accept.iif;
        in !(hasDefaultRoute networks accept.oif table)
      ) accessPolicyAccepts;
    in
    map (
      accept:
      let table = tableForIngress networks accept.iif;
      in
      {
        container = name;
        inherit (accept) iif oif line;
        ingressTable = table;
      }
    ) missingDefaults;

  downstreamSelectors = lib.filterAttrs (
    _: container: (container.specialArgs.s88RoleName or "") == "downstream-selector"
  ) containers;

  missingDefaultRoutes = lib.concatLists (lib.mapAttrsToList checkContainer downstreamSelectors);
in
{
  ok = missingDefaultRoutes == [ ];
  failed = lib.optionals (missingDefaultRoutes != [ ]) [ "downstream_selector_access_policy_default_routes" ];
  inherit missingDefaultRoutes;
}
