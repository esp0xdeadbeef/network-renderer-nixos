{ lib, common }:

let
  inherit (common) identityPartToString;
in
{
  hostBridgeIdentityForInterface =
    { unitName, ifName, iface, file ? "s88/Unit/mapping/runtime-targets.nix" }:
    let
      backingRef =
        if iface ? backingRef && builtins.isAttrs iface.backingRef then
          iface.backingRef
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef

            interface:
            ${builtins.toJSON iface}
          '';
      backingRefId =
        if backingRef ? id && builtins.isString backingRef.id then
          backingRef.id
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef.id

            interface:
            ${builtins.toJSON iface}
          '';
      backingRefKind =
        if backingRef ? kind && builtins.isString backingRef.kind then
          backingRef.kind
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef.kind

            interface:
            ${builtins.toJSON iface}
          '';
      sourceKind = if iface ? sourceKind && builtins.isString iface.sourceKind then iface.sourceKind else backingRefKind;
      upstream = identityPartToString (iface.upstream or null);
      bridgeBackingRefId =
        if sourceKind == "overlay" && builtins.isString (backingRef.name or null) && backingRef.name != "" then
          "overlay::${backingRef.name}"
        else
          backingRefId;
      segments = lib.filter builtins.isString (
        [ "rt" sourceKind backingRefKind bridgeBackingRefId ]
        ++ lib.optionals (upstream != null) [ upstream ]
      );
    in
    builtins.concatStringsSep "--" segments;
}
