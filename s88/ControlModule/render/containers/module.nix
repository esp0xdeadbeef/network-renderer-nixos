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

  containerIpv6AcceptRAInterfaces = containerNetworkRender.ipv6AcceptRAInterfaces or [ ];

  ipv6AcceptRAServices = builtins.listToAttrs (
    map (interfaceName: {
      name = "s88-ipv6-accept-ra-${interfaceName}";
      value = {
        description = "Enable IPv6 router advertisements on ${interfaceName}";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-networkd.service" ];
        wants = [ "systemd-networkd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          for _ in $(seq 1 30); do
            if [ -e /proc/sys/net/ipv6/conf/${interfaceName}/accept_ra ]; then
              ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.${interfaceName}.accept_ra=2
              ${pkgs.iproute2}/bin/ip link set dev ${interfaceName} down
              sleep 1
              ${pkgs.iproute2}/bin/ip link set dev ${interfaceName} up
              exit 0
            fi
            sleep 1
          done
          echo "interface ${interfaceName} did not appear" >&2
          exit 1
        '';
      };
    }) containerIpv6AcceptRAInterfaces
  );

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
      warnings = warningMessages;
    }

    (lib.optionalAttrs (containerIpv6AcceptRAInterfaces != [ ]) {
      boot.kernel.sysctl = {
        "net.ipv6.conf.all.accept_ra" = 2;
        "net.ipv6.conf.default.accept_ra" = 2;
      };

      systemd.services = ipv6AcceptRAServices;
    })

    accessServices
    dnsServices

    (lib.optionalAttrs firewallArg.enable {
      networking.nftables.enable = true;
      networking.nftables.ruleset = firewallArg.ruleset;
    })
  ];
}
