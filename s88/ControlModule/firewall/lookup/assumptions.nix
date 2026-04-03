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

  wanNames =
    if interfaceView ? wanNames && builtins.isList interfaceView.wanNames then
      sortedStrings interfaceView.wanNames
    else
      [ ];

  lanNames =
    if interfaceView ? lanNames && builtins.isList interfaceView.lanNames then
      sortedStrings interfaceView.lanNames
    else
      [ ];

  p2pNames = sortedStrings (
    map (entry: entry.name or null) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  localAdapterNames = sortedStrings (
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

  uplinkNames =
    if builtins.isAttrs uplinks then lib.sort builtins.lessThan (builtins.attrNames uplinks) else [ ];

  accessUplinkNames = if p2pNames != [ ] then p2pNames else wanNames;

  entityName =
    if builtins.isString containerName && containerName != "" then
      containerName
    else if builtins.isString unitName && unitName != "" then
      unitName
    else
      null;

  policyScopeText = builtins.toJSON {
    enterprise = communication.currentRootName or null;
    site = communication.currentSiteName or null;
  };

  policyKnownInterfaces =
    if endpointMap ? allKnownInterfaces && builtins.isList endpointMap.allKnownInterfaces then
      sortedStrings endpointMap.allKnownInterfaces
    else
      [ ];

  alarms =
    lib.optionals (roleName == "access" && interfaceNames != [ ]) [
      (isa.mkDesignAssumptionAlarm {
        alarmId = "firewall-access-defaults";
        summary = "access firewall policy is currently synthesized from rendered interface classification";
        file = "s88/ControlModule/firewall/lookup/assumptions.nix";
        entityName = entityName;
        roleName = roleName;
        interfaces = sortedStrings (localAdapterNames ++ accessUplinkNames);
        assumptions = [
          "local adapter interfaces are inferred as any discovered interface whose source kind is neither 'wan' nor 'p2p'"
          "uplink interfaces are inferred from p2p interfaces when present, otherwise from wan interfaces"
          "bidirectional forwarding is emitted between every inferred local-adapter and inferred uplink interface"
          "TCP MSS clamping is applied to inferred p2p uplinks, or inferred wan uplinks when no p2p interfaces exist"
        ];
        extraText = [
          "resolved local adapters: ${builtins.toJSON localAdapterNames}"
          "resolved uplinks: ${builtins.toJSON accessUplinkNames}"
        ];
        authorityText = "Network forwarding model should provide authoritative access forwarding intent.";
      })
    ]
    ++ lib.optionals (roleName == "core" && interfaceNames != [ ]) [
      (isa.mkDesignAssumptionAlarm {
        alarmId = "firewall-core-defaults";
        summary = "core firewall policy is currently synthesized from rendered WAN/LAN inference";
        file = "s88/ControlModule/firewall/lookup/assumptions.nix";
        entityName = entityName;
        roleName = roleName;
        interfaces = sortedStrings (wanNames ++ lanNames);
        assumptions = [
          "WAN interfaces are inferred from explicit wanIfs plus interfaces whose source kind resolves to 'wan'"
          "LAN interfaces are inferred from explicit lanIfs plus every remaining discovered interface"
          "NAT enablement is inferred from the presence of WAN interfaces and uplink IPv4 flags, defaulting missing uplink IPv4 metadata to enabled"
          "masquerade is applied to every inferred WAN interface when NAT is considered enabled"
          "TCP MSS clamping is applied to every inferred WAN interface"
        ];
        extraText = [
          "resolved WAN interfaces: ${builtins.toJSON wanNames}"
          "resolved LAN interfaces: ${builtins.toJSON lanNames}"
          "resolved uplinks: ${builtins.toJSON uplinkNames}"
        ];
        authorityText = "Network forwarding model should provide authoritative WAN/LAN role assignment and NAT intent.";
      })
    ]
    ++ lib.optionals (roleName == "upstream-selector" && interfaceNames != [ ]) [
      (isa.mkDesignAssumptionAlarm {
        alarmId = "firewall-upstream-selector-defaults";
        summary = "upstream-selector firewall policy is currently synthesized from rendered transit interface discovery";
        file = "s88/ControlModule/firewall/lookup/assumptions.nix";
        entityName = entityName;
        roleName = roleName;
        interfaces = p2pNames;
        assumptions = [
          "transit candidates are inferred from interfaces whose source kind resolves to 'p2p'"
          "a full-mesh bidirectional forwarding policy is emitted between every distinct pair of inferred transit interfaces"
        ];
        extraText = [
          "resolved transit interfaces: ${builtins.toJSON p2pNames}"
        ];
        authorityText = "Network forwarding model should provide authoritative upstream-selector forwarding intent.";
      })
    ]
    ++ lib.optionals (roleName == "policy" && communication.communicationContract != { }) [
      (isa.mkDesignAssumptionAlarm {
        alarmId = "firewall-policy-endpoint-mapping";
        summary = "policy firewall endpoint mapping is currently synthesized from rendered interface and site metadata";
        file = "s88/ControlModule/firewall/lookup/assumptions.nix";
        entityName = entityName;
        roleName = roleName;
        interfaces = policyKnownInterfaces;
        assumptions = [
          "communication contract scope is selected from runtime logical-node enterprise/site hints instead of an explicit authoritative policy binding"
          "policy endpoints are mapped to rendered interfaces using site attachments, ownership data, service-provider membership, and token matching against interface reference strings"
          "the upstream/WAN endpoint is inferred from source-kind 'wan', explicit WAN interface names, or an upstream-selector naming convention"
          "renderer emits allow and deny rules only for endpoints it can heuristically map to rendered interface names"
        ];
        extraText = [
          "resolved communication scope: ${policyScopeText}"
          "resolved endpoint-capable interfaces: ${builtins.toJSON policyKnownInterfaces}"
        ];
        authorityText = "Network forwarding model should provide authoritative policy endpoint bindings.";
      })
    ];

  warningMessages = isa.warningsFromAlarms alarms;
in
{
  inherit alarms warningMessages;
  warnings = warningMessages;
}
