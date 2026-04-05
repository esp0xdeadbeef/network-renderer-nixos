{
  lib,
  cpm ? null,
  flakeInputs ? null,
  runtimeTarget ? { },
  unitName ? null,
  containerName ? null,
  roleName ? null,
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
}:

let
  isa = import ../../alarm/isa18.nix { inherit lib; };

  interfaceView = import ./interface-view.nix {
    inherit
      lib
      interfaces
      wanIfs
      lanIfs
      ;
  };

  forwardingIntent = import ./forwarding-intent.nix {
    inherit
      lib
      runtimeTarget
      interfaces
      wanIfs
      lanIfs
      uplinks
      ;
  };

  communication =
    if cpm != null then
      import ./communication-contract.nix {
        inherit
          lib
          cpm
          flakeInputs
          runtimeTarget
          ;
      }
    else
      {
        currentRootName = null;
        currentSiteName = null;
        currentSite = { };
        forwardingModel = { };
        forwardingSite = { };
        communicationContract = { };
        ownership = { };
      };

  endpointMap =
    if cpm != null then
      import ../mapping/policy-endpoints.nix {
        inherit
          lib
          interfaceView
          runtimeTarget
          ;
        currentSite = communication.currentSite;
        communicationContract = communication.communicationContract;
        ownership = communication.ownership;
      }
    else
      {
        resolveEndpoint = _: [ ];
        allKnownInterfaces = [ ];
        wanNames = interfaceView.wanNames or [ ];
        p2pNames = [ ];
        localAdapterNames = interfaceView.lanNames or [ ];
        authoritativeBindings = false;
        authorityGaps = [ ];
      };

  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

  sourceKindOf =
    entry:
    if entry ? sourceKind && builtins.isString entry.sourceKind then
      entry.sourceKind
    else if
      entry ? iface
      && builtins.isAttrs entry.iface
      && entry.iface ? sourceKind
      && builtins.isString entry.iface.sourceKind
    then
      entry.iface.sourceKind
    else
      null;

  interfaceEntries =
    if interfaceView ? interfaceEntries && builtins.isList interfaceView.interfaceEntries then
      interfaceView.interfaceEntries
    else
      [ ];

  interfaceNames = sortedStrings (map (entry: entry.name or null) interfaceEntries);

  fallbackWanNames =
    if interfaceView ? wanNames && builtins.isList interfaceView.wanNames then
      sortedStrings interfaceView.wanNames
    else
      [ ];

  fallbackLanNames =
    if interfaceView ? lanNames && builtins.isList interfaceView.lanNames then
      sortedStrings interfaceView.lanNames
    else
      [ ];

  fallbackP2pNames = sortedStrings (
    map (entry: entry.name or null) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  wanNames =
    if forwardingIntent ? resolvedWanNames && builtins.isList forwardingIntent.resolvedWanNames then
      sortedStrings forwardingIntent.resolvedWanNames
    else
      fallbackWanNames;

  lanNames =
    if forwardingIntent ? resolvedLanNames && builtins.isList forwardingIntent.resolvedLanNames then
      sortedStrings forwardingIntent.resolvedLanNames
    else
      fallbackLanNames;

  p2pNames =
    if
      forwardingIntent ? resolvedTransitNames && builtins.isList forwardingIntent.resolvedTransitNames
    then
      sortedStrings forwardingIntent.resolvedTransitNames
    else
      fallbackP2pNames;

  localAdapterNames =
    if
      forwardingIntent ? resolvedLocalAdapterNames
      && builtins.isList forwardingIntent.resolvedLocalAdapterNames
    then
      sortedStrings forwardingIntent.resolvedLocalAdapterNames
    else
      sortedStrings (
        map (entry: entry.name or null) (
          lib.filter (
            entry:
            let
              sourceKind = sourceKindOf entry;
            in
            sourceKind != "wan" && sourceKind != "p2p"
          ) interfaceEntries
        )
      );

  accessUplinkNames =
    if
      forwardingIntent ? resolvedAccessUplinkNames
      && builtins.isList forwardingIntent.resolvedAccessUplinkNames
    then
      sortedStrings forwardingIntent.resolvedAccessUplinkNames
    else if p2pNames != [ ] then
      p2pNames
    else
      wanNames;

  uplinkNames =
    if builtins.isAttrs uplinks then lib.sort builtins.lessThan (builtins.attrNames uplinks) else [ ];

  entityName =
    if builtins.isString containerName && containerName != "" then
      containerName
    else if builtins.isString unitName && unitName != "" then
      unitName
    else
      null;

  alarms =
    lib.optionals
      (
        roleName == "access"
        && interfaceNames != [ ]
        && localAdapterNames != [ ]
        && accessUplinkNames != [ ]
        && !(forwardingIntent.authoritativeAccessForwarding or false)
      )
      [
        (isa.mkDesignAssumptionAlarm {
          alarmId = "firewall-access-forwarding-defaults";
          summary = "access firewall forwarding policy is currently synthesized from role defaults";
          file = "s88/ControlModule/firewall/lookup/assumptions.nix";
          entityName = entityName;
          roleName = roleName;
          interfaces = sortedStrings (localAdapterNames ++ accessUplinkNames);
          assumptions = [
            "local-adapter and uplink roles are resolved from explicit interface semantics when available, but forwarding allowance itself still defaults from the access role procedure"
            "bidirectional forwarding is emitted between every resolved local-adapter and resolved uplink interface"
            "TCP MSS clamping is applied to resolved p2p uplinks, or resolved WAN uplinks when no p2p uplinks exist"
          ];
          extraText = [
            "resolved local adapters: ${builtins.toJSON localAdapterNames}"
            "resolved uplinks: ${builtins.toJSON accessUplinkNames}"
          ];
          authorityText = "Network forwarding model should provide authoritative access forwarding intent.";
        })
      ]
    ++
      lib.optionals
        (
          roleName == "core"
          && interfaceNames != [ ]
          && wanNames != [ ]
          && !(forwardingIntent.authoritativeCoreNat or false)
        )
        [
          (isa.mkDesignAssumptionAlarm {
            alarmId = "firewall-core-nat-defaults";
            summary = "core firewall NAT intent is currently synthesized from role defaults and uplink IPv4 inference";
            file = "s88/ControlModule/firewall/lookup/assumptions.nix";
            entityName = entityName;
            roleName = roleName;
            interfaces = sortedStrings (wanNames ++ lanNames);
            assumptions = [
              "WAN and LAN interface roles are resolved from explicit interface semantics when available, but NAT enablement itself is not authored explicitly"
              "NAT enablement is inferred from the presence of WAN interfaces and uplink IPv4 flags, defaulting missing uplink IPv4 metadata to enabled"
              "masquerade is applied to every resolved WAN interface when NAT is considered enabled"
              "TCP MSS clamping is applied to every resolved WAN interface"
            ];
            extraText = [
              "resolved WAN interfaces: ${builtins.toJSON wanNames}"
              "resolved LAN interfaces: ${builtins.toJSON lanNames}"
              "resolved uplinks: ${builtins.toJSON uplinkNames}"
            ];
            authorityText = "Network forwarding model should provide authoritative core NAT intent.";
          })
        ]
    ++
      lib.optionals
        (
          (roleName == "upstream-selector" || roleName == "downstream-selector")
          && builtins.length p2pNames > 1
          && !(forwardingIntent.authoritativeUpstreamSelectorForwarding or false)
        )
        [
          (isa.mkDesignAssumptionAlarm {
            alarmId = "firewall-${roleName}-forwarding-defaults";
            summary = "${roleName} firewall forwarding policy is currently synthesized from role defaults";
            file = "s88/ControlModule/firewall/lookup/assumptions.nix";
            entityName = entityName;
            roleName = roleName;
            interfaces = p2pNames;
            assumptions = [
              "transit interface roles are resolved from explicit interface semantics when available, but forwarding allowance itself still defaults from the selector role procedure"
              "a full-mesh bidirectional forwarding policy is emitted between every distinct resolved transit interface"
            ];
            extraText = [
              "resolved transit interfaces: ${builtins.toJSON p2pNames}"
            ];
            authorityText = "Network forwarding model should provide authoritative selector forwarding intent.";
          })
        ]
    ++
      lib.optionals
        (
          roleName == "policy"
          && communication.communicationContract != { }
          && !(endpointMap.authoritativeBindings or false)
        )
        [
          (isa.mkDesignAssumptionAlarm {
            alarmId = "firewall-policy-endpoint-bindings-missing";
            summary = "policy firewall endpoint bindings are not fully explicit in the available control-plane data";
            file = "s88/ControlModule/firewall/lookup/assumptions.nix";
            entityName = entityName;
            roleName = roleName;
            interfaces =
              if endpointMap ? allKnownInterfaces && builtins.isList endpointMap.allKnownInterfaces then
                sortedStrings endpointMap.allKnownInterfaces
              else
                [ ];
            assumptions = [
              "policy endpoint bindings require explicit site policy tags plus explicit tenant and upstream transit bindings"
              "renderer can only emit allow and deny rules for endpoints that can be bound from the available explicit site data"
            ];
            extraText =
              if endpointMap ? authorityGaps && builtins.isList endpointMap.authorityGaps then
                endpointMap.authorityGaps
              else
                [ ];
            authorityText = "Control plane should provide canonical policy endpoint bindings and site.policy.interfaceTags.";
          })
        ];

  warningMessages = isa.warningsFromAlarms alarms;
in
{
  inherit alarms warningMessages;
  warnings = warningMessages;
}
