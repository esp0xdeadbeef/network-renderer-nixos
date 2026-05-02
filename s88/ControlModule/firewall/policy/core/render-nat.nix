{ lib, serviceNat, relationNameOf }:

let
  renderInetFamilyMatch =
    family:
    if family == "ipv4" then "meta nfproto ipv4" else if family == "ipv6" then "meta nfproto ipv6" else "";

  renderL4Match =
    { proto, dport }:
    if proto == null || proto == "any" then
      ""
    else if proto == "tcp" || proto == "udp" then
      let portExpr = if dport == null then "" else " ${proto} dport ${builtins.toString dport}";
      in "meta l4proto ${proto}${portExpr}"
    else
      "meta l4proto ${proto}";

  renderFamilyDaddr =
    { family, target }:
    if family == "ipv4" then "ip daddr ${target}" else if family == "ipv6" then "ip6 daddr ${target}" else "";

  joinMatchParts =
    parts: lib.concatStringsSep " " (lib.filter (part: builtins.isString part && part != "") parts);

  ingressSelectorFor =
    entry:
    if builtins.length entry.ingressIfNames == 1 then
      "\"${builtins.head entry.ingressIfNames}\""
    else
      "{ ${builtins.concatStringsSep ", " (map (name: "\"${name}\"") entry.ingressIfNames)} }";
in
{
  portForwardForwardRules = map (
    entry:
    let
      matchExpr = joinMatchParts [
        (renderInetFamilyMatch entry.family)
        (renderFamilyDaddr { inherit (entry) family target; })
        (renderL4Match { inherit (entry) proto dport; })
      ];
    in
    "iifname ${ingressSelectorFor entry} ${matchExpr} accept comment \"${
      relationNameOf { id = entry.relationName; }
    }\""
  ) serviceNat.serviceNatEntries;

  natPreroutingRules4 = map (
    entry:
    "iifname ${ingressSelectorFor entry} ${
      renderL4Match { inherit (entry) proto dport; }
    } dnat to ${entry.target} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv4") serviceNat.serviceNatEntries);

  natPreroutingRules6 = map (
    entry:
    "iifname ${ingressSelectorFor entry} ${
      renderL4Match { inherit (entry) proto dport; }
    } dnat to ${entry.target} comment \"${entry.relationName}\""
  ) (lib.filter (entry: entry.family == "ipv6") serviceNat.serviceNatEntries);
}
