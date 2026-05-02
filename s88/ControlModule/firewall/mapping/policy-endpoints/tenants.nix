{
  lib,
  currentSite,
  runtimeTarget,
  currentNodeName,
  firstHopInterfaceToUnit,
  resolveInterfaceAlias,
  common,
}:

let
  tenantAttachments =
    if currentSite ? attachments && builtins.isList currentSite.attachments then
      lib.filter (
        attachment:
        builtins.isAttrs attachment
        && (attachment.kind or null) == "tenant"
        && attachment ? name
        && builtins.isString attachment.name
        && attachment ? unit
        && builtins.isString attachment.unit
      ) currentSite.attachments
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

  boundInterfaceForCurrentNodeTenant =
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
      matches = lib.filter (
        binding:
        let
          logicalNode = binding.logicalNode or null;
          runtimeTargetName = binding.runtimeTarget or null;
        in
        (logicalNode != null && logicalNode == currentNodeName)
        || (runtimeTargetName != null && runtimeTargetName == (runtimeTarget.name or null))
      ) runtimeBindings;
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
    if resolved == [ ] then null else builtins.head resolved;
in
{
  inherit tenantAttachments;

  tenantInterfaceByName = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      map (
        attachment:
        let
          interfaceName =
            if currentNodeName != null && attachment.unit == currentNodeName then
              boundInterfaceForCurrentNodeTenant attachment.name
            else
              firstHopInterfaceToUnit attachment.unit;
        in
        if interfaceName != null then
          {
            name = attachment.name;
            value = interfaceName;
          }
        else
          null
      ) tenantAttachments
    )
  );
}
