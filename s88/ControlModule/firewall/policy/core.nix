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

  underlayInput = import ./core/underlay-input.nix {
    inherit lib catalog;
  };
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
  explicitTransitUnderlayNames =
    if forwardingIntent != null && builtins.isAttrs forwardingIntent then
      lib.filter (name: builtins.elem name interfaceSet.adapterNames) (
        (forwardingIntent.explicitTransitNames or [ ]) ++ (forwardingIntent.resolvedTransitNames or [ ])
      )
    else
      [ ];
  nebulaUnderlayNames =
    if explicitTransitUnderlayNames != [ ] then
      common.sortedStrings explicitTransitUnderlayNames
    else
      common.sortedStrings (lib.subtractLists interfaceSet.overlayIngressNames interfaceSet.forwardEgressNames);

  inputRules = [
    ''
      icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment "allow-ipv6-nd-ra"
    ''
  ]
  ++ lib.optional (interfaceSet.overlayIngressNames != [ ]) ''
    iifname ${renderInterfaceSet interfaceSet.overlayIngressNames} accept comment "allow-overlay-to-core"
  ''
  ++ lib.optional (interfaceSet.overlayIngressNames != [ ] && nebulaUnderlayNames != [ ] && underlayInput.udpPorts != [ ]) ''
    iifname ${renderInterfaceSet nebulaUnderlayNames} meta l4proto udp udp dport ${renderPortSet underlayInput.udpPorts} accept comment "allow-nebula-underlay-to-core"
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
