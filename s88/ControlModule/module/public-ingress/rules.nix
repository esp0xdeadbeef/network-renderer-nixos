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

  dportMatchText = proto: dports:
    let
      ports = sortedUnique dports;
      portText =
        if builtins.length ports == 1 then
          toString (builtins.head ports)
        else
          "{ ${lib.concatStringsSep ", " (map toString ports)} }";
    in
    if proto == "any" || ports == [ ] then "" else " ${proto} dport ${portText}";

  renderMatch = match:
    let
      proto = match.proto or (throw "FS-310-HDS-030-SDS-010-SMS-111: match.proto required by CPM provider contract, cannot default to 'any'");
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

  # FS-230-HDS-010-SDS-010-SMS-020: translationMode = "none" is an explicit
  # no-translation decision — emit no DNAT for that service tuple. Only an
  # explicit translation-capable mode keeps the DNAT contract; an absent
  # decision (missing translationMode) is an ambiguous translation binding and
  # fails closed instead of materializing legacy DNAT.
  noTranslationDecision = forward: (forward.translationMode or null) == "none";

  requireTranslationDecision = forward:
    if (forward.translationMode or null) == null then
      throw "FS-230-HDS-010-SDS-010-SMS-020: public-ingress service tuple '${forward.serviceName or forward.comment or "<unknown>"}' has no publicIngressTupleAuthority.translationMode (missing translation mode field; ambiguous translation binding) — refusing legacy DNAT materialization"
    else
      forward;

  renderServiceForward = bridgeInterface: forward:
    if noTranslationDecision (requireTranslationDecision forward) then
      ""
    else
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

  renderServiceSnat = forward:
    if noTranslationDecision (requireTranslationDecision forward) then
      ""
    else
      ''
        ip saddr ${forward.targetIPv4} ct status dnat masquerade comment ${nftString "${forward.comment}-snat"}
      '';

  # FS-310-HDS-010-SDS-010-SMS-130: renderRuntimeForward is a DNAT helper, and
  # a direct invocation on synthetic runtime facts must never materialize DNAT.
  # The forward must carry the CPM-artifact public-ingress authority record
  # that the runtime-forward normalization attaches after cross-checking the
  # CPM artifact (external allow service relation with
  # publicIngressTupleAuthority owning the target endpoint / production host
  # entry). A forward without that record fails closed here.
  requireRuntimeForwardAuthority = forward:
    let
      authority = forward.publicIngressAuthority or null;
    in
    if
      !(builtins.isAttrs authority)
      || (authority.source or null) != "cpm-artifact"
      || !(builtins.isString (authority.translationMode or null))
      || authority.translationMode == ""
    then
      throw "FS-310-HDS-010-SDS-010-SMS-130: runtime forward '${forward.comment or "<unknown>"}' invoked without a CPM-artifact public-ingress authority record (direct helper invocation on caller-supplied synthetic runtime facts) — refusing DNAT materialization (diagnostic.synthetic-core-ingress-authority, FS-310-HDS-020-SDS-010-SMS-075 negative case 3; RENDERER_LOCAL_POLICY_AUTHORITY, FS-310-HDS-040-SDS-010-SMS-101: direct helper arguments cannot create policy output absent from the CPM artifact)"
    else
      forward;

  runtimeNoTranslationDecision = forward:
    (requireRuntimeForwardAuthority forward).publicIngressAuthority.translationMode == "none";

  renderRuntimeForward = bridgeInterface: requiredString: protectedDportsByProto: forward:
    if runtimeNoTranslationDecision forward then
      ""
    else
    let
      targetIPv4 = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].targetIPv4" (forward.targetIPv4 or null);
      protocols = if listOr (forward.protocols or null) == [ ] then [ "tcp" "udp" ] else forward.protocols;
      inputDports = listOr (forward.inputDports or null);
      exceptTcpDports = listOr (forward.exceptTcpDports or null);
      protectServiceDports = forward.protectServiceDports or (throw "FS-310-HDS-030-SDS-010-SMS-111: forward.protectServiceDports required by CPM provider contract, cannot default to true");
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
            if inputDports != [ ] then
              dportMatchText proto inputDports
            else if proto == "tcp" then
              " tcp${exceptDportText (exceptTcpDports ++ protectedDports)}"
            else if protectedDports != [ ] then
              " ${proto}${exceptDportText protectedDports}"
            else
              "";
        in
        ''
          ${publicIPv4Match forward} meta l4proto ${proto}${except} dnat to ${targetIPv4} comment ${nftString comment}
        '')
      protocols;

  renderRuntimeAccept = bridgeInterface: requiredString: forward:
    let
      targetIPv4 = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].targetIPv4" (forward.targetIPv4 or null);
      protocols = if listOr (forward.protocols or null) == [ ] then [ "tcp" "udp" ] else forward.protocols;
      inputDports = listOr (forward.inputDports or null);
      exceptTcpDports = listOr (forward.exceptTcpDports or null);
      comment = forward.comment or "s88-public-runtime-forward";
    in
    lib.concatMapStringsSep "\n"
      (proto:
        let
          except =
            if inputDports != [ ] then
              dportMatchText proto inputDports
            else if proto == "tcp" && exceptTcpDports != [ ] then
              " tcp dport != { ${lib.concatStringsSep ", " (map toString exceptTcpDports)} }"
            else
              "";
        in
        ''
          iifname != ${nftString bridgeInterface} oifname ${nftString bridgeInterface} ip daddr ${targetIPv4} meta l4proto ${proto}${except} accept comment ${nftString comment}
          iifname ${nftString bridgeInterface} oifname ${nftString bridgeInterface} ip daddr ${targetIPv4} meta l4proto ${proto}${except} accept comment ${nftString comment}
        '')
      protocols;
in
{
  inherit
    nftString
    renderServiceForward
    renderServiceAccept
    renderServiceSnat
    renderRuntimeForward
    renderRuntimeAccept
    ;
}
