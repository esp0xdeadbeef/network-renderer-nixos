{
  lib,
  cpm ? null,
  flakeInputs ? null,
  runtimeTarget ? { },
  unitName ? null,
  containerName ? null,
  roleName ? null,
  assumptionFamily ? null,
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
  interfaceView ? null,
  forwardingIntent ? null,
  communication ? null,
  endpointMap ? null,
}:

let
  isa = import ../../alarm/isa18.nix { inherit lib; };

  interfaceViewResolved =
    if interfaceView != null then
      interfaceView
    else
      import ./interface-view.nix {
        inherit
          lib
          interfaces
          wanIfs
          lanIfs
          ;
      };

  forwardingIntentResolved =
    if forwardingIntent != null then
      forwardingIntent
    else
      import ./forwarding-intent.nix {
        inherit
          lib
          runtimeTarget
          interfaces
          wanIfs
          lanIfs
          uplinks
          ;
      };

  communicationResolved =
    if communication != null then
      communication
    else if cpm != null then
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

  endpointMapResolved =
    if endpointMap != null then
      endpointMap
    else if cpm != null then
      import ../mapping/policy-endpoints.nix {
        inherit
          lib
          runtimeTarget
          roleName
          unitName
          containerName
          ;
        interfaceView = interfaceViewResolved;
        currentSite = communicationResolved.currentSite;
        communicationContract = communicationResolved.communicationContract;
        ownership = communicationResolved.ownership;
      }
    else
      {
        resolveEndpoint = _: [ ];
        allKnownInterfaces = [ ];
        wanNames = interfaceViewResolved.wanNames or [ ];
        p2pNames = [ ];
        localAdapterNames = interfaceViewResolved.lanNames or [ ];
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
    if interfaceViewResolved ? interfaceEntries && builtins.isList interfaceViewResolved.interfaceEntries then
      interfaceViewResolved.interfaceEntries
    else
      [ ];

  interfaceNames = sortedStrings (map (entry: entry.name or null) interfaceEntries);

  fallbackWanNames =
    if interfaceViewResolved ? wanNames && builtins.isList interfaceViewResolved.wanNames then
      sortedStrings interfaceViewResolved.wanNames
    else
      [ ];

  fallbackLanNames =
    if interfaceViewResolved ? lanNames && builtins.isList interfaceViewResolved.lanNames then
      sortedStrings interfaceViewResolved.lanNames
    else
      [ ];

  fallbackP2pNames = sortedStrings (
    map (entry: entry.name or null) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  wanNames =
    if forwardingIntentResolved ? resolvedWanNames && builtins.isList forwardingIntentResolved.resolvedWanNames then
      sortedStrings forwardingIntentResolved.resolvedWanNames
    else
      fallbackWanNames;

  lanNames =
    if forwardingIntentResolved ? resolvedLanNames && builtins.isList forwardingIntentResolved.resolvedLanNames then
      sortedStrings forwardingIntentResolved.resolvedLanNames
    else
      fallbackLanNames;

  p2pNames =
    if
      forwardingIntentResolved ? resolvedTransitNames && builtins.isList forwardingIntentResolved.resolvedTransitNames
    then
      sortedStrings forwardingIntentResolved.resolvedTransitNames
    else
      fallbackP2pNames;

  localAdapterNames =
    if
      forwardingIntentResolved ? resolvedLocalAdapterNames
      && builtins.isList forwardingIntentResolved.resolvedLocalAdapterNames
    then
      sortedStrings forwardingIntentResolved.resolvedLocalAdapterNames
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
      forwardingIntentResolved ? resolvedAccessUplinkNames
      && builtins.isList forwardingIntentResolved.resolvedAccessUplinkNames
    then
      sortedStrings forwardingIntentResolved.resolvedAccessUplinkNames
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
        assumptionFamily == "edge"
        && interfaceNames != [ ]
        && localAdapterNames != [ ]
        && accessUplinkNames != [ ]
        && !(forwardingIntentResolved.authoritativeAccessForwarding or false)
      )
      [
        (isa.mkDesignAssumptionAlarm {
          alarmId = "firewall-${roleName}-forwarding-defaults";
          summary = "${roleName} firewall forwarding policy is currently synthesized from role defaults";
          file = "s88/ControlModule/firewall/lookup/assumptions.nix";
          entityName = entityName;
          roleName = roleName;
          interfaces = sortedStrings (localAdapterNames ++ accessUplinkNames);
          assumptions = [
            "local-adapter and uplink roles are resolved from explicit interface semantics when available, but forwarding allowance itself still defaults from the ${roleName} role procedure"
            "bidirectional forwarding is emitted between every resolved local-adapter and resolved uplink interface"
            "TCP MSS clamping is applied to resolved p2p uplinks, or resolved WAN uplinks when no p2p uplinks exist"
          ];
          extraText = [
            "resolved local adapters: ${builtins.toJSON localAdapterNames}"
            "resolved uplinks: ${builtins.toJSON accessUplinkNames}"
          ];
          authorityText = "Network forwarding model should provide authoritative ${roleName} forwarding intent.";
        })
      ]
    ++
      lib.optionals
        (
          assumptionFamily == "egress"
          && interfaceNames != [ ]
          && wanNames != [ ]
          && !(forwardingIntentResolved.authoritativeCoreNat or false)
        )
        [
          (isa.mkDesignAssumptionAlarm {
            alarmId = "firewall-${roleName}-nat-defaults";
            summary = "${roleName} firewall NAT intent is currently synthesized from role defaults and uplink IPv4 inference";
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
            authorityText = "Network forwarding model should provide authoritative ${roleName} NAT intent.";
          })
        ]
    ++
      lib.optionals
        (
          assumptionFamily == "selector"
          && builtins.length p2pNames > 1
          && !(forwardingIntentResolved.authoritativeUpstreamSelectorForwarding or false)
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
              "transit interface roles are resolved from explicit interface semantics when available"
              "missing authoritative selector forwarding intent is treated as fail-closed; no selector transit accept rules are synthesized"
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
          assumptionFamily == "endpoint"
          && communicationResolved.communicationContract != { }
          && !(endpointMapResolved.authoritativeBindings or false)
        )
        [
          (isa.mkDesignAssumptionAlarm {
            alarmId = "firewall-${roleName}-endpoint-bindings-missing";
            summary = "${roleName} firewall endpoint bindings are not fully explicit in the available control-plane data";
            file = "s88/ControlModule/firewall/lookup/assumptions.nix";
            entityName = entityName;
            roleName = roleName;
            interfaces =
              if endpointMapResolved ? allKnownInterfaces && builtins.isList endpointMapResolved.allKnownInterfaces then
                sortedStrings endpointMapResolved.allKnownInterfaces
              else
                [ ];
            assumptions = [
              "${roleName} endpoint bindings require explicit site tags plus explicit tenant and upstream transit bindings"
              "renderer can only emit allow and deny rules for endpoints that can be bound from the available explicit site data"
            ];
            extraText =
              if endpointMapResolved ? authorityGaps && builtins.isList endpointMapResolved.authorityGaps then
                endpointMapResolved.authorityGaps
              else
                [ ];
            authorityText = "Control plane should provide canonical ${roleName} endpoint bindings and site interface tags.";
          })
        ];

  warningMessages = isa.warningsFromAlarms alarms;
in
{
  inherit alarms warningMessages;
  warnings = warningMessages;
}
