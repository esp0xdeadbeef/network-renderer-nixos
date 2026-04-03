{ lib }:

let
  base = import ./base.nix { inherit lib; };

  sortedAttrNames = base.sortedAttrNames;

  emittedInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      target = base.runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      effectiveRuntimeRealization =
        if target ? effectiveRuntimeRealization && builtins.isAttrs target.effectiveRuntimeRealization then
          target.effectiveRuntimeRealization
        else
          throw ''
            ${file}: runtime target for unit '${unitName}' is missing effectiveRuntimeRealization

            runtime target:
            ${builtins.toJSON target}
          '';
    in
    if
      effectiveRuntimeRealization ? interfaces && builtins.isAttrs effectiveRuntimeRealization.interfaces
    then
      effectiveRuntimeRealization.interfaces
    else
      throw ''
        ${file}: runtime target for unit '${unitName}' is missing effectiveRuntimeRealization.interfaces

        runtime target:
        ${builtins.toJSON target}
      '';

  validateStringField =
    {
      value,
      fieldName,
      unitName,
      ifName ? null,
      file ? "s88/Unit/lookup/runtime-context.nix",
      context ? { },
    }:
    if builtins.isString value then
      true
    else
      throw ''
        ${file}: expected string field '${fieldName}'${
          if ifName != null then " on interface '${ifName}'" else ""
        } for unit '${unitName}'

        context:
        ${builtins.toJSON context}
      '';

  validateOptionalStringOrListField =
    {
      value,
      fieldName,
      unitName,
      ifName ? null,
      file ? "s88/Unit/lookup/runtime-context.nix",
      context ? { },
    }:
    if value == null || builtins.isString value || builtins.isList value then
      true
    else
      throw ''
        ${file}: expected string-or-list field '${fieldName}'${
          if ifName != null then " on interface '${ifName}'" else ""
        } for unit '${unitName}'

        context:
        ${builtins.toJSON context}
      '';

  validateOptionalAttrField =
    {
      value,
      fieldName,
      unitName,
      ifName ? null,
      file ? "s88/Unit/lookup/runtime-context.nix",
      context ? { },
    }:
    if value == null || builtins.isAttrs value then
      true
    else
      throw ''
        ${file}: expected attr field '${fieldName}'${
          if ifName != null then " on interface '${ifName}'" else ""
        } for unit '${unitName}'

        context:
        ${builtins.toJSON context}
      '';

  validateInterfaceForUnit =
    {
      unitName,
      ifName,
      iface,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
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

      _validateRenderedIfName = validateStringField {
        value = iface.renderedIfName or null;
        fieldName = "renderedIfName";
        inherit unitName ifName file;
        context = iface;
      };

      _validateBackingRefId = validateStringField {
        value = backingRef.id or null;
        fieldName = "backingRef.id";
        inherit unitName ifName file;
        context = iface;
      };

      _validateBackingRefKind = validateStringField {
        value = backingRef.kind or null;
        fieldName = "backingRef.kind";
        inherit unitName ifName file;
        context = iface;
      };

      _validateSourceKind = validateStringField {
        value = iface.sourceKind or null;
        fieldName = "sourceKind";
        inherit unitName ifName file;
        context = iface;
      };

      _validateAddr4 = validateOptionalStringOrListField {
        value = iface.addr4 or null;
        fieldName = "addr4";
        inherit unitName ifName file;
        context = iface;
      };

      _validateAddr6 = validateOptionalStringOrListField {
        value = iface.addr6 or null;
        fieldName = "addr6";
        inherit unitName ifName file;
        context = iface;
      };

      _validateRoutes = validateOptionalAttrField {
        value = iface.routes or { };
        fieldName = "routes";
        inherit unitName ifName file;
        context = iface;
      };

      _validateRoutesIpv4 = validateOptionalStringOrListField {
        value = if iface ? routes && builtins.isAttrs iface.routes then iface.routes.ipv4 or [ ] else [ ];
        fieldName = "routes.ipv4";
        inherit unitName ifName file;
        context = iface;
      };

      _validateRoutesIpv6 = validateOptionalStringOrListField {
        value = if iface ? routes && builtins.isAttrs iface.routes then iface.routes.ipv6 or [ ] else [ ];
        fieldName = "routes.ipv6";
        inherit unitName ifName file;
        context = iface;
      };
    in
    true;

  validateRuntimeTargetForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      _interfaces = emittedInterfacesForUnit {
        inherit cpm unitName file;
      };

      _validateInterfaces = map (
        ifName:
        validateInterfaceForUnit {
          inherit unitName ifName file;
          iface = _interfaces.${ifName};
        }
      ) (sortedAttrNames _interfaces);
    in
    true;

  validateAllRuntimeTargets =
    {
      cpm,
      inventory ? { },
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      targets = base.runtimeTargets cpm;

      _validations = map (
        unitName:
        validateRuntimeTargetForUnit {
          inherit
            cpm
            inventory
            unitName
            file
            ;
        }
      ) (sortedAttrNames targets);
    in
    true;
in
{
  inherit
    emittedInterfacesForUnit
    validateInterfaceForUnit
    validateRuntimeTargetForUnit
    validateAllRuntimeTargets
    ;
}
