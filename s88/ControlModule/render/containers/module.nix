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

  defaultRouteCandidates =
    let
      routeEntries = lib.concatMap (
        ifaceName:
        let
          iface = renderedModel.interfaces.${ifaceName};
          containerInterfaceName =
            if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
              iface.containerInterfaceName
            else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
              iface.hostInterfaceName
            else if iface ? interfaceName && builtins.isString iface.interfaceName then
              iface.interfaceName
            else if iface ? ifName && builtins.isString iface.ifName then
              iface.ifName
            else
              ifaceName;
          routes = if iface ? routes && builtins.isList iface.routes then iface.routes else [ ];
        in
        map (
          route:
          let
            family =
              if (route.dst or null) == "0.0.0.0/0" && builtins.isString (route.via4 or null) then
                4
              else if (route.dst or null) == "::/0" && builtins.isString (route.via6 or null) then
                6
              else
                null;
            gateway =
              if family == 4 then
                route.via4
              else if family == 6 then
                route.via6
              else
                null;
          in
          if family == null || gateway == null then
            null
          else
            {
              inherit family gateway containerInterfaceName;
              metric = if route ? metric && builtins.isInt route.metric then route.metric else 1024;
            }
        ) routes
      ) (lib.sort builtins.lessThan (builtins.attrNames (renderedModel.interfaces or { })));

      compareCandidates =
        left: right:
        if left.family < right.family then
          true
        else if left.family > right.family then
          false
        else if left.metric < right.metric then
          true
        else if left.metric > right.metric then
          false
        else if left.containerInterfaceName < right.containerInterfaceName then
          true
        else if left.containerInterfaceName > right.containerInterfaceName then
          false
        else
          left.gateway < right.gateway;
    in
    builtins.sort compareCandidates (lib.filter (entry: entry != null) routeEntries);

  needsDefaultRouteFailover = builtins.length defaultRouteCandidates > 1;

  defaultRouteFailoverScript =
    let
      candidateLines = map (
        candidate:
        "${toString candidate.family}|${toString candidate.metric}|${candidate.containerInterfaceName}|${candidate.gateway}"
      ) defaultRouteCandidates;
    in
    pkgs.writeShellScript "s88-default-route-failover" ''
      set -eu

      candidates='${builtins.concatStringsSep "\n" candidateLines}'

      interface_up() {
        local ifname="$1"
        ${pkgs.iproute2}/bin/ip link show dev "$ifname" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "LOWER_UP"
      }

      probe_gateway() {
        local family="$1"
        local ifname="$2"
        local gateway="$3"

        if ! interface_up "$ifname"; then
          return 1
        fi

        if [ "$family" = "4" ]; then
          ${pkgs.iputils}/bin/ping -n -c1 -W1 -I "$ifname" "$gateway" >/dev/null 2>&1
        else
          ${pkgs.iputils}/bin/ping -6 -n -c1 -W1 -I "$ifname" "$gateway" >/dev/null 2>&1
        fi
      }

      reconcile_family() {
        local family="$1"
        local best_line=""

        while IFS='|' read -r cand_family cand_metric cand_if cand_gw; do
          [ -n "$cand_family" ] || continue
          [ "$cand_family" = "$family" ] || continue

          if probe_gateway "$cand_family" "$cand_if" "$cand_gw"; then
            best_line="$cand_family|$cand_metric|$cand_if|$cand_gw"
            break
          fi
        done <<EOF
      $candidates
      EOF

        while IFS='|' read -r cand_family cand_metric cand_if cand_gw; do
          [ -n "$cand_family" ] || continue
          [ "$cand_family" = "$family" ] || continue

          if [ "$best_line" = "$cand_family|$cand_metric|$cand_if|$cand_gw" ]; then
            if [ "$family" = "4" ]; then
              ${pkgs.iproute2}/bin/ip route replace default via "$cand_gw" dev "$cand_if" metric "$cand_metric" onlink
            else
              ${pkgs.iproute2}/bin/ip -6 route replace default via "$cand_gw" dev "$cand_if" metric "$cand_metric" onlink
            fi
          else
            if [ "$family" = "4" ]; then
              ${pkgs.iproute2}/bin/ip route del default via "$cand_gw" dev "$cand_if" >/dev/null 2>&1 || true
            else
              ${pkgs.iproute2}/bin/ip -6 route del default via "$cand_gw" dev "$cand_if" >/dev/null 2>&1 || true
            fi
          fi
        done <<EOF
      $candidates
      EOF
      }

      while true; do
        reconcile_family 4
        reconcile_family 6
        sleep 2
      done
    '';

  defaultRouteFailoverService = lib.optionalAttrs needsDefaultRouteFailover {
    systemd.services.s88-default-route-failover = {
      description = "Keep a live default route selected for multi-uplink containers";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-networkd.service" ];
      wants = [ "systemd-networkd.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 2;
      };
      script = "exec ${defaultRouteFailoverScript}";
    };
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

    accessServices
    dnsServices
    bgpServices
    defaultRouteFailoverService

    (lib.optionalAttrs firewallArg.enable {
      networking.nftables.enable = true;
      networking.nftables.ruleset = firewallArg.ruleset;
    })
  ];
}
