{
  lib,
  interfaceView ? null,
  forwardingIntent ? null,
  communicationContract ? { },
  ownership ? { },
  inventory ? { },
  unitName ? null,
  runtimeTarget ? { },
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
  ...
}:

let
  common = import ./core/common.nix { inherit lib; };

  interfaceSet = import ./core/interfaces.nix {
    inherit lib interfaceView interfaces wanIfs lanIfs common;
  };

  catalog = import ./core/catalog.nix {
    inherit communicationContract ownership inventory common;
  };

  serviceNat = import ./core/service-nat.nix {
    inherit lib catalog interfaceSet common;
  };

  forwarding = import ./core/forwarding.nix {
    inherit lib forwardingIntent uplinks;
    inherit (interfaceSet)
      wanNames
      lanNames
      forwardEgressNames
      overlayIngressNames
      adapterNames
      ;
  };

  renderedNat = import ./core/render-nat.nix {
    inherit lib serviceNat;
    inherit (common) relationNameOf;
  };

  nebulaTrafficTypes =
    builtins.filter
      (trafficType: builtins.isAttrs trafficType && (trafficType.name or null) == "nebula")
      (communicationContract.trafficTypes or [ ]);
  nebulaUdpPorts =
    lib.unique (
      lib.concatMap
        (trafficType:
          lib.concatMap
            (match:
              if builtins.isAttrs match && (match.proto or null) == "udp" then match.dports or [ ] else [ ])
            (trafficType.match or [ ]))
        nebulaTrafficTypes
    );
  renderInterfaceSet = names:
    if builtins.length names == 1 then
      "\"${builtins.head names}\""
    else
      "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") names)} }";
  renderPortSet = ports:
    if builtins.length ports == 1 then
      toString (builtins.head ports)
    else
      "{ ${builtins.concatStringsSep ", " (map toString ports)} }";
  nebulaUnderlayNames = common.sortedStrings (
    lib.subtractLists interfaceSet.overlayIngressNames interfaceSet.forwardEgressNames
  );

  inputRules = [
    ''
      icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment "allow-ipv6-nd-ra"
    ''
  ]
  ++ lib.optional (interfaceSet.overlayIngressNames != [ ]) ''
    iifname ${renderInterfaceSet interfaceSet.overlayIngressNames} accept comment "allow-overlay-to-core"
  ''
  ++ lib.optional (interfaceSet.overlayIngressNames != [ ] && nebulaUnderlayNames != [ ] && nebulaUdpPorts != [ ]) ''
    iifname ${renderInterfaceSet nebulaUnderlayNames} meta l4proto udp udp dport ${renderPortSet nebulaUdpPorts} accept comment "allow-nebula-underlay-to-core"
  '';

  _validateCoreAdapterCount =
    if builtins.length interfaceSet.adapterNames == 1 then
      throw ''
        s88/ControlModule/firewall/policy/core.nix: core role requires at least two adapters

        unitName:
        ${builtins.toJSON unitName}

        adapters:
        ${builtins.toJSON interfaceSet.adapterNames}
      ''
    else
      true;
in
if interfaceSet.wanNames == [ ] && interfaceSet.lanNames == [ ] then
  null
else
  builtins.seq _validateCoreAdapterCount {
    tableName = "router";
    inputPolicy = "drop";
    outputPolicy = "accept";
    forwardPolicy = "drop";
    inherit inputRules;
    inherit (forwarding) forwardPairs natInterfaces clampMssInterfaces;
    inherit (renderedNat) natPreroutingRules4 natPreroutingRules6;
    forwardRules = renderedNat.portForwardForwardRules;
  }
