{
  config,
  lib,
  globalInventory,
  ...
}:

let
  inventory = globalInventory;
  hostname = config.networking.hostName;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  renderHosts =
    if inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  renderHostConfig =
    if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
      renderHosts.${hostname}
    else
      { };

  deploymentHosts =
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      throw "host-network/network.nix: inventory.deployment.hosts missing";

  deploymentHostNames = sortedAttrNames deploymentHosts;

  realizationNodes =
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  deploymentHostName =
    if renderHostConfig ? deploymentHost
      && builtins.isString renderHostConfig.deploymentHost
      && builtins.hasAttr renderHostConfig.deploymentHost deploymentHosts
    then
      renderHostConfig.deploymentHost
    else if builtins.hasAttr hostname realizationNodes
      && builtins.isAttrs realizationNodes.${hostname}
      && realizationNodes.${hostname} ? host
      && builtins.isString realizationNodes.${hostname}.host
      && builtins.hasAttr realizationNodes.${hostname}.host deploymentHosts
    then
      realizationNodes.${hostname}.host
    else if builtins.hasAttr hostname deploymentHosts then
      hostname
    else if builtins.length deploymentHostNames == 1 then
      builtins.head deploymentHostNames
    else
      throw ''
        host-network/network.nix: could not resolve deployment host for '${hostname}'

        known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';

  hostConfig = deploymentHosts.${deploymentHostName};

  uplinks =
    if hostConfig ? uplinks && builtins.isAttrs hostConfig.uplinks then
      hostConfig.uplinks
    else
      throw "host-network/network.nix: inventory.deployment.hosts.${deploymentHostName}.uplinks missing";

  uplinkNames = sortedAttrNames uplinks;

  localRealizationNode =
    if builtins.hasAttr hostname realizationNodes && builtins.isAttrs realizationNodes.${hostname} then
      realizationNodes.${hostname}
    else
      null;

  hostTransitBridges =
    if hostConfig ? transitBridges && builtins.isAttrs hostConfig.transitBridges then
      hostConfig.transitBridges
    else
      { };

  parseTransitVlan =
    transitName:
      if lib.hasPrefix "tr" transitName then
        builtins.fromJSON (
          builtins.substring
            2
            (builtins.stringLength transitName - 2)
            transitName
        )
      else
        throw "host-network/network.nix: cannot derive transit vlan from bridge name '${transitName}'";

  localTransitBridgeNames =
    if localRealizationNode != null
      && localRealizationNode ? ports
      && builtins.isAttrs localRealizationNode.ports
    then
      lib.unique (
        lib.filter
          (name: name != null)
          (
            map
              (
                portName:
                let
                  port = localRealizationNode.ports.${portName};
                  attach = port.attach or { };
                in
                if builtins.isAttrs attach
                  && (attach.kind or null) == "bridge"
                  && attach ? bridge
                  && builtins.isString attach.bridge
                then
                  attach.bridge
                else
                  null
              )
              (sortedAttrNames localRealizationNode.ports)
          )
      )
    else
      [ ];

  selectedTransitBridgeNames =
    if localTransitBridgeNames != [ ] then
      localTransitBridgeNames
    else
      sortedAttrNames hostTransitBridges;

  transitBridges =
    builtins.listToAttrs (
      map
        (
          transitName:
          {
            name = transitName;
            value =
              if builtins.hasAttr transitName hostTransitBridges then
                hostTransitBridges.${transitName}
              else
                {
                  name = transitName;
                  vlan = parseTransitVlan transitName;
                };
          }
        )
        selectedTransitBridgeNames
    );

  transitNames = sortedAttrNames transitBridges;

  transitParentUplinkNames =
    lib.unique (
      lib.filter
        (name: name != null)
        (
          map
            (
              transitName:
              let
                transit = transitBridges.${transitName};
              in
              if transit ? parentUplink && builtins.isString transit.parentUplink then
                transit.parentUplink
              else
                null
            )
            transitNames
        )
    );

  trunkUplinkName =
    if builtins.length transitParentUplinkNames == 1 then
      builtins.head transitParentUplinkNames
    else if uplinks ? fabric && builtins.isAttrs uplinks.fabric then
      "fabric"
    else if uplinks ? trunk && builtins.isAttrs uplinks.trunk then
      "trunk"
    else if builtins.length uplinkNames == 1 then
      builtins.head uplinkNames
    else
      throw ''
        host-network/network.nix: could not resolve fabric trunk uplink for '${hostname}'

        uplinks:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ uplinkNames)}

        transit parent uplinks:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ transitParentUplinkNames)}
      '';

  trunkUplink =
    if builtins.hasAttr trunkUplinkName uplinks then
      uplinks.${trunkUplinkName}
    else
      throw "host-network/network.nix: missing uplink '${trunkUplinkName}'";

  parentIf =
    if trunkUplink ? parent && trunkUplink.parent != "" then
      trunkUplink.parent
    else
      throw "host-network/network.nix: missing parent on uplink '${trunkUplinkName}'";

  trunkBridgeName =
    if trunkUplink ? bridge && trunkUplink.bridge != "" then
      trunkUplink.bridge
    else
      "br-fabric";

  transitVlans =
    lib.sort builtins.lessThan (
      lib.unique (
        map
          (
            transitName:
            let
              transit = transitBridges.${transitName};
            in
            if transit ? vlan then
              transit.vlan
            else
              parseTransitVlan transitName
          )
          transitNames
      )
    );

  transitBridgeName = vlan: "tr${toString vlan}";
  trunkVlanIfName = vlan: "${trunkBridgeName}.${toString vlan}";
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs =
    {
      "10-${trunkBridgeName}" = {
        netdevConfig = {
          Name = trunkBridgeName;
          Kind = "bridge";
        };
      };
    }
    // builtins.listToAttrs (
      map
        (
          vlan:
          {
            name = "11-${trunkVlanIfName vlan}";
            value = {
              netdevConfig = {
                Name = trunkVlanIfName vlan;
                Kind = "vlan";
              };
              vlanConfig.Id = vlan;
            };
          }
        )
        transitVlans
    )
    // builtins.listToAttrs (
      map
        (
          vlan:
          {
            name = "20-${transitBridgeName vlan}";
            value = {
              netdevConfig = {
                Name = transitBridgeName vlan;
                Kind = "bridge";
              };
            };
          }
        )
        transitVlans
    );

  systemd.network.networks =
    {
      "05-${parentIf}" = {
        matchConfig.Name = parentIf;
        networkConfig = {
          Bridge = trunkBridgeName;
          DHCP = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
      };

      "06-${trunkBridgeName}" = {
        matchConfig.Name = trunkBridgeName;
        networkConfig = {
          VLAN = map trunkVlanIfName transitVlans;
          ConfigureWithoutCarrier = true;
        };
      };
    }
    // builtins.listToAttrs (
      lib.concatMap
        (
          vlan:
          [
            {
              name = "30-${trunkVlanIfName vlan}";
              value = {
                matchConfig.Name = trunkVlanIfName vlan;
                networkConfig = {
                  Bridge = transitBridgeName vlan;
                  DHCP = "no";
                  IPv6AcceptRA = false;
                  ConfigureWithoutCarrier = true;
                };
              };
            }
            {
              name = "31-${transitBridgeName vlan}";
              value = {
                matchConfig.Name = transitBridgeName vlan;
                networkConfig = {
                  ConfigureWithoutCarrier = true;
                };
              };
            }
          ]
        )
        transitVlans
    );
}
