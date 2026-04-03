{
  lib,
  containerName,
  renderedModel,
  firewallArg,
  uplinks,
  wanUplinkName,
}:

let
  roleName = renderedModel.roleName or null;

  profilePath = if renderedModel ? profilePath then renderedModel.profilePath else null;

  resolvedHostName =
    if renderedModel ? unitName && builtins.isString renderedModel.unitName then
      renderedModel.unitName
    else
      containerName;

  commonRouterConfig =
    {
      lib,
      pkgs,
      ...
    }:
    {
      boot.isContainer = true;

      networking.useNetworkd = true;
      systemd.network.enable = true;
      networking.useDHCP = false;
      networking.networkmanager.enable = false;
      networking.useHostResolvConf = lib.mkForce false;

      services.resolved.enable = lib.mkForce false;
      networking.firewall.enable = lib.mkForce false;

      environment.systemPackages = with pkgs; [
        gron
        traceroute
        tcpdump
        nftables
        dnsutils
        iproute2
        iputils
      ];

      system.stateVersion = "25.11";
    };
in
{
  lib,
  pkgs,
  ...
}:
let
  containerNetworks = import ../container-networks.nix {
    inherit
      lib
      uplinks
      wanUplinkName
      ;
    containerModel = renderedModel;
  };

  accessServices =
    if roleName == "access" then
      import ../../access/render/default.nix {
        inherit lib pkgs;
        containerModel = renderedModel;
      }
    else
      { };
in
{
  imports = lib.optionals (profilePath != null) [ profilePath ];

  config = lib.mkMerge [
    (commonRouterConfig { inherit lib pkgs; })

    {
      networking.hostName = resolvedHostName;
      systemd.network.networks = containerNetworks;
    }

    accessServices

    (lib.optionalAttrs firewallArg.enable {
      networking.nftables.enable = true;
      networking.nftables.ruleset = firewallArg.ruleset;
    })
  ];
}
