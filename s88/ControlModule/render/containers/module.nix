{
  lib,
  containerName,
  renderedModel,
  firewallArg,
  alarmModel,
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

  warningMessages =
    if alarmModel ? warningMessages && builtins.isList alarmModel.warningMessages then
      lib.unique (lib.filter builtins.isString alarmModel.warningMessages)
    else
      [ ];

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
  containerNetworkRender = import ../container-networks.nix {
    inherit
      lib
      uplinks
      wanUplinkName
      ;
    containerModel = renderedModel;
  };

  containerNetworks = containerNetworkRender.networks;

  containerKernelSysctl = containerNetworkRender.kernelSysctl or { };

  accessServices =
    if roleName == "access" then
      import ../../access/render/default.nix {
        inherit lib pkgs;
        containerModel = renderedModel;
      }
    else
      { };

  dnsServices = import ./dns-services.nix {
    inherit
      lib
      pkgs
      renderedModel
      ;
  };
in
{
  imports = lib.optionals (profilePath != null) [ profilePath ];

  config = lib.mkMerge [
    (commonRouterConfig { inherit lib pkgs; })

    {
      networking.hostName = resolvedHostName;
      systemd.network.networks = containerNetworks;
      boot.kernel.sysctl = containerKernelSysctl;
      warnings = warningMessages;
    }

    accessServices
    dnsServices

    (lib.optionalAttrs firewallArg.enable {
      networking.nftables.enable = true;
      networking.nftables.ruleset = firewallArg.ruleset;
    })
  ];
}
