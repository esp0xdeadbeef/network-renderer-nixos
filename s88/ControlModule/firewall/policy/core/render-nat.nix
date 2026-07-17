{
  lib,
  serviceNat,
  relationNameOf,
}:

let
  renderInetFamilyMatch =
    family:
    if family == "ipv4" then
      "meta nfproto ipv4"
    else if family == "ipv6" then
      "meta nfproto ipv6"
    else
      "";

  renderL4Match =
    { proto, dport }:
    if proto == null || proto == "any" then
      ""
    else if proto == "tcp" || proto == "udp" then
      let
        portExpr = if dport == null then "" else " ${proto} dport ${builtins.toString dport}";
      in
      "meta l4proto ${proto}${portExpr}"
    else
      "meta l4proto ${proto}";

  renderFamilyDaddr =
    { family, target }:
    if family == "ipv4" then
      "ip daddr ${target}"
    else if family == "ipv6" then
      "ip6 daddr ${target}"
    else
      "";

  joinMatchParts =
    parts: lib.concatStringsSep " " (lib.filter (part: builtins.isString part && part != "") parts);

  ingressSelectorFor =
    entry:
    if builtins.length entry.ingressIfNames == 1 then
      "\"${builtins.head entry.ingressIfNames}\""
    else
      "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") entry.ingressIfNames)} }";

  dnatTargetFor =
    entry:
    if builtins.isInt (entry.targetPort or null) then
      "${entry.target}:${builtins.toString entry.targetPort}"
    else
      entry.target;

  exactForwardRule =
    entry:
    let
      matchExpr = joinMatchParts [
        (renderInetFamilyMatch entry.family)
        (renderFamilyDaddr { inherit (entry) family target; })
        (renderL4Match {
          inherit (entry) proto;
          dport = entry.targetPort or entry.dport;
        })
      ];
      outputMatch =
        if builtins.isString (entry.egressIfName or null) then " oifname \"${entry.egressIfName}\"" else "";
      dnatState = if (entry.source or null) == "cpm-nat-intent" then " ct status dnat" else "";
    in
    "iifname ${ingressSelectorFor entry}${outputMatch}${dnatState} ${matchExpr} accept comment \"${
      relationNameOf { id = entry.relationName; }
    }\"";

  renderSourceTranslation =
    entry:
    let
      translation = entry.sourceTranslation or { };
      targetPort = entry.targetPort or entry.dport;
    in
    if
      (entry.source or null) != "cpm-nat-intent"
      || (translation.mode or null) != "snat"
      || !builtins.isString (translation.address or null)
      || !builtins.isString (entry.egressIfName or null)
    then
      null
    else
      "oifname \"${entry.egressIfName}\" ip daddr ${entry.target} ${
        renderL4Match {
          inherit (entry) proto;
          dport = targetPort;
        }
      } snat to ${translation.address} comment \"${entry.relationName}-source-translation\"";
in
{
  portForwardForwardRules = map exactForwardRule serviceNat.serviceNatEntries;

  natPreroutingRules4 = map (
    entry:
    "iifname ${ingressSelectorFor entry} ${
      renderL4Match { inherit (entry) proto dport; }
    } dnat to ${dnatTargetFor entry} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv4") serviceNat.serviceNatEntries);

  natPreroutingRules6 = map (
    entry:
    "iifname ${ingressSelectorFor entry} ${
      renderL4Match { inherit (entry) proto dport; }
    } dnat to ${dnatTargetFor entry} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv6") serviceNat.serviceNatEntries);

  natPostroutingRules4 = lib.filter (rule: rule != null) (
    map renderSourceTranslation (
      lib.filter (entry: entry.family == "ipv4") serviceNat.serviceNatEntries
    )
  );
  natPostroutingRules6 = [ ];
}
