{
  lib,
  pkgs,
  renderedModel,
  forwardingIntent ? { },
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

    forwarder4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) forwarders;
    forwarder6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) forwarders;
    hasMixedForwarders = forwarder4 != [ ] && forwarder6 != [ ];
    deniedResolverCidrs =
      if dnsService ? deniedResolverCidrs && builtins.isList dnsService.deniedResolverCidrs then
        lib.unique (lib.filter builtins.isString dnsService.deniedResolverCidrs)
      else
        [ ];
    deniedResolverCidrs4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) deniedResolverCidrs;
    deniedResolverCidrs6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) deniedResolverCidrs;

    localZones =
      if dnsService ? localZones && builtins.isList dnsService.localZones then
        lib.filter (
          zone: builtins.isAttrs zone && builtins.isString (zone.name or null) && zone.name != ""
        ) dnsService.localZones
      else
        [ ];

    localRecords =
      if dnsService ? localRecords && builtins.isList dnsService.localRecords then
        lib.filter (
          record: builtins.isAttrs record && builtins.isString (record.name or null) && record.name != ""
        ) dnsService.localRecords
      else
        [ ];

    outgoingInterfaces =
      if dnsService ? outgoingInterfaces && builtins.isList dnsService.outgoingInterfaces then
        lib.unique (lib.filter builtins.isString dnsService.outgoingInterfaces)
      else
        [ ];
    dnsEgressSources =
      if outgoingInterfaces != [ ] then
        outgoingInterfaces
      else
        listenAddresses;
    dnsEgressSources4 = lib.filter (value: builtins.isString value && lib.hasInfix "." value) dnsEgressSources;
    dnsEgressSources6 = lib.filter (value: builtins.isString value && lib.hasInfix ":" value) dnsEgressSources;

    nftString = value:
      ''"${lib.replaceStrings [ ''\'' "\\" ''"'' ] [ ''\\'' "\\\\" ''\"'' ] (toString value)}"'';

    interfaces =
      if renderedModel ? interfaces && builtins.isAttrs renderedModel.interfaces then
        renderedModel.interfaces
      else
        { };

    explicitDnsForwardPairs =
      lib.filter
        (pair:
          builtins.isAttrs pair
          && (pair.action or "accept") == "accept"
          && (pair.trafficType or null) == "dns"
          && builtins.isList (pair."in" or null))
        (forwardingIntent.normalizedExplicitForwardPairs or [ ]);

    hasExplicitDnsAllowFrom =
      ifName:
      builtins.any (pair: builtins.elem ifName (pair."in" or [ ])) explicitDnsForwardPairs;

    directEgressBlockedTenants =
      if dnsService ? directEgressBlockedTenants && builtins.isList dnsService.directEgressBlockedTenants then
        lib.filter builtins.isString dnsService.directEgressBlockedTenants
      else
        null;

    shouldBlockInterface =
      ifName: iface:
      let
        sourceKind = iface.sourceKind or "";
        tenant = iface.tenant or null;
      in
      if sourceKind == "wan" || sourceKind == "overlay" then
        false
      else if sourceKind == "tenant" && directEgressBlockedTenants != null then
        builtins.isString tenant && builtins.elem tenant directEgressBlockedTenants
      else
        true;

    ingressInterfaceNames =
      if dnsService.blockDirectEgress or false then
        lib.unique (
          lib.filter (name: name != "") (
            map (
              ifName:
              let
                iface = interfaces.${ifName} or { };
              in
              if !(shouldBlockInterface ifName iface) then
                ""
              else if iface ? renderedIfName && builtins.isString iface.renderedIfName && iface.renderedIfName != "" then
                if hasExplicitDnsAllowFrom iface.renderedIfName then "" else iface.renderedIfName
              else if iface ? interfaceName && builtins.isString iface.interfaceName && iface.interfaceName != "" then
                if hasExplicitDnsAllowFrom iface.interfaceName then "" else iface.interfaceName
              else if hasExplicitDnsAllowFrom ifName then
                ""
              else
                ifName
            ) (builtins.attrNames interfaces)
          )
        )
      else
        [ ];

    accessControl = map (cidr: "${cidr} allow") allowFrom;

    localZoneSettings = map (zone: "${zone.name} ${zone.type or "static"}") localZones;

    localDataSettings = lib.concatMap (
      record:
      let
        name = record.name;
        a = if builtins.isList (record.a or null) then lib.filter builtins.isString record.a else [ ];
        aaaa =
          if builtins.isList (record.aaaa or null) then lib.filter builtins.isString record.aaaa else [ ];
      in
      (map (addr: "\"${name} IN A ${addr}\"") a) ++ (map (addr: "\"${name} IN AAAA ${addr}\"") aaaa)
    ) localRecords;

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
      ) listen6)
      ++ (lib.concatMap (
        ifName:
        [
          "${pkgs.nftables}/bin/nft add rule inet router forward iifname ${nftString ifName} udp dport 53 drop comment \"deny-direct-dns-egress\""
          "${pkgs.nftables}/bin/nft add rule inet router forward iifname ${nftString ifName} tcp dport 53 drop comment \"deny-direct-dns-egress\""
        ]
      ) ingressInterfaceNames);
    dnsOutputRules =
      (lib.concatMap (
        source:
        map (
          forwarder:
          "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} ip daddr ${forwarder} udp dport 53 accept comment \"allow-dns-service-egress\""
        ) forwarder4
      ) dnsEgressSources4)
      ++ (lib.concatMap (
        source:
        map (
          forwarder:
          "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} ip daddr ${forwarder} tcp dport 53 accept comment \"allow-dns-service-egress\""
        ) forwarder4
      ) dnsEgressSources4)
      ++ (lib.concatMap (
        source:
        map (
          forwarder:
          "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} ip6 daddr ${forwarder} udp dport 53 accept comment \"allow-dns-service-egress\""
        ) forwarder6
      ) dnsEgressSources6)
      ++ (lib.concatMap (
        source:
        map (
          forwarder:
          "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} ip6 daddr ${forwarder} tcp dport 53 accept comment \"allow-dns-service-egress\""
        ) forwarder6
      ) dnsEgressSources6)
      ++ (lib.concatMap (
        cidr:
        [
          "${pkgs.nftables}/bin/nft add rule inet router output ip daddr ${cidr} udp dport 53 drop comment \"deny-public-dns-output-leak\""
          "${pkgs.nftables}/bin/nft add rule inet router output ip daddr ${cidr} tcp dport 53 drop comment \"deny-public-dns-output-leak\""
        ]
      ) deniedResolverCidrs4)
      ++ (lib.concatMap (
        cidr:
        [
          "${pkgs.nftables}/bin/nft add rule inet router output ip6 daddr ${cidr} udp dport 53 drop comment \"deny-public-dns-output-leak\""
          "${pkgs.nftables}/bin/nft add rule inet router output ip6 daddr ${cidr} tcp dport 53 drop comment \"deny-public-dns-output-leak\""
        ]
      ) deniedResolverCidrs6);
    dnsOutputScript =
      if dnsOutputRules != [ ] then
        lib.concatStringsSep "\n          " dnsOutputRules
      else
        ":";
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
          "infra-host-ttl" = 1;
          "infra-lame-ttl" = 1;
        }
        // lib.optionalAttrs hasMixedForwarders {
          "prefer-ip4" = true;
        }
        // lib.optionalAttrs (localZoneSettings != [ ]) {
          "local-zone" = localZoneSettings;
        }
        // lib.optionalAttrs (localDataSettings != [ ]) {
          "local-data" = localDataSettings;
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

    systemd.services.unbound = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
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

        if ! ${pkgs.nftables}/bin/nft list ruleset | grep -q 'allow-dns-service-egress'; then
          ${dnsOutputScript}
        fi
      '';
    };
  }
