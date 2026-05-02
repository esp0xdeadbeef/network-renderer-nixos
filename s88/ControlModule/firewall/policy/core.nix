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

  inputRules = [
    ''
      icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept comment "allow-ipv6-nd-ra"
    ''
  ]
  ++ lib.optional (interfaceSet.overlayIngressNames != [ ]) ''
    iifname ${
      if builtins.length interfaceSet.overlayIngressNames == 1 then
        "\"${builtins.head interfaceSet.overlayIngressNames}\""
      else
        "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") interfaceSet.overlayIngressNames)} }"
    } accept comment "allow-overlay-to-core"
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
