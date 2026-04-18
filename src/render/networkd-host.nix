{ lib }:
hostModel:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  uplinkNames = sortedAttrNames hostModel.uplinks;

  renderedUplinkNames = lib.filter (
    uplinkName:
    let
      uplink = hostModel.uplinks.${uplinkName};
    in
    uplink.kind == "bridge" || uplink.kind == "vlan-bridge"
  ) uplinkNames;

  keepaliveNameFor = bridgeName: "ka-${bridgeName}";

  parentGrouped = builtins.foldl' (
    acc: uplinkName:
    let
      uplink = hostModel.uplinks.${uplinkName};
      parentName = uplink.parent;

      existing =
        if builtins.hasAttr parentName acc then
          acc.${parentName}
        else
          {
            vlanInterfaces = [ ];
            bridgeUplinks = [ ];
          };

      updated =
        if uplink.kind == "vlan-bridge" then
          existing
          // {
            vlanInterfaces = existing.vlanInterfaces ++ [ uplink.vlanInterfaceName ];
          }
        else
          existing
          // {
            bridgeUplinks = existing.bridgeUplinks ++ [ uplink ];
          };
    in
    acc
    // {
      "${parentName}" = updated;
    }
  ) { } renderedUplinkNames;

  parentNames = sortedAttrNames parentGrouped;

  _validateParentUsage = builtins.foldl' (
    acc: parentName:
    let
      parentGroup = parentGrouped.${parentName};
    in
    if builtins.length parentGroup.bridgeUplinks > 1 then
      throw "network-renderer-nixos: parent '${parentName}' resolves to multiple direct bridge uplinks"
    else if parentGroup.bridgeUplinks != [ ] && parentGroup.vlanInterfaces != [ ] then
      throw "network-renderer-nixos: parent '${parentName}' cannot be both a direct bridge uplink and a VLAN parent"
    else
      acc
  ) true parentNames;

  netdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
        keepaliveName = keepaliveNameFor uplink.bridgeName;
      in
      if uplink.kind == "vlan-bridge" then
        [
          {
            name = uplink.vlanInterfaceName;
            value = {
              netdevConfig = {
                Kind = "vlan";
                Name = uplink.vlanInterfaceName;
              };
              vlanConfig = {
                Id = uplink.vlanId;
              };
            };
          }
          {
            name = uplink.bridgeName;
            value = {
              netdevConfig = {
                Kind = "bridge";
                Name = uplink.bridgeName;
              };
            };
          }
          {
            name = keepaliveName;
            value = {
              netdevConfig = {
                Kind = "dummy";
                Name = keepaliveName;
              };
            };
          }
        ]
      else
        [
          {
            name = uplink.bridgeName;
            value = {
              netdevConfig = {
                Kind = "bridge";
                Name = uplink.bridgeName;
              };
            };
          }
          {
            name = keepaliveName;
            value = {
              netdevConfig = {
                Kind = "dummy";
                Name = keepaliveName;
              };
            };
          }
        ]
    ) renderedUplinkNames
  );

  parentNetworks = builtins.listToAttrs (
    map (
      parentName:
      let
        parentGroup = parentGrouped.${parentName};
      in
      {
        name = "10-${parentName}";
        value =
          if parentGroup.vlanInterfaces != [ ] then
            {
              matchConfig.Name = parentName;
              networkConfig.VLAN = lib.unique parentGroup.vlanInterfaces;
            }
          else
            let
              uplink = builtins.head parentGroup.bridgeUplinks;
            in
            {
              matchConfig.Name = parentName;
              networkConfig.Bridge = uplink.bridgeName;
            };
      }
    ) parentNames
  );

  keepaliveNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
        keepaliveName = keepaliveNameFor uplink.bridgeName;
      in
      {
        name = "15-${keepaliveName}";
        value = {
          matchConfig.Name = keepaliveName;
          networkConfig = {
            Bridge = uplink.bridgeName;
            ConfigureWithoutCarrier = true;
          };
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
        };
      }
    ) renderedUplinkNames
  );

  childNetworks = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
      in
      if uplink.kind == "vlan-bridge" then
        [
          {
            name = "20-${uplink.vlanInterfaceName}";
            value = {
              matchConfig.Name = uplink.vlanInterfaceName;
              networkConfig.Bridge = uplink.bridgeName;
            };
          }
          {
            name = "30-${uplink.bridgeName}";
            value = {
              matchConfig.Name = uplink.bridgeName;
              networkConfig = uplink.networkOptions // {
                ConfigureWithoutCarrier = true;
              };
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
            };
          }
        ]
      else
        [
          {
            name = "20-${uplink.bridgeName}";
            value = {
              matchConfig.Name = uplink.bridgeName;
              networkConfig = uplink.networkOptions // {
                ConfigureWithoutCarrier = true;
              };
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
            };
          }
        ]
    ) renderedUplinkNames
  );

  renderedNetworks = parentNetworks // keepaliveNetworks // childNetworks;
in
builtins.seq _validateParentUsage {
  hostName = hostModel.hostName;
  deploymentHostName = hostModel.deploymentHostName;
  netdevs = netdevs;
  networks = renderedNetworks;
  debug = hostModel.debug // {
    renderedNetdevs = builtins.attrNames netdevs;
    renderedNetworks = builtins.attrNames renderedNetworks;
    renderedParentNetworks = builtins.attrNames parentNetworks;
  };
}
