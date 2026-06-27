{ lib
, currentSite
, runtimeTarget
, currentNodeName
, firstHopInterfaceToUnit
, firstHopInterfacesToUnit
, resolveInterfaceAlias
, common
,
}:

let
  inherit (common) sortedStrings;

  tenantAttachments =
    if currentSite ? attachments && builtins.isList currentSite.attachments then
      lib.filter
        (
          attachment:
          builtins.isAttrs attachment
          && (attachment.kind or null) == "tenant"
          && attachment ? name
          && builtins.isString attachment.name
          && attachment ? unit
          && builtins.isString attachment.unit
        )
        currentSite.attachments
    else
      [ ];

  policyTenantBindings =
    if
      currentSite ? policy
      && builtins.isAttrs currentSite.policy
      && currentSite.policy ? endpointBindings
      && builtins.isAttrs currentSite.policy.endpointBindings
      && currentSite.policy.endpointBindings ? tenants
      && builtins.isAttrs currentSite.policy.endpointBindings.tenants
    then
      currentSite.policy.endpointBindings.tenants
    else
      { };

  boundInterfacesForCurrentNodeTenant =
    tenantName:
    let
      tenantBinding =
        if builtins.hasAttr tenantName policyTenantBindings then
          policyTenantBindings.${tenantName}
        else
          { };
      runtimeBindings =
        if tenantBinding ? runtimeBindings && builtins.isList tenantBinding.runtimeBindings then
          lib.filter builtins.isAttrs tenantBinding.runtimeBindings
        else
          [ ];
      matches = lib.filter
        (
          binding:
          let
            logicalNode = binding.logicalNode or null;
            runtimeTargetName = binding.runtimeTarget or null;
          in
          (logicalNode != null && logicalNode == currentNodeName)
          || (runtimeTargetName != null && runtimeTargetName == (runtimeTarget.name or null))
        )
        runtimeBindings;
      binding = if matches == [ ] then null else builtins.head matches;
      candidates =
        if binding == null then
          [ ]
        else
          [
            (binding.runtimeInterface or null)
            (binding.sourceInterface or null)
          ];
      resolved = lib.filter (n: n != null) (map resolveInterfaceAlias candidates);
    in
    sortedStrings resolved;
in
rec {
  inherit tenantAttachments;

  tenantInterfacesByName = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      map
        (
          attachment:
          let
            boundInterfaces = boundInterfacesForCurrentNodeTenant attachment.name;
            interfaceNames =
              if boundInterfaces != [ ] then
                boundInterfaces
              else
                firstHopInterfacesToUnit attachment.unit;
          in
          if interfaceNames != [ ] then
            {
              name = attachment.name;
              value = interfaceNames;
            }
          else
            null
        )
      tenantAttachments
    )
  );

  tenantInterfaceByName = builtins.mapAttrs (_: interfaces: builtins.head interfaces) tenantInterfacesByName;
}
