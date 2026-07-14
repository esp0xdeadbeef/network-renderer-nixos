{ lib, sourceModel, common, portResolution }:

let
  inherit (sourceModel) attachForPort;
  inherit (common) sortedAttrNames runtimeTargetForUnitFromNormalized;

  tryResolvePortForRuntimeInterface =
    args:
    let
      attempt = builtins.tryEval (portResolution.resolvePortForRuntimeInterface args);
    in
    if attempt.success then attempt.value else null;

  attachTargetForRuntimeInterface =
    { source, normalizedRuntimeTargets, unitName, ifName, iface, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      resolvedPort = tryResolvePortForRuntimeInterface { inherit source normalizedRuntimeTargets unitName ifName iface file; };
      attachTarget =
        if resolvedPort == null then
          null
        else
          attachForPort {
            inherit file unitName;
            node = resolvedPort.node;
            portName = resolvedPort.portName;
            port = resolvedPort.port;
          };
    in
    if attachTarget == null then
      null
    else
      attachTarget
      // {
        inherit unitName ifName;
        renderedIfName = iface.renderedIfName or null;
        interface = iface;
        connectivity = iface.connectivity or { };
        backingRef = iface.backingRef or { };
        realizationNodeName = resolvedPort.nodeName;
      };

  fallbackAttachTargetForRuntimeInterface =
    { unitName, ifName, iface, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      attach = if iface ? attach && builtins.isAttrs iface.attach then iface.attach else { };
      hasExplicitBridgeAttach =
        (attach.kind or null) == "bridge"
        && attach ? bridge
        && builtins.isString attach.bridge
        && attach.bridge != "";
      hostBridgeName =
        if hasExplicitBridgeAttach then
          attach.bridge
        else if iface ? hostBridge && builtins.isString iface.hostBridge then
          iface.hostBridge
        else
          throw ''
            ${file}: normalized interface '${ifName}' for unit '${unitName}' is missing hostBridge

            interface:
            ${builtins.toJSON iface}
          '';
    in
    {
      inherit unitName ifName hostBridgeName;
      renderedIfName = iface.renderedIfName or null;
      interface = iface;
      connectivity = iface.connectivity or { };
      backingRef = iface.backingRef or { };
      kind = if hasExplicitBridgeAttach then "bridge" else "synthetic";
      name = hostBridgeName;
      originalName = hostBridgeName;
      identity = {
        unitName = unitName;
        portName = ifName;
        attachmentKind = if hasExplicitBridgeAttach then "bridge" else "synthetic";
      };
    };
  # FS-500-HDS-010-SDS-010-SMS-050: runtime p2p bridge co-location.
  # Both endpoints of one modeled p2p link must share one runtime L2
  # attachment. When one endpoint resolves to an explicit realization
  # attachment (inventory bridge or direct link bridge) and the peer endpoint
  # only has a synthetic fallback attachment, the synthetic endpoint is
  # co-located onto the explicit attachment derived from the modeled
  # backingRef link identity. Name-derived repair stays rejected: the grouping
  # key is backingRef.id, never bridge/interface/host name similarity.
  modeledLinkIdForTarget =
    target:
    let
      backingRef =
        if target ? backingRef && builtins.isAttrs target.backingRef then target.backingRef else { };
    in
    if (backingRef.kind or null) == "link" && builtins.isString (backingRef.id or null) then
      backingRef.id
    else
      null;

  explicitLinkBridgesForTargets =
    targets:
    builtins.foldl'
      (
        acc: target:
        let
          linkId = modeledLinkIdForTarget target;
        in
        if
          linkId == null
          || (target.kind or null) == "synthetic"
          || !(builtins.isString (target.hostBridgeName or null))
        then
          acc
        else
          acc // { ${linkId} = lib.unique ((acc.${linkId} or [ ]) ++ [ target.hostBridgeName ]); }
      )
      { }
      targets;

  colocateSyntheticTargetsByModeledLink =
    { targets, file }:
    let
      explicitLinkBridges = explicitLinkBridgesForTargets targets;

      colocate =
        target:
        let
          linkId = modeledLinkIdForTarget target;
          peerBridges = if linkId == null then [ ] else explicitLinkBridges.${linkId} or [ ];
        in
        if (target.kind or null) != "synthetic" || peerBridges == [ ] then
          target
        else if builtins.length peerBridges == 1 then
          let
            bridgeName = builtins.head peerBridges;
          in
          target
          // {
            kind = "bridge";
            name = bridgeName;
            originalName = bridgeName;
            hostBridgeName = bridgeName;
            identity = (if builtins.isAttrs (target.identity or null) then target.identity else { }) // {
              attachmentKind = "bridge";
              colocatedByModeledLink = linkId;
            };
          }
        else
          throw ''
            ${file}: FS-500-HDS-010-SDS-010-SMS-050: split runtime attachment for modeled p2p link '${linkId}'

            endpoint '${target.unitName or "<unknown>"}/${target.ifName or "<unknown>"}' has no explicit
            attachment, and peer endpoints of the same modeled link resolve to more than one runtime
            L2 attachment: ${builtins.concatStringsSep ", " peerBridges}

            Both endpoints of one modeled point-to-point link must share one runtime bridge/link
            attachment derived from modeled link identity.
          '';
    in
    map colocate targets;
in
{
  attachTargetsForUnitsFromRuntime =
    { source ? { }, selectedUnits, normalizedRuntimeTargets, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      resolvedTargets = lib.concatMap
        (
          unitName:
          let
            runtimeTarget = runtimeTargetForUnitFromNormalized { inherit normalizedRuntimeTargets unitName file; };
            interfaces =
              if runtimeTarget ? interfaces && builtins.isAttrs runtimeTarget.interfaces then
                runtimeTarget.interfaces
              else
                { };
          in
          map
            (
              ifName:
              let
                iface = interfaces.${ifName};
                authoritativeTarget =
                  if source == { } then
                    null
                  else
                    attachTargetForRuntimeInterface { inherit source normalizedRuntimeTargets unitName ifName iface file; };
              in
              if authoritativeTarget != null then
                authoritativeTarget
              else
                fallbackAttachTargetForRuntimeInterface { inherit unitName ifName iface file; }
            )
            (sortedAttrNames interfaces)
        )
        selectedUnits;
    in
    colocateSyntheticTargetsByModeledLink { targets = resolvedTargets; inherit file; };
}
