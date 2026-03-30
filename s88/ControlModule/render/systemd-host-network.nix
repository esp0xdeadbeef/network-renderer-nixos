{
  lib,
  hostPlan,
}:

let
  hostNaming = import ../../../../lib/host-naming.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentHost = hostPlan.deploymentHost or { };
  bridges = hostPlan.bridges or { };
  uplinks = hostPlan.uplinks or { };
  transitBridges = hostPlan.transitBridges or { };
  hostHasUplinks = hostPlan.hostHasUplinks or false;

  bridgeNetworks =
    if deploymentHost ? bridgeNetworks && builtins.isAttrs deploymentHost.bridgeNetworks then
      deploymentHost.bridgeNetworks
    else
      { };

  localBridgeNetdevs = builtins.listToAttrs (
    map (bridgeName: {
      name = "10-${bridges.${bridgeName}.renderedName}";
      value = {
        netdevConfig = {
          Name = bridges.${bridgeName}.renderedName;
          Kind = "bridge";
        };
      };
    }) (sortedAttrNames bridges)
  );

  localBridgeNetworks = builtins.listToAttrs (
    map (bridgeName: {
      name = "30-${bridges.${bridgeName}.renderedName}";
      value = {
        matchConfig.Name = bridges.${bridgeName}.renderedName;
        linkConfig = {
          ActivationPolicy = "always-up";
          RequiredForOnline = "no";
        };
        networkConfig = {
          ConfigureWithoutCarrier = true;
        };
      };
    }) (sortedAttrNames bridges)
  );

  uplinkNames = sortedAttrNames uplinks;
  transitNames = sortedAttrNames transitBridges;

  transitNamesForUplink =
    uplinkName:
    lib.filter (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      (transit.parentUplink or null) == uplinkName
    ) transitNames;

  vlanIfNameFor =
    uplinkName:
    let
      uplink = uplinks.${uplinkName};
    in
    if (uplink.mode or "") == "vlan" then "${uplink.parent}.${toString uplink.vlan}" else null;

  bridgeNetworkFor =
    uplink:
    let
      originalBridge =
        if uplink ? originalBridge && builtins.isString uplink.originalBridge then
          uplink.originalBridge
        else
          uplink.bridge;
    in
    if builtins.hasAttr originalBridge bridgeNetworks then
      bridgeNetworks.${originalBridge}
    else
      { ConfigureWithoutCarrier = true; };

  uplinkNetdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        vlanIfName = vlanIfNameFor uplinkName;
      in
      [
        {
          name = "10-${uplink.bridge}";
          value = {
            netdevConfig = {
              Name = uplink.bridge;
              Kind = "bridge";
            };
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "vlan") [
        {
          name = "11-${vlanIfName}";
          value = {
            netdevConfig = {
              Name = vlanIfName;
              Kind = "vlan";
            };
            vlanConfig.Id = uplink.vlan;
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "trunk") (
        map (
          transitName:
          let
            transit = transitBridges.${transitName};
            transitNameRendered =
              if transit ? name && builtins.isString transit.name then
                transit.name
              else
                hostNaming.shorten transitName;
          in
          {
            name = "12-${transitNameRendered}";
            value = {
              netdevConfig = {
                Name = "${uplink.bridge}.${toString transit.vlan}";
                Kind = "vlan";
              };
              vlanConfig.Id = transit.vlan;
            };
          }
        ) transitNamesOnUplink
      )
    ) uplinkNames
  );

  parentNames = lib.unique (
    lib.filter builtins.isString (map (uplinkName: uplinks.${uplinkName}.parent or null) uplinkNames)
  );

  uplinkParentNetworks = builtins.listToAttrs (
    let
      parentEntries = map (
        parentIf:
        let
          uplinksOnParent = lib.filter (uplinkName: uplinks.${uplinkName}.parent == parentIf) uplinkNames;

          vlanChildren = lib.filter (name: name != null) (map vlanIfNameFor uplinksOnParent);

          directBridgeUplinks = lib.filter (
            uplinkName:
            let
              mode = uplinks.${uplinkName}.mode or "";
            in
            mode != "vlan"
          ) uplinksOnParent;

          _singleDirectBridge =
            if builtins.length directBridgeUplinks <= 1 then
              true
            else
              throw ''
                s88/CM/network/render/systemd-host-network.nix: multiple non-vlan uplinks on parent '${parentIf}' are not supported

                uplinks:
                ${builtins.concatStringsSep "\n  - " ([ "" ] ++ directBridgeUplinks)}
              '';
        in
        builtins.seq _singleDirectBridge {
          name = "20-${parentIf}";
          value = {
            matchConfig.Name = parentIf;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig = {
              ConfigureWithoutCarrier = true;
              LinkLocalAddressing = "no";
              IPv6AcceptRA = false;
            }
            // lib.optionalAttrs (vlanChildren != [ ]) {
              VLAN = vlanChildren;
            }
            // lib.optionalAttrs (builtins.length directBridgeUplinks == 1) {
              Bridge = uplinks.${builtins.head directBridgeUplinks}.bridge;
            };
          };
        }
      ) parentNames;

      vlanBridgeEntries = lib.concatMap (
        uplinkName:
        let
          uplink = uplinks.${uplinkName};
          vlanIfName = vlanIfNameFor uplinkName;
        in
        lib.optionals ((uplink.mode or "") == "vlan") [
          {
            name = "21-${vlanIfName}";
            value = {
              matchConfig.Name = vlanIfName;
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
              networkConfig = {
                Bridge = uplink.bridge;
                ConfigureWithoutCarrier = true;
                LinkLocalAddressing = "no";
                IPv6AcceptRA = false;
              };
            };
          }
        ]
      ) uplinkNames;
    in
    parentEntries ++ vlanBridgeEntries
  );

  uplinkBridgeNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        baseBridgeNetworkConfig = bridgeNetworkFor uplink;
      in
      {
        name = "30-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = {
            ConfigureWithoutCarrier = true;
            DHCP = "no";
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          }
          // baseBridgeNetworkConfig
          // lib.optionalAttrs ((uplink.mode or "") == "trunk" && transitNamesOnUplink != [ ]) {
            VLAN = map (
              transitName:
              let
                transit = transitBridges.${transitName};
              in
              "${uplink.bridge}.${toString transit.vlan}"
            ) transitNamesOnUplink;
          };
        };
      }
    ) uplinkNames
  );

  transitNetdevs = builtins.listToAttrs (
    map (
      transitName:
      let
        transit = transitBridges.${transitName};
        transitNameRendered =
          if transit ? name && builtins.isString transit.name then
            transit.name
          else
            hostNaming.shorten transitName;
      in
      {
        name = "40-${transitNameRendered}";
        value = {
          netdevConfig = {
            Name = transitNameRendered;
            Kind = "bridge";
          };
        };
      }
    ) transitNames
  );

  transitNetworks = builtins.listToAttrs (
    lib.concatMap (
      transitName:
      let
        transit = transitBridges.${transitName};
        transitNameRendered =
          if transit ? name && builtins.isString transit.name then
            transit.name
          else
            hostNaming.shorten transitName;
        parentUplink = transit.parentUplink or null;
      in
      [
        {
          name = "50-${transitNameRendered}";
          value = {
            matchConfig.Name = transitNameRendered;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++
        lib.optionals
          (
            parentUplink != null
            && builtins.hasAttr parentUplink uplinks
            && (uplinks.${parentUplink}.mode or "") == "trunk"
          )
          [
            {
              name = "51-${uplinks.${parentUplink}.bridge}.${toString transit.vlan}";
              value = {
                matchConfig.Name = "${uplinks.${parentUplink}.bridge}.${toString transit.vlan}";
                linkConfig = {
                  ActivationPolicy = "always-up";
                  RequiredForOnline = "no";
                };
                networkConfig = {
                  Bridge = transitNameRendered;
                  ConfigureWithoutCarrier = true;
                  LinkLocalAddressing = "no";
                  IPv6AcceptRA = false;
                };
              };
            }
          ]
    ) transitNames
  );

  netdevs =
    if hostHasUplinks then
      localBridgeNetdevs // uplinkNetdevs // transitNetdevs
    else
      localBridgeNetdevs;

  networks =
    if hostHasUplinks then
      localBridgeNetworks // uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks
    else
      localBridgeNetworks;
in
{
  inherit netdevs networks;
}
