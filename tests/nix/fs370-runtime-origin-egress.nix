let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  built = import (repoRoot + "/tests/nix/build-host-from-paths.nix") {
    selector = "s-router-test";
    system = "x86_64-linux";
    intentPath = builtins.getEnv "INTENT_PATH";
    inventoryPath = builtins.getEnv "INVENTORY_PATH";
  };

  containers = built.renderedHost.containers;
  configFor =
    name:
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ containers.${name}.config ];
    }).config;

  data = built.controlPlaneOut.control_plane_model.data;
  allTargets = lib.concatMap (
    enterprise:
    lib.concatMap (site: builtins.attrValues (site.runtimeTargets or { })) (
      builtins.attrValues enterprise
    )
  ) (builtins.attrValues data);

  enabledTargets = builtins.filter (
    target:
    (target.runtimeOriginEgress.enabled or false) == true
    && builtins.isAttrs (target.runtimeOriginEgress.preferredSources or null)
    && builtins.isString (target.logicalNode.name or null)
    && builtins.hasAttr target.logicalNode.name containers
  ) allTargets;

  prefixForAddress = address: if lib.hasInfix ":" address then "${address}/128" else "${address}/32";

  factsFor =
    target:
    let
      name = target.logicalNode.name;
      cfg = configFor name;
      networks = cfg.systemd.network.networks;
      networkNames = builtins.attrNames networks;
      routes = lib.concatMap (networkName: networks.${networkName}.routes or [ ]) networkNames;
      rules = lib.concatMap (networkName: networks.${networkName}.routingPolicyRules or [ ]) networkNames;
      preferredSources = target.runtimeOriginEgress.preferredSources;
      preferences = builtins.filter (value: builtins.isString value) [
        (preferredSources.ipv4 or null)
        (preferredSources.ipv6 or null)
      ];
      preferredDefaults = builtins.filter (
        route: builtins.isString (route.PreferredSource or null) && builtins.isInt (route.Table or null)
      ) routes;
      sourceScopedRules = builtins.filter (
        rule:
        builtins.isString (rule.From or null)
        && builtins.isInt (rule.Table or null)
        && !(rule ? SuppressPrefixLength)
      ) rules;
      checkFor =
        preference:
        let
          sourcePrefix = prefixForAddress preference;
          preferredRoutes = builtins.filter (
            route: (route.PreferredSource or null) == preference
          ) preferredDefaults;
          preferredTables = lib.unique (map (route: route.Table) preferredRoutes);
          sourceTables = lib.unique (
            map (rule: rule.Table) (
              builtins.filter (rule: (rule.From or null) == sourcePrefix) sourceScopedRules
            )
          );

          defaultsArePolicyRoutes = builtins.all (
            route: (route.GatewayOnLink or false) == true
          ) preferredRoutes;
        in
        {
          inherit
            preference
            sourcePrefix
            sourceTables
            preferredTables
            ;
          ok =
            preferredRoutes != [ ]
            && defaultsArePolicyRoutes
            && sourceTables != [ ]
            && builtins.any (table: builtins.elem table preferredTables) sourceTables;
        };
    in
    {
      inherit name;
      checks = map checkFor preferences;
    };

  facts = map factsFor enabledTargets;
  failures = lib.concatMap (
    fact:
    map (check: {
      target = fact.name;
      inherit (check)
        preference
        sourcePrefix
        sourceTables
        preferredTables
        ;
    }) (builtins.filter (check: !check.ok) fact.checks)
  ) facts;
  withoutPreferences = map (fact: fact.name) (builtins.filter (fact: fact.checks == [ ]) facts);

in
if enabledTargets == [ ] then
  throw "runtime-origin: no rendered target publishes an enabled runtimeOriginEgress contract"
else if withoutPreferences != [ ] then
  throw (
    "runtime-origin: enabled contract without a preferred source: " + builtins.toJSON withoutPreferences
  )
else if failures != [ ] then
  throw ("runtime-origin: rendered preferred-source binding missing: " + builtins.toJSON failures)
else
  true
