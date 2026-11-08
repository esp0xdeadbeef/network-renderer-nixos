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

  targetName = "b-router-core-nebula";
  cfg =
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ built.renderedHost.containers.${targetName}.config ];
    }).config;

  networks = cfg.systemd.network.networks;
  networkNames = builtins.attrNames networks;

  routes = lib.concatMap (networkName: networks.${networkName}.routes or [ ]) networkNames;
  rules = lib.concatMap (networkName: networks.${networkName}.routingPolicyRules or [ ]) networkNames;

  services = lib.filterAttrs (
    name: _: lib.hasPrefix "s88-delegated-prefix" name
  ) cfg.systemd.services;
  scripts = lib.mapAttrs (
    _: service: builtins.readFile (lib.removeSuffix " " (service.serviceConfig.ExecStart or ""))
  ) services;

  hostileSourceFile = "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile";
  hostilePrefixes = [
    "10.70.10.0/24"
    "fd42:dead:feed:0070:0000:0000:0000:0000/64"
  ];
  hostileV4 = "10.70.10.0/24";
  hostileUla = "fd42:dead:feed:0070:0000:0000:0000:0000/64";

  hostileScripts = lib.filterAttrs (
    _: script: lib.hasInfix "source_file=${hostileSourceFile}" script
  ) scripts;

  policyTablesFor =
    prefix:
    lib.unique (
      map (rule: rule.Table) (
        builtins.filter (
          rule:
          (rule.From or null) == prefix
          && builtins.isInt (rule.Table or null)
          && (rule.Table or null) != 254
          && !(rule ? SuppressPrefixLength)
        ) rules
      )
    );
  mainFallbackFor =
    prefix:
    builtins.any (
      rule: (rule.From or null) == prefix && (rule.Table or null) == 254 && (rule ? SuppressPrefixLength)
    ) rules;
  hostileV4Tables = policyTablesFor hostileV4;
  hostileUlaTables = policyTablesFor hostileUla;

  hasTableLine = script: table: lib.hasInfix "table=${table}" script;
  mainScripts = lib.filterAttrs (_: script: hasTableLine script "''") hostileScripts;
  policyScripts =
    table: lib.filterAttrs (_: script: hasTableLine script (toString table)) hostileScripts;

  scriptHasModeledReturn =
    script:
    lib.hasInfix "interface=upstream" script
    && lib.hasInfix "gateway=fd42:dead:feed:1000:0:0:0:5" script
    && (
      lib.hasInfix "ip -6 route replace table \"$table\" \"$prefix\" via \"$gateway\" dev \"$interface\"" script
      || lib.hasInfix "ip -6 route replace  \"$prefix\" via \"$gateway\" dev \"$interface\"" script
    )
    && lib.hasInfix "proto static onlink" script;
  scriptFailsClosed = script: lib.hasInfix "exit 1" script;

  checks = {

    hostile_v4_policy_table = hostileV4Tables != [ ];
    hostile_ula_policy_table = hostileUlaTables != [ ];
    hostile_policy_tables_match =
      lib.sort builtins.lessThan hostileV4Tables == lib.sort builtins.lessThan hostileUlaTables;
    hostile_main_fallback = mainFallbackFor hostileV4 && mainFallbackFor hostileUla;

    no_static_hostile_route =
      !(builtins.any (route: builtins.elem (route.Destination or null) hostilePrefixes) routes);

    hostile_runtime_service = hostileScripts != { };
    hostile_runtime_main_install = mainScripts != { };
    hostile_runtime_policy_install = builtins.all (table: policyScripts table != { }) hostileV4Tables;
    hostile_runtime_tables_are_modeled = builtins.all (
      script:
      hasTableLine script "''"
      || builtins.any (table: hasTableLine script (toString table)) hostileV4Tables
    ) (builtins.attrValues hostileScripts);
    hostile_runtime_uses_modeled_return = builtins.all scriptHasModeledReturn (
      builtins.attrValues hostileScripts
    );
    hostile_runtime_fails_closed = builtins.all scriptFailsClosed (builtins.attrValues hostileScripts);
  };
  failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
in
{
  ok = failed == [ ];
  inherit failed checks;
  inherit
    hostileV4Tables
    hostileUlaTables
    ;
  serviceNames = builtins.attrNames hostileScripts;
  ruleTables = lib.unique (
    map (rule: rule.Table or null) (
      builtins.filter (rule: builtins.elem (rule.From or null) hostilePrefixes) rules
    )
  );
  routeDestinations = map (route: route.Destination or null) routes;
}
