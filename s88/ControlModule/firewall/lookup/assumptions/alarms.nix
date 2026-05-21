{ lib
, isa
, assumptionFamily
, roleName
, entityName
, interfaceNames
, localAdapterNames
, accessUplinkNames
, forwardingIntentResolved
, wanNames
, lanNames
, uplinkNames
, p2pNames
, communicationResolved
, endpointMapResolved
,
}:

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
      interfaces = lib.sort builtins.lessThan (lib.unique (localAdapterNames ++ accessUplinkNames));
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
++ lib.optionals
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
      interfaces = lib.sort builtins.lessThan (lib.unique (wanNames ++ lanNames));
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
++ lib.optionals
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
++ lib.optionals
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
          lib.sort builtins.lessThan (lib.unique endpointMapResolved.allKnownInterfaces)
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
  ]
