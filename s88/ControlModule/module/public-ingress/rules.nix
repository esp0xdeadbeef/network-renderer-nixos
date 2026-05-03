{ lib }:

let
  listOr = value: if builtins.isList value then value else [ ];
  nftString = value: ''"${lib.replaceStrings [ ''\'' "\\" ''"'' ] [ ''\\'' "\\\\" ''\"'' ] (toString value)}"'';

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
          iifname != ${nftString bridgeInterface} ip daddr ${forward.publicIPv4}${renderMatch match} dnat to ${forward.targetIPv4} comment ${nftString forward.comment}
        '')
      forward.matches;

  renderServiceAccept = bridgeInterface: forward:
    lib.concatMapStringsSep "\n"
      (match:
        ''
          iifname != ${nftString bridgeInterface} oifname ${nftString bridgeInterface} ip daddr ${forward.targetIPv4}${renderMatch match} accept comment ${nftString forward.comment}
        '')
      forward.matches;

  renderRuntimeForward = bridgeInterface: requiredString: forward:
    let
      publicIPv4 = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].publicIPv4" (forward.publicIPv4 or null);
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
          iifname != ${nftString bridgeInterface} ip daddr ${publicIPv4} meta l4proto ${proto}${except} dnat to ${targetIPv4} comment ${nftString comment}
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
