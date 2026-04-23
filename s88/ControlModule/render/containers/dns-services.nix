{
  lib,
  pkgs,
  renderedModel,
}:

let
  runtimeTarget =
    if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
      renderedModel.runtimeTarget
    else
      { };

  dnsService =
    if
      runtimeTarget ? services && builtins.isAttrs runtimeTarget.services && runtimeTarget.services ? dns
    then
      runtimeTarget.services.dns
    else
      null;
in
if !(builtins.isAttrs dnsService) then
  { }
else
  let
    listenAddresses = lib.unique (
      [
        "127.0.0.1"
        "::1"
      ]
      ++ (
        if dnsService ? listen && builtins.isList dnsService.listen then
          lib.filter builtins.isString dnsService.listen
        else
          [ ]
      )
    );

    listen4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) listenAddresses;
    listen6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) listenAddresses;

    allowFrom = lib.unique (
      [
        "127.0.0.0/8"
        "::1/128"
      ]
      ++ (
        if dnsService ? allowFrom && builtins.isList dnsService.allowFrom then
          lib.filter builtins.isString dnsService.allowFrom
        else
          [ ]
      )
    );

    forwarders =
      if dnsService ? forwarders && builtins.isList dnsService.forwarders then
        lib.filter builtins.isString dnsService.forwarders
      else if dnsService ? upstreams && builtins.isList dnsService.upstreams then
        lib.filter builtins.isString dnsService.upstreams
      else
        [ ];

    explicitOutgoingInterfaces =
      if dnsService ? outgoingInterfaces && builtins.isList dnsService.outgoingInterfaces then
        lib.filter builtins.isString dnsService.outgoingInterfaces
      else
        [ ];

    derivedOutgoingInterfaces = lib.filter (addr: addr != "127.0.0.1" && addr != "::1") listenAddresses;

    outgoingInterfaces = lib.unique (
      if explicitOutgoingInterfaces != [ ] then explicitOutgoingInterfaces else derivedOutgoingInterfaces
    );

    tenantInterfaceNames = lib.unique (
      map
        (
          iface:
          if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
            iface.containerInterfaceName
          else if iface ? interfaceName && builtins.isString iface.interfaceName then
            iface.interfaceName
          else
            null
        )
        (
          lib.filter (iface: builtins.isAttrs iface && (iface.sourceKind or null) == "tenant") (
            builtins.attrValues (renderedModel.interfaces or { })
          )
        )
    );

    accessControl = map (cidr: "${cidr} allow") allowFrom;

    nftRules =
      (map (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip daddr ${addr} udp dport 53 accept comment \"allow-dns-service\""
      ) listen4)
      ++ (map (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip daddr ${addr} tcp dport 53 accept comment \"allow-dns-service\""
      ) listen4)
      ++ (map (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip6 daddr ${addr} udp dport 53 accept comment \"allow-dns-service\""
      ) listen6)
      ++ (map (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip6 daddr ${addr} tcp dport 53 accept comment \"allow-dns-service\""
      ) listen6);

    directDnsLeakRules = lib.concatMap (ifName: [
      "${pkgs.nftables}/bin/nft insert rule inet router forward iifname \\\"${ifName}\\\" udp dport 53 drop comment \"deny-direct-dns-egress\""
      "${pkgs.nftables}/bin/nft insert rule inet router forward iifname \\\"${ifName}\\\" tcp dport 53 drop comment \"deny-direct-dns-egress\""
    ]) tenantInterfaceNames;
  in
  {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = listenAddresses;
          "access-control" = accessControl;
          "do-ip4" = true;
          "do-ip6" = true;
        }
        // lib.optionalAttrs (outgoingInterfaces != [ ]) {
          "outgoing-interface" = outgoingInterfaces;
        };
        forward-zone = lib.optional (forwarders != [ ]) {
          name = ".";
          "forward-addr" = forwarders;
        };
      };
    };

    systemd.services.nft-allow-dns-service = {
      description = "Allow DNS to local unbound listeners";
      wantedBy = [ "multi-user.target" ];
      wants = [ "nftables.service" ];
      after = [ "nftables.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        if ! ${pkgs.nftables}/bin/nft list chain inet router input | grep -q 'allow-dns-service'; then
          ${lib.concatStringsSep "\n          " nftRules}
        fi

        if ! ${pkgs.nftables}/bin/nft list chain inet router forward | grep -q 'deny-direct-dns-egress'; then
          ${lib.concatStringsSep "\n          " directDnsLeakRules}
        fi
      '';
    };
  }
