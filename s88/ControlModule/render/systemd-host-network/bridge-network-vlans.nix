{ lib, common }:

let
  inherit (common) sortedAttrNames bridgeNetworks bridges;

  bridgeNetworkVlanNames =
    lib.filter
      (bridgeName: (bridgeNetworks.${bridgeName}.mode or null) == "vlan")
      (sortedAttrNames bridgeNetworks);

  bridgeNetworkVlanIfNameFor =
    bridgeName:
    let
      bridgeNetwork = bridgeNetworks.${bridgeName};
      parent =
        if bridgeNetwork ? parent && builtins.isString bridgeNetwork.parent then
          bridgeNetwork.parent
        else
          throw ''
            s88/CM/network/render/systemd-host-network.nix: bridgeNetwork '${bridgeName}' mode=vlan requires string parent
          '';
      vlan =
        if bridgeNetwork ? vlan && builtins.isInt bridgeNetwork.vlan then
          bridgeNetwork.vlan
        else
          throw ''
            s88/CM/network/render/systemd-host-network.nix: bridgeNetwork '${bridgeName}' mode=vlan requires integer vlan
          '';
    in
    "${parent}.${toString vlan}";

  bridgeNetworkVlanParentFor =
    bridgeName:
    let bridgeNetwork = bridgeNetworks.${bridgeName};
    in
    if bridgeNetwork ? parent && builtins.isString bridgeNetwork.parent then
      bridgeNetwork.parent
    else
      throw ''
        s88/CM/network/render/systemd-host-network.nix: bridgeNetwork '${bridgeName}' mode=vlan requires string parent
      '';
in
{
  inherit bridgeNetworkVlanNames bridgeNetworkVlanIfNameFor bridgeNetworkVlanParentFor;

  bridgeNetworkVlanNetdevs = builtins.listToAttrs (
    map (
      bridgeName:
      let
        bridgeNetwork = bridgeNetworks.${bridgeName};
        vlanIfName = bridgeNetworkVlanIfNameFor bridgeName;
      in
      {
        name = "13-${vlanIfName}";
        value = {
          netdevConfig = {
            Name = vlanIfName;
            Kind = "vlan";
          };
          vlanConfig.Id = bridgeNetwork.vlan;
        };
      }
    ) bridgeNetworkVlanNames
  );

  bridgeNetworkVlanAttachmentNetworks = builtins.listToAttrs (
    map (
      bridgeName:
      let
        vlanIfName = bridgeNetworkVlanIfNameFor bridgeName;
        renderedBridgeName =
          if builtins.hasAttr bridgeName bridges then
            bridges.${bridgeName}.renderedName
          else
            throw ''
              s88/CM/network/render/systemd-host-network.nix: bridgeNetwork '${bridgeName}' mode=vlan has no rendered bridge
            '';
      in
      {
        name = "22-${vlanIfName}";
        value = {
          matchConfig.Name = vlanIfName;
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = {
            Bridge = renderedBridgeName;
            ConfigureWithoutCarrier = true;
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          };
        };
      }
    ) bridgeNetworkVlanNames
  );
}
