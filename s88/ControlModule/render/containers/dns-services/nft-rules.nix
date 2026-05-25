{ lib, pkgs, facts }:

let
  nftString = value:
    ''"${lib.replaceStrings [ ''\'' "\\" ''"'' ] [ ''\\'' "\\\\" ''\"'' ] (toString value)}"'';

  inherit (facts)
    listen4
    listen6
    ingressInterfaceNames
    forwarder4
    forwarder6
    dnsEgressSources4
    dnsEgressSources6
    deniedResolverCidrs4
    deniedResolverCidrs6
    publicResolverForwardIngressNames
    ;

  publicResolverForwardDropRules =
    ifName:
    (lib.concatMap
      (
        cidr:
        [
          "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} ip daddr ${cidr} udp dport 53 drop comment \"deny-public-dns-forward-leak\""
          "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} ip daddr ${cidr} tcp dport 53 drop comment \"deny-public-dns-forward-leak\""
        ]
      )
      deniedResolverCidrs4)
    ++ (lib.concatMap
      (
        cidr:
        [
          "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} ip6 daddr ${cidr} udp dport 53 drop comment \"deny-public-dns-forward-leak\""
          "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} ip6 daddr ${cidr} tcp dport 53 drop comment \"deny-public-dns-forward-leak\""
        ]
      )
      deniedResolverCidrs6);

  nftRules =
    (map
      (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip daddr ${addr} udp dport 53 accept comment \"allow-dns-service\""
      )
      listen4)
    ++ (map
      (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip daddr ${addr} tcp dport 53 accept comment \"allow-dns-service\""
      )
      listen4)
    ++ (map
      (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip6 daddr ${addr} udp dport 53 accept comment \"allow-dns-service\""
      )
      listen6)
    ++ (map
      (
        addr:
        "${pkgs.nftables}/bin/nft add rule inet router input ip6 daddr ${addr} tcp dport 53 accept comment \"allow-dns-service\""
      )
      listen6)
    ++ (lib.concatMap
      (
        ifName:
        [
          "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} udp dport 53 drop comment \"deny-direct-dns-egress\""
          "${pkgs.nftables}/bin/nft insert rule inet router forward iifname ${nftString ifName} tcp dport 53 drop comment \"deny-direct-dns-egress\""
        ]
      )
      ingressInterfaceNames)
    ++ (lib.concatMap publicResolverForwardDropRules publicResolverForwardIngressNames);

  dnsOutputRules =
    (lib.concatMap
      (source: map (forwarder: "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} ip daddr ${forwarder} udp dport 53 accept comment \"allow-dns-service-egress\"") forwarder4)
      dnsEgressSources4)
    ++ (lib.concatMap
      (source: map (forwarder: "${pkgs.nftables}/bin/nft add rule inet router output ip saddr ${source} ip daddr ${forwarder} tcp dport 53 accept comment \"allow-dns-service-egress\"") forwarder4)
      dnsEgressSources4)
    ++ (lib.concatMap
      (source: map (forwarder: "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} ip6 daddr ${forwarder} udp dport 53 accept comment \"allow-dns-service-egress\"") forwarder6)
      dnsEgressSources6)
    ++ (lib.concatMap
      (source: map (forwarder: "${pkgs.nftables}/bin/nft add rule inet router output ip6 saddr ${source} ip6 daddr ${forwarder} tcp dport 53 accept comment \"allow-dns-service-egress\"") forwarder6)
      dnsEgressSources6)
    ++ (lib.concatMap
      (
        cidr:
        [
          "${pkgs.nftables}/bin/nft add rule inet router output ip daddr ${cidr} udp dport 53 drop comment \"deny-public-dns-output-leak\""
          "${pkgs.nftables}/bin/nft add rule inet router output ip daddr ${cidr} tcp dport 53 drop comment \"deny-public-dns-output-leak\""
        ]
      )
      deniedResolverCidrs4)
    ++ (lib.concatMap
      (
        cidr:
        [
          "${pkgs.nftables}/bin/nft add rule inet router output ip6 daddr ${cidr} udp dport 53 drop comment \"deny-public-dns-output-leak\""
          "${pkgs.nftables}/bin/nft add rule inet router output ip6 daddr ${cidr} tcp dport 53 drop comment \"deny-public-dns-output-leak\""
        ]
      )
      deniedResolverCidrs6);
in
{
  inherit nftRules;
  dnsOutputScript =
    if dnsOutputRules != [ ] then
      lib.concatStringsSep "\n          " dnsOutputRules
    else
      ":";
}
