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
        jq
        ethtool
        lsof
        mtr
        procps
        strace
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
  containerInterfaceRenames = lib.filter (entry: entry != null) (
    map (
      iface:
      let
        initialInterfaceName =
          if iface ? hostVethName && builtins.isString iface.hostVethName then iface.hostVethName else null;
        finalInterfaceName =
          if
            iface ? containerInterfaceName
            && builtins.isString iface.containerInterfaceName
            && iface.containerInterfaceName != ""
          then
            iface.containerInterfaceName
          else
            null;
      in
      if
        initialInterfaceName != null
        && finalInterfaceName != null
        && initialInterfaceName != finalInterfaceName
      then
        {
          inherit initialInterfaceName finalInterfaceName;
        }
      else
        null
    ) (builtins.attrValues (renderedModel.interfaces or { }))
  );
  containerInterfaceRenameService =
    if containerInterfaceRenames == [ ] then
      { }
    else
      {
        s88-rename-interfaces = {
          description = "Rename rendered container interfaces to semantic names";
          wantedBy = [ "multi-user.target" ];
          requiredBy = [ "systemd-networkd.service" ];
          before = [
            "systemd-networkd.service"
            "multi-user.target"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script =
            let
              renameCommands = map (rename: ''
                for _ in $(seq 1 30); do
                  if ${pkgs.iproute2}/bin/ip link show dev ${rename.finalInterfaceName} >/dev/null 2>&1; then
                    break
                  fi
                  if ${pkgs.iproute2}/bin/ip link show dev ${rename.initialInterfaceName} >/dev/null 2>&1; then
                    ${pkgs.iproute2}/bin/ip link set dev ${rename.initialInterfaceName} down || true
                    ${pkgs.iproute2}/bin/ip link set dev ${rename.initialInterfaceName} name ${rename.finalInterfaceName}
                    ${pkgs.iproute2}/bin/ip link set dev ${rename.finalInterfaceName} up || true
                    break
                  fi
                  sleep 1
                done
              '') containerInterfaceRenames;
            in
            lib.concatStringsSep "\n" renameCommands;
        };
      };
  networkManagerWanInterfaces =
    if
      renderedModel ? networkManagerWanInterfaces
      && builtins.isList renderedModel.networkManagerWanInterfaces
    then
      lib.filter builtins.isString renderedModel.networkManagerWanInterfaces
    else
      [ ];

  networkdManagedInterfaces =
    lib.filter
      (
        interfaceName:
        builtins.isString interfaceName && !(builtins.elem interfaceName networkManagerWanInterfaces)
      )
      (
        map (
          iface:
          if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
            iface.containerInterfaceName
          else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
            iface.hostInterfaceName
          else if iface ? interfaceName && builtins.isString iface.interfaceName then
            iface.interfaceName
          else if iface ? ifName && builtins.isString iface.ifName then
            iface.ifName
          else
            null
        ) (builtins.attrValues (renderedModel.interfaces or { }))
      );

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

  networkManagerConnections = builtins.listToAttrs (
    map (interfaceName: {
      name = "NetworkManager/system-connections/s88-${interfaceName}.nmconnection";
      value = {
        mode = "0600";
        text = ''
          [connection]
          id=s88-${interfaceName}
          type=ethernet
          interface-name=${interfaceName}
          autoconnect=true

          [ethernet]

          [ipv4]
          method=auto

          [ipv6]
          method=auto
        '';
      };
    }) networkManagerWanInterfaces
  );

  networkManagerActivationServices = builtins.listToAttrs (
    map (interfaceName: {
      name = "s88-networkmanager-${interfaceName}";
      value = {
        description = "Activate NetworkManager WAN profile on ${interfaceName}";
        wantedBy = [ "multi-user.target" ];
        after = [ "NetworkManager.service" ];
        wants = [ "NetworkManager.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [ pkgs.networkmanager ];
        script = ''
          nmcli connection reload
          nmcli connection up s88-${interfaceName} ifname ${interfaceName}
        '';
      };
    }) networkManagerWanInterfaces
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

  bgpServices = import ./bgp-services.nix {
    inherit
      lib
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

    (lib.optionalAttrs (networkManagerWanInterfaces != [ ]) {
      networking.networkmanager.enable = lib.mkForce true;
      networking.networkmanager.unmanaged = map (
        interfaceName: "interface-name:${interfaceName}"
      ) networkdManagedInterfaces;
      environment.etc = networkManagerConnections;
      systemd.services = networkManagerActivationServices;
    })

    (lib.optionalAttrs (containerIpv6AcceptRAInterfaces != [ ]) {
      boot.kernel.sysctl = {
        "net.ipv6.conf.all.accept_ra" = 2;
        "net.ipv6.conf.default.accept_ra" = 2;
      };

      systemd.services = ipv6AcceptRAServices;
    })

    (lib.optionalAttrs (containerInterfaceRenameService != { }) {
      systemd.services = containerInterfaceRenameService;
    })

    accessServices
    dnsServices
    bgpServices
    (lib.optionalAttrs firewallArg.enable {
      networking.nftables.enable = true;
      networking.nftables.ruleset = firewallArg.ruleset;
    })
  ];
}
