{
  lib,
  pkgs,
  hostName,
  controlPlane,
  ...
}:

let
  cpmRoot =
    if builtins.isAttrs (controlPlane.control_plane_model or null) then
      controlPlane.control_plane_model
    else if builtins.isAttrs controlPlane then
      controlPlane
    else
      { };
  data = if builtins.isAttrs (cpmRoot.data or null) then cpmRoot.data else { };
  runtimeTargets = lib.concatMap (
    enterprise:
    lib.concatMap (
      site:
      if builtins.isAttrs (site.runtimeTargets or null) then
        builtins.attrValues site.runtimeTargets
      else
        [ ]
    ) (lib.filter builtins.isAttrs (builtins.attrValues enterprise))
  ) (lib.filter builtins.isAttrs (builtins.attrValues data));
  hostAuthorities = lib.filter (
    target:
    (target.placement.host or null) == hostName
    && builtins.isAttrs (target.services.dns.validationAuthority or null)
  ) runtimeTargets;
  authorityCount = builtins.length hostAuthorities;
  authority =
    if authorityCount == 1 then
      (builtins.head hostAuthorities).services.dns.validationAuthority
    else
      null;
  bridge = if authority == null then null else authority.provider.bridge;
  forwardingGateway =
    let
      fg = if authority == null then { } else (authority.forwardingGateway or { });
    in
    if (fg.enable or false) && builtins.isString (fg.upstreamInterface or null) then
      {
        enable = true;
        upstream = fg.upstreamInterface;
        ipv4Prefix = authority.provider.ipv4.address;
        ipv6Prefix = authority.provider.ipv6.prefix;
      }
    else
      { enable = false; };
  rootAddresses = if authority == null then [ ] else authority.root.ipv4 ++ authority.root.ipv6;
  delegationAddresses =
    if authority == null then [ ] else authority.delegation.ipv4 ++ authority.delegation.ipv6;
  listenerAddresses = rootAddresses ++ delegationAddresses;
  rootZone =
    if authority == null then
      ""
    else
      ''
        $ORIGIN .
        $TTL 60
        @ IN SOA ${authority.root.nameServer} hostmaster.${authority.delegation.zone} 1 60 60 60 60
        @ IN NS ${authority.root.nameServer}
        ${authority.root.nameServer} IN A ${builtins.head authority.root.ipv4}
        ${authority.root.nameServer} IN AAAA ${builtins.head authority.root.ipv6}
        ${authority.delegation.zone} IN NS ${authority.delegation.nameServer}
        ${authority.delegation.nameServer} IN A ${builtins.head authority.delegation.ipv4}
        ${authority.delegation.nameServer} IN AAAA ${builtins.head authority.delegation.ipv6}
      '';
  delegationZone =
    if authority == null then
      ""
    else
      ''
        $ORIGIN ${authority.delegation.zone}
        $TTL 60
        @ IN SOA ${authority.delegation.nameServer} hostmaster.${authority.delegation.zone} 1 60 60 60 60
        @ IN NS ${authority.delegation.nameServer}
        ${authority.delegation.nameServer} IN A ${builtins.head authority.delegation.ipv4}
        ${authority.delegation.nameServer} IN AAAA ${builtins.head authority.delegation.ipv6}
        ${authority.terminal.name} IN A ${builtins.head authority.terminal.ipv4}
        ${authority.terminal.name} IN AAAA ${builtins.head authority.terminal.ipv6}
      '';
  rootZoneFile = if authority == null then null else pkgs.writeText "controlled-root.zone" rootZone;
  delegationZoneFile =
    if authority == null then null else pkgs.writeText "controlled-delegation.zone" delegationZone;
in
if authorityCount == 0 then
  { }
else if authorityCount != 1 then
  throw "network-renderer-nixos DNS_VALIDATION_AUTHORITY_EXTERNAL: host must own exactly one controlled authority fixture; address material is intentionally omitted"
else
  {
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

    systemd.network.networks."30-${bridge}" = {
      address = [
        authority.provider.ipv4.address
        authority.provider.ipv6.address
      ]
      ++ map (address: "${address}/32") (authority.root.ipv4 ++ authority.delegation.ipv4)
      ++ map (address: "${address}/128") (authority.root.ipv6 ++ authority.delegation.ipv6);

      networkConfig.LinkLocalAddressing = lib.mkForce "ipv6";
    };

    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        interface = bridge;
        "bind-interfaces" = true;
        port = 0;
        "dhcp-authoritative" = true;
        "enable-ra" = true;
        "dhcp-range" = [
          "${authority.provider.ipv4.rangeStart},${authority.provider.ipv4.rangeEnd},${authority.provider.ipv4.leaseTime}"
          "::,constructor:${bridge},ra-only,slaac,64,${authority.provider.ipv6.leaseTime}"
        ];
        "dhcp-option" = [
          "option:router,${authority.provider.ipv4.router}"
        ];
      };
    };

    services.knot = {
      enable = true;
      settings = {
        server.listen = map (address: "${address}@53") listenerAddresses;
        zone = {
          ".".file = "${rootZoneFile}";
          "${authority.delegation.zone}".file = "${delegationZoneFile}";
        };
      };
    };

    networking.firewall.interfaces.${bridge} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [
        53
        67
      ];
    };
  }
  // lib.optionalAttrs forwardingGateway.enable {

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    networking.nftables.enable = true;
    networking.nftables.ruleset = ''
      table inet gateway_nat {
        chain forward {
          type filter hook forward priority filter; policy accept;
          iifname "${bridge}" oifname "${forwardingGateway.upstream}" accept
          iifname "${forwardingGateway.upstream}" oifname "${bridge}" ct state established,related accept
        }
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "${forwardingGateway.upstream}" ip saddr ${forwardingGateway.ipv4Prefix} masquerade
          oifname "${forwardingGateway.upstream}" ip6 saddr ${forwardingGateway.ipv6Prefix} masquerade
        }
      }
    '';
  }
