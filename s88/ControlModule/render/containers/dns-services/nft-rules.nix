{
  lib,
  pkgs,
  facts,
}:

# Firewall rules for the DNS service.
#
# These rules are a pure function of the realized model: listen addresses,
# forwarders, ingress interface names, DNS egress sources and registered
# upstreams can all be determined at build time. They therefore render as
# declarative `nft` syntax that the container's `nftables.conf` carries as one
# file, rather than as a oneshot service issuing `nft add rule` at boot.
#
# What remains imperative is only what genuinely cannot be known statically:
# the egress-mark table whose priority has to coexist with a live routing
# policy, and the registered-upstream sets that are repopulated when the health
# timer rewrites them. Both are emitted separately and applied by
# `nft-dns-dynamic`.
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

  # A realized rule record names its family; render the matching source match.
  sourceMatch =
    rule:
    let
      source = rule.source;
    in
    if (source.family or 4) == 6 then "ip6 saddr ${source.prefix}" else "ip saddr ${source.prefix}";

  dnsServiceForwardEgressRulesDeclarative = lib.concatMap (rule: [
    "iifname ${nftString rule.inInterface} oifname ${nftString rule.outInterface} ${sourceMatch rule} udp dport 53 accept comment \"allow-dns-service-forward-egress\""
    "iifname ${nftString rule.inInterface} oifname ${nftString rule.outInterface} ${sourceMatch rule} tcp dport 53 accept comment \"allow-dns-service-forward-egress\""
  ]) dnsServiceForwardEgressRules;

  # listener accepts: input chain, one pair per realized listen address.
  listenerAccepts =
    (map (addr: "ip daddr ${addr} udp dport 53 accept comment \"allow-dns-service\"") listen4)
    ++ (map (addr: "ip daddr ${addr} tcp dport 53 accept comment \"allow-dns-service\"") listen4)
    ++ (map (addr: "ip6 daddr ${addr} udp dport 53 accept comment \"allow-dns-service\"") listen6)
    ++ (map (addr: "ip6 daddr ${addr} tcp dport 53 accept comment \"allow-dns-service\"") listen6);

  # direct DNS egress from an access ingress is denied before any accept can
  # match it, so these go to the head of the forward chain.
  denyDirectEgress =
    lib.concatMap (ifName: [
      "iifname ${nftString ifName} udp dport 53 drop comment \"deny-direct-dns-egress\""
      "iifname ${nftString ifName} tcp dport 53 drop comment \"deny-direct-dns-egress\""
    ]) ingressInterfaceNames;

  # egress accepts from the DNS service's own sources towards realized forwarders.
  forwarderAccepts =
    (lib.concatMap (
      source:
      lib.concatMap (fwd: [
        "ip saddr ${source} ip daddr ${fwd} udp dport 53 accept comment \"allow-dns-service-egress\""
        "ip saddr ${source} ip daddr ${fwd} tcp dport 53 accept comment \"allow-dns-service-egress\""
      ]) forwarder4
    ) dnsEgressSources4)
    ++ (lib.concatMap (
      source:
      lib.concatMap (fwd: [
        "ip6 saddr ${source} ip6 daddr ${fwd} udp dport 53 accept comment \"allow-dns-service-egress\""
        "ip6 saddr ${source} ip6 daddr ${fwd} tcp dport 53 accept comment \"allow-dns-service-egress\""
      ]) forwarder6
    ) dnsEgressSources6);

  # A rule may only reference a set that is actually declared. The set is
  # declared when the model registered a matching upstream family, so the
  # accepts are gated on the same condition.
  registeredUpstreamAccepts =
    (lib.optionals (registeredUpstreams4 != [ ]) (
      lib.concatMap (source: [
        "ip saddr ${source} ip daddr @s88_dns_upstream4 udp dport 53 accept comment \"allow-dns-service-egress-registered\""
        "ip saddr ${source} ip daddr @s88_dns_upstream4 tcp dport 53 accept comment \"allow-dns-service-egress-registered\""
      ]) dnsEgressSources4
    ))
    ++ (lib.optionals (registeredUpstreams6 != [ ]) (
      lib.concatMap (source: [
        "ip6 saddr ${source} ip6 daddr @s88_dns_upstream6 udp dport 53 accept comment \"allow-dns-service-egress-registered\""
        "ip6 saddr ${source} ip6 daddr @s88_dns_upstream6 tcp dport 53 accept comment \"allow-dns-service-egress-registered\""
      ]) dnsEgressSources6
    ));

  strictEgressDefaultDrops =
    if strictEgress then
      (lib.concatMap (source: [
        "ip saddr ${source} udp dport 53 drop comment \"deny-dns-service-egress-default\""
        "ip saddr ${source} tcp dport 53 drop comment \"deny-dns-service-egress-default\""
      ]) dnsEgressSources4)
      ++ (lib.concatMap (source: [
        "ip6 saddr ${source} udp dport 53 drop comment \"deny-dns-service-egress-default\""
        "ip6 saddr ${source} tcp dport 53 drop comment \"deny-dns-service-egress-default\""
      ]) dnsEgressSources6)
    else
      [ ];

  # Set declarations must precede the rules that reference them.
  registeredUpstreamSetDeclarations =
    (lib.optional (registeredUpstreams4 != [ ]) "set s88_dns_upstream4 { type ipv4_addr; }")
    ++ (lib.optional (registeredUpstreams6 != [ ]) "set s88_dns_upstream6 { type ipv6_addr; }");

  chainBody = rules: if rules == [ ] then "policy accept;" else "policy accept;\n" + lib.concatStringsSep "\n" rules;
in
{
  # Declarative DNS rules, delivered as firewall chain rules.
  #
  # The firewall module owns `table inet router` and its input/forward/output
  # chains; a second `table inet router` in the same nftables.conf is a syntax
  # error, so this module contributes *rules* to those chains rather than a
  # table of its own. Everything here is a pure function of the realized model.
  #
  # Ordering is significant: direct-egress denials are placed ahead of the DNS
  # forward accepts so a client can never reach an upstream the model did not
  # grant.
  inputRules = listenerAccepts;

  forwardRules = denyDirectEgress ++ dnsServiceForwardEgressRulesDeclarative;

  outputRules = forwarderAccepts ++ registeredUpstreamAccepts ++ strictEgressDefaultDrops;

  # Set declarations have no chain placement, so they stay a small standalone
  # fragment applied by nftables before the table is populated.
  setsFragment =
    if registeredUpstreamSetDeclarations == [ ] then
      ""
    else
      "table inet router {\n"
      + lib.concatStringsSep "\n" registeredUpstreamSetDeclarations
      + "\n}\n";

  # Genuinely dynamic: populated by the health timer and by policy routing.
  dynamicScript =
    let
      mark = if dnsEgressPolicy == null then null else toString dnsEgressPolicy.firewallMark;
    in
    lib.optionalString (mark != null) ''
      if ${pkgs.nftables}/bin/nft list table inet s88_dns_egress >/dev/null 2>&1; then
        ${pkgs.nftables}/bin/nft delete table inet s88_dns_egress
      fi
      ${pkgs.nftables}/bin/nft add table inet s88_dns_egress
      ${pkgs.nftables}/bin/nft 'add chain inet s88_dns_egress output { type route hook output priority mangle; policy accept; }'
      ${pkgs.nftables}/bin/nft add rule inet s88_dns_egress output meta skuid "unbound" udp dport 53 meta mark set ${mark} comment "select-modeled-dns-egress"
      ${pkgs.nftables}/bin/nft add rule inet s88_dns_egress output meta skuid "unbound" tcp dport 53 meta mark set ${mark} comment "select-modeled-dns-egress"
    '';
}
