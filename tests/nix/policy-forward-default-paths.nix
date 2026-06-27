let
  repoRoot = builtins.getEnv "REPO_ROOT";
  boxName = builtins.getEnv "BOX_NAME";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  system = "x86_64-linux";
  cpmPath = builtins.getEnv "CPM_PATH";
  cpm =
    if cpmPath == "" then
      { }
    else
      builtins.fromJSON (builtins.readFile cpmPath);

  containers = flake.lib.containers.buildForBox {
    inherit boxName system;
    intentPath = builtins.getEnv "INTENT_PATH";
    inventoryPath = builtins.getEnv "INVENTORY_PATH";
    inherit cpm;
  };

  isDefault =
    route:
    (route.Destination or null) == "0.0.0.0/0"
    || (route.Destination or null) == "::/0"
    || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  isDownstream = name:
    lib.hasPrefix "downstr-" name || lib.hasPrefix "downstream-" name || lib.hasPrefix "down-" name;

  isUpstream = name:
    lib.hasPrefix "up-" name || lib.hasPrefix "upstream-" name;

  parseTerminal =
    index: line:
    let
      match = builtins.match ''[[:space:]]*iifname "([^"]+)" oifname "([^"]+)"(.*)'' line;
      suffix = if match == null then "" else builtins.elemAt match 2;
      action =
        if lib.hasInfix " accept" suffix then
          "accept"
        else if lib.hasInfix " drop" suffix then
          "drop"
        else
          null;
      typed =
        lib.hasInfix "meta l4proto" suffix
        || lib.hasInfix "ip protocol" suffix
        || lib.hasInfix "ip6 nexthdr" suffix;
    in
    if match == null || action == null then
      null
    else
      {
        iif = builtins.elemAt match 0;
        oif = builtins.elemAt match 1;
        inherit action;
        inherit typed;
        inherit index;
        inherit line;
      };

  pairKey = pair: "${pair.iif}->${pair.oif}";

  tableForIngress =
    networks: iif:
    let
      rules = (networks."10-${iif}" or { }).routingPolicyRules or [ ];
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

  hasDefaultRoute =
    networks: oif: table:
    table != null
    && builtins.any
      (
        route:
        (route.Table or null) == table && isDefault route
      )
      ((networks."10-${oif}" or { }).routes or [ ]);

  checkContainer =
    name: container:
    let
      policyCpmTargets = lib.filter
        (
          target:
          (target.role or "") == "policy"
          && ((target.logicalNode or { }).name or "") == name
        )
        (
          lib.concatMap
            (
              enterprise:
              lib.concatMap
                (
                  site:
                  builtins.attrValues (
                    (((cpm.control_plane_model or { }).data or { }).${enterprise}.${site}.runtimeTargets or { })
                  )
                )
                (builtins.attrNames (((cpm.control_plane_model or { }).data or { }).${enterprise} or { }))
            )
            (builtins.attrNames (((cpm.control_plane_model or { }).data or { })))
        );
      cpmForwardingRules = lib.concatMap
        (
          target:
          if builtins.isList ((target.forwardingIntent or { }).rules or null) then
            target.forwardingIntent.rules
          else
            [ ]
        )
        policyCpmTargets;
      cpmHasUntypedDeny = builtins.any
        (
          rule:
          (rule.action or null) == "deny"
          && ((rule.trafficType or "any") == "any")
        )
        cpmForwardingRules;
      cpmTypedDenyRelationIds = lib.unique (
        lib.filter (id: id != null) (
          map
            (
              rule:
              if
                (rule.action or null) == "deny"
                && (rule.trafficType or "any") != "any"
                && builtins.isString (rule.relationId or null)
              then
                rule.relationId
              else
                null
            )
            cpmForwardingRules
        )
      );
      cfg = (lib.nixosSystem {
        inherit system;
        modules = [ container.config ];
      }).config;
      networks = cfg.systemd.network.networks or { };
      lines = lib.splitString "\n" (cfg.networking.nftables.ruleset or "");
      terminals = lib.filter (entry: entry != null) (lib.imap0 parseTerminal lines);
      bareDrops = lib.filter (entry: entry.action == "drop" && !(entry.typed or false)) terminals;
      accepts = lib.filter (entry: entry.action == "accept") terminals;
      drops = lib.filter (entry: entry.action == "drop" && !(entry.typed or false)) terminals;
      hasEarlierDrop =
        accept:
        builtins.any
          (
            drop: pairKey drop == pairKey accept && drop.index < accept.index
          )
          drops;
      conflictingPairs = lib.filter hasEarlierDrop accepts;
      downstreamUplinkAccepts = lib.filter
        (
          accept:
          isDownstream accept.iif
          && isUpstream accept.oif
          && !(lib.hasInfix "east-west" accept.line)
          && !(lib.hasSuffix "-ew" accept.oif)
        )
        accepts;
      missingDefaults = lib.filter
        (
          accept:
          let table = tableForIngress networks accept.iif;
          in !(hasDefaultRoute networks accept.oif table)
        )
        downstreamUplinkAccepts;
      typedDenyWithoutTypedRender = lib.filter
        (
          relationId:
            !(builtins.any
              (
                line:
                lib.hasInfix "drop comment \"${relationId}\"" line
                && (lib.hasInfix "meta l4proto" line || lib.hasInfix "ip protocol" line || lib.hasInfix "ip6 nexthdr" line)
              )
              lines)
        )
        cpmTypedDenyRelationIds;
    in
    {
      typedDenyRelationIds = cpmTypedDenyRelationIds;
      downstreamUplinkAcceptCount = builtins.length downstreamUplinkAccepts;
      cpmParityViolations =
        (lib.optionals (!cpmHasUntypedDeny && bareDrops != [ ]) (
          map
            (drop: {
              container = name;
              reason = "renderer emitted an untyped drop even though CPM has no trafficType=any deny rule";
              inherit (drop) iif oif line;
            })
            bareDrops
        ))
        ++ (map
          (relationId: {
            container = name;
            reason = "CPM typed deny relation was not rendered as a typed nft drop";
            inherit relationId;
          })
          typedDenyWithoutTypedRender);
      terminalConflicts = map
        (pair: {
          container = name;
          inherit (pair) iif oif line;
        })
        conflictingPairs;
      missingDefaultRoutes = map
        (
          pair:
          let table = tableForIngress networks pair.iif;
          in
          {
            container = name;
            inherit (pair) iif oif line;
            ingressTable = table;
          }
        )
        missingDefaults;
    };

  policyContainers = lib.filterAttrs
    (
      _: container: (container.specialArgs.s88RoleName or "") == "policy"
    )
    containers;

  results = lib.mapAttrsToList checkContainer policyContainers;
  cpmParityViolations = lib.concatMap (result: result.cpmParityViolations) results;
  terminalConflicts = lib.concatMap (result: result.terminalConflicts) results;
  missingDefaultRoutes = lib.concatMap (result: result.missingDefaultRoutes) results;
  typedDenyRelationIds = lib.unique (lib.concatMap (result: result.typedDenyRelationIds) results);
  downstreamUplinkAcceptCount = builtins.foldl'
    (total: result: total + result.downstreamUplinkAcceptCount)
    0
    results;
  coverageViolations =
    (lib.optionals (builtins.length results == 0) [
      { reason = "renderer produced no policy containers to inspect"; }
    ])
    ++
    (lib.optionals (typedDenyRelationIds == [ ]) [
      { reason = "CPM fixture produced no typed deny relations"; }
    ]);
in
{
  ok =
    coverageViolations == [ ]
    && cpmParityViolations == [ ]
    && terminalConflicts == [ ]
    && missingDefaultRoutes == [ ];
  failed =
    (lib.optionals (coverageViolations != [ ]) [ "policy_cpm_firewall_parity_inactive" ])
    ++
    (lib.optionals (cpmParityViolations != [ ]) [ "cpm_renderer_policy_semantics_parity" ])
    ++
    (lib.optionals (terminalConflicts != [ ]) [ "policy_nft_terminal_conflicts" ])
    ++ (lib.optionals (missingDefaultRoutes != [ ]) [ "policy_downstream_uplink_default_routes" ]);
  coverage = {
    policyContainerCount = builtins.length results;
    typedDenyRelationCount = builtins.length typedDenyRelationIds;
    inherit typedDenyRelationIds downstreamUplinkAcceptCount;
  };
  inherit cpmParityViolations terminalConflicts missingDefaultRoutes coverageViolations;
}
