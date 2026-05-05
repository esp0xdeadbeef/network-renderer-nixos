{ lib }:

let
  listOr = value: if builtins.isList value then value else [ ];
  nftString = value: ''"${lib.replaceStrings [ ''\'' "\\" ''"'' ] [ ''\\'' "\\\\" ''\"'' ] (toString value)}"'';
  sortedUnique = values: lib.sort (left: right: left < right) (lib.unique values);
  publicIPv4Match = forward:
    if builtins.isString (forward.publicIPv4SetName or null) && forward.publicIPv4SetName != "" then
      "ip daddr @${forward.publicIPv4SetName}"
    else
      "ip daddr ${forward.publicIPv4}";

  exceptDportText = dports:
    let ports = sortedUnique dports;
    in
    if ports == [ ] then
      ""
    else
      " dport != { ${lib.concatStringsSep ", " (map toString ports)} }";

  renderMatch = match:
    let
      proto = match.proto or "any";
      dports = listOr (match.dports or null);
      dportSet = "{ ${lib.concatStringsSep ", " (map toString dports)} }";
      protoText = if proto == "any" then "" else " meta l4proto ${proto}";
      dportText =
        if proto == "any" || dports == [ ] then
          ""
        else
          " ${proto} dport ${if builtins.length dports == 1 then toString (builtins.head dports) else dportSet}";
    in
    "${protoText}${dportText}";

  renderServiceForward = bridgeInterface: forward:
    lib.concatMapStringsSep "\n"
      (match:
        ''
          ${publicIPv4Match forward}${renderMatch match} dnat to ${forward.targetIPv4} comment ${nftString forward.comment}
        '')
      forward.matches;

  renderServiceAccept = bridgeInterface: forward:
    lib.concatMapStringsSep "\n"
      (match:
        ''
          iifname != ${nftString bridgeInterface} oifname ${nftString bridgeInterface} ip daddr ${forward.targetIPv4}${renderMatch match} accept comment ${nftString forward.comment}
          iifname ${nftString bridgeInterface} oifname ${nftString bridgeInterface} ip daddr ${forward.targetIPv4}${renderMatch match} accept comment ${nftString forward.comment}
        '')
      forward.matches;

  renderRuntimeForward = bridgeInterface: requiredString: protectedDportsByProto: forward:
    let
      targetIPv4 = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].targetIPv4" (forward.targetIPv4 or null);
      protocols = if listOr (forward.protocols or null) == [ ] then [ "tcp" "udp" ] else forward.protocols;
      exceptTcpDports = listOr (forward.exceptTcpDports or null);
      protectServiceDports = forward.protectServiceDports or true;
      comment = forward.comment or "s88-public-runtime-forward";
    in
    lib.concatMapStringsSep "\n"
      (proto:
        let
          protectedDports =
            if protectServiceDports then
              listOr (protectedDportsByProto.${proto} or null)
            else
              [ ];
          except =
            if proto == "tcp" then
              " tcp${exceptDportText (exceptTcpDports ++ protectedDports)}"
            else if protectedDports != [ ] then
              " ${proto}${exceptDportText protectedDports}"
            else
              "";
        in
        ''
          iifname != ${nftString bridgeInterface} ${publicIPv4Match forward} meta l4proto ${proto}${except} dnat to ${targetIPv4} comment ${nftString comment}
        '')
      protocols;

  renderRuntimeAccept = bridgeInterface: requiredString: forward:
    let
      targetIPv4 = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].targetIPv4" (forward.targetIPv4 or null);
      protocols = if listOr (forward.protocols or null) == [ ] then [ "tcp" "udp" ] else forward.protocols;
      exceptTcpDports = listOr (forward.exceptTcpDports or null);
      comment = forward.comment or "s88-public-runtime-forward";
    in
    lib.concatMapStringsSep "\n"
      (proto:
        let
          except =
            if proto == "tcp" && exceptTcpDports != [ ] then
              " tcp dport != { ${lib.concatStringsSep ", " (map toString exceptTcpDports)} }"
            else
              "";
        in
        ''
          iifname != ${nftString bridgeInterface} oifname ${nftString bridgeInterface} ip daddr ${targetIPv4} meta l4proto ${proto}${except} accept comment ${nftString comment}
        '')
      protocols;
in
{
  inherit
    nftString
    renderServiceForward
    renderServiceAccept
    renderRuntimeForward
    renderRuntimeAccept
    ;
}
