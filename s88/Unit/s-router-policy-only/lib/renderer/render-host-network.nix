{
  lib,
  inventory,
  hostName,
  cpm ? null,
}:

let
  validated = import ../inventory/validate.nix {
    inherit
      lib
      inventory
      hostName
      cpm
      ;
  };

  host = validated.deployment.hosts.${hostName};

  uplinks = host.uplinks;
  uplinkNames = lib.sort builtins.lessThan (builtins.attrNames uplinks);

  bridgeNetworkFor =
    bridge:
    if host ? bridgeNetworks && builtins.hasAttr bridge host.bridgeNetworks then
      host.bridgeNetworks.${bridge}
    else
      { ConfigureWithoutCarrier = true; };

  realizationNodes =
    if validated ? realization
      && builtins.isAttrs validated.realization
      && validated.realization ? nodes
      && builtins.isAttrs validated.realization.nodes
    then
      validated.realization.nodes
    else
      { };

  synthesizedTransitLinks =
    lib.unique (
      lib.concatMap (
        nodeName:
        let
          node = realizationNodes.${nodeName};
          ports =
            if node ? ports && builtins.isAttrs node.ports then
              node.ports
            else
              { };
        in
        if (node.host or null) == hostName then
          lib.concatMap (
            portName:
            let
              port = ports.${portName};
            in
            lib.optionals (
              builtins.isAttrs port
              && port ? link
              && builtins.isString port.link
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "direct"
            ) [
              port.link
            ]
          ) (builtins.attrNames ports)
        else
          [ ]
      ) (builtins.attrNames realizationNodes)
    );

  transitBridges =
    if host ? transitBridges && builtins.isAttrs host.transitBridges then
      host.transitBridges
    else
      builtins.listToAttrs (
        map (
          linkName:
          {
            name = linkName;
            value = {
              name = linkName;
            };
          }
        ) synthesizedTransitLinks
      );

  transitNames = lib.sort builtins.lessThan (builtins.attrNames transitBridges);

  parentNames =
    lib.unique (
      map (uplinkName: uplinks.${uplinkName}.parent) uplinkNames
    );

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
    if (uplink.mode or "") == "vlan" then
      "${uplink.parent}.${toString uplink.vlan}"
    else
      null;

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
            transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
          in
          {
            name = "12-${transitVlanIfName}";
            value = {
              netdevConfig = {
                Name = transitVlanIfName;
                Kind = "vlan";
              };
              vlanConfig.Id = transit.vlan;
            };
          }
        ) transitNamesOnUplink
      )
    ) uplinkNames
  );

  uplinkParentNetworks =
    builtins.listToAttrs (
      let
        parentEntries =
          map (
            parentIf:
            let
              uplinksOnParent =
                lib.filter (uplinkName: uplinks.${uplinkName}.parent == parentIf) uplinkNames;

              vlanChildren =
                lib.filter (name: name != null) (map vlanIfNameFor uplinksOnParent);

              directBridgeUplinks =
                lib.filter (
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
                  abort ''
                    renderer/lib/renderer/render-host-network.nix
                    hostName: ${hostName}
                    error: multiple non-vlan uplinks on parent '${parentIf}' are not supported
                    uplinks: ${builtins.toJSON directBridgeUplinks}
                  '';
            in
            {
              name = "20-${parentIf}";
              value = {
                matchConfig.Name = parentIf;
                networkConfig =
                  {
                    ConfigureWithoutCarrier = true;
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

        vlanBridgeEntries =
          lib.concatMap (
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
                  networkConfig = {
                    Bridge = uplink.bridge;
                    ConfigureWithoutCarrier = true;
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
        bridgeNetwork = bridgeNetworkFor uplink.bridge;
        transitNamesOnUplink = transitNamesForUplink uplinkName;
      in
      {
        name = "30-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          networkConfig =
            bridgeNetwork
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
      in
      {
        name = "40-${transit.name}";
        value = {
          netdevConfig = {
            Name = transit.name;
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
        parentUplink = transit.parentUplink or null;
      in
      [
        {
          name = "50-${transit.name}";
          value = {
            matchConfig.Name = transit.name;
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++ lib.optionals (parentUplink != null && builtins.hasAttr parentUplink uplinks && (uplinks.${parentUplink}.mode or "") == "trunk") [
        {
          name =
            let
              uplink = uplinks.${parentUplink};
              transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
            in
            "51-${transitVlanIfName}";
          value =
            let
              uplink = uplinks.${parentUplink};
              transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
            in
            {
              matchConfig.Name = transitVlanIfName;
              networkConfig = {
                Bridge = transit.name;
                ConfigureWithoutCarrier = true;
              };
            };
        }
      ]
    ) transitNames
  );
in
{
  netdevs = uplinkNetdevs // transitNetdevs;
  networks = uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks;
}
