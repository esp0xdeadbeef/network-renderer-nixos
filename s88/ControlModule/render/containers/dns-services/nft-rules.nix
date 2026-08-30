{
  lib,
  pkgs,
  facts,
}:

let
  nftString =
    value: ''"${lib.replaceStrings [ ''\'' "\\" ''"'' ] [ ''\\'' "\\\\" ''\"'' ] (toString value)}"'';

  inherit (facts)
    listen4
    listen6
    ingressInterfaceNames
    forwarder4
    forwarder6
    registeredUpstreams4
    registeredUpstreams6
    dnsEgressSources4
    dnsEgressSources6
    dnsServiceForwardEgressRules
    dnsEgressPolicy
    strictEgress
    ;

  dnsServiceForwardEgressRule =
    proto: rule:
    let
      source = rule.source;
      sourceExpr =
        if (source.family or 4) == 6 then "ip6 saddr ${source.prefix}" else "ip saddr ${source.prefix}";
    in
    "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString rule.inInterface} oifname ${nftString rule.outInterface} ${sourceExpr} ${proto} dport 53 accept comment \"allow-dns-service-forward-egress\"";

  dnsServiceForwardEgressNftRules = lib.concatMap (rule: [
    (dnsServiceForwardEgressRule "udp" rule)
    (dnsServiceForwardEgressRule "tcp" rule)
  ]) dnsServiceForwardEgressRules;

  dnsUpstreamSetDefinitions =
    (lib.optional (registeredUpstreams4 != [ ])
      "${pkgs.nftables}/bin/nft list set inet router s88_dns_upstream4 >/dev/null 2>&1 || ${pkgs.nftables}/bin/nft add set inet router s88_dns_upstream4 { type ipv4_addr; }"
    )
    ++ (lib.optional (registeredUpstreams6 != [ ])
      "${pkgs.nftables}/bin/nft list set inet router s88_dns_upstream6 >/dev/null 2>&1 || ${pkgs.nftables}/bin/nft add set inet router s88_dns_upstream6 { type ipv6_addr; }"
    );

  registeredUpstreamAllowRules =
    (lib.optionals (registeredUpstreams4 != [ ]) (
      lib.concatMap (source: [
        "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} ip daddr @s88_dns_upstream4 udp dport 53 accept comment \"allow-dns-service-egress-registered\""
        "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} ip daddr @s88_dns_upstream4 tcp dport 53 accept comment \"allow-dns-service-egress-registered\""
      ]) dnsEgressSources4
    ))
    ++ (lib.optionals (registeredUpstreams6 != [ ]) (
      lib.concatMap (source: [
        "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} ip6 daddr @s88_dns_upstream6 udp dport 53 accept comment \"allow-dns-service-egress-registered\""
        "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} ip6 daddr @s88_dns_upstream6 tcp dport 53 accept comment \"allow-dns-service-egress-registered\""
      ]) dnsEgressSources6
    ));

  dnsServiceStrictEgressDefaultDropRules =
    if strictEgress then
      (lib.concatMap (source: [
        "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} udp dport 53 drop comment \"deny-dns-service-egress-default\""
        "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} tcp dport 53 drop comment \"deny-dns-service-egress-default\""
      ]) dnsEgressSources4)
      ++ (lib.concatMap (source: [
        "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} udp dport 53 drop comment \"deny-dns-service-egress-default\""
        "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} tcp dport 53 drop comment \"deny-dns-service-egress-default\""
      ]) dnsEgressSources6)
    else
      [ ];

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
    ++ (lib.concatMap (ifName: [
      "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} udp dport 53 drop comment \"deny-direct-dns-egress\""
      "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} tcp dport 53 drop comment \"deny-direct-dns-egress\""
    ]) ingressInterfaceNames)
    ++ dnsServiceForwardEgressNftRules;

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
    ++ registeredUpstreamAllowRules
    ++ dnsServiceStrictEgressDefaultDropRules;

  dnsPolicyRoutingScript =
    if dnsEgressPolicy == null then
      ":"
    else
      let
        mark = toString dnsEgressPolicy.firewallMark;
      in
      ''
        if ${pkgs.nftables}/bin/nft list table inet s88_dns_egress >/dev/null 2>&1; then
          ${pkgs.nftables}/bin/nft delete table inet s88_dns_egress
        fi
        ${pkgs.nftables}/bin/nft add table inet s88_dns_egress
        ${pkgs.nftables}/bin/nft 'add chain inet s88_dns_egress output { type route hook output priority mangle; policy accept; }'





        ${pkgs.nftables}/bin/nft add rule inet s88_dns_egress output meta skuid "unbound" udp dport 53 meta mark set ${mark} comment "select-modeled-dns-egress"
        ${pkgs.nftables}/bin/nft add rule inet s88_dns_egress output meta skuid "unbound" tcp dport 53 meta mark set ${mark} comment "select-modeled-dns-egress"
      '';
in
{
  inherit nftRules;
  inherit dnsPolicyRoutingScript;
  inherit dnsUpstreamSetDefinitions;
  dnsOutputScript =
    if dnsOutputRules != [ ] then lib.concatStringsSep "\n          " dnsOutputRules else ":";
}
