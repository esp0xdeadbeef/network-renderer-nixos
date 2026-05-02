{
  lib,
  currentSite,
  runtimeTarget,
  roleName,
  unitName,
  containerName,
  currentNodeName,
  tenantAttachments,
  tenantInterfaceByName,
  upstreamSelectorNodeName,
  upstreamInterfaceNames,
  interfaceTags,
  common,
}:

let
  inherit (common) sortedStrings;

  missingTenantBindings = lib.filter (
    tenantName: !builtins.hasAttr tenantName tenantInterfaceByName
  ) (sortedStrings (map (attachment: attachment.name) tenantAttachments));

  authorityGaps = lib.unique (
    lib.optionals (currentNodeName == null) [
      "policy node identity could not be resolved from the rendered runtime target"
    ]
    ++ lib.optionals (interfaceTags == { }) [
      "policy interface tags are missing (README requires site.policy.interfaceTags canonically)"
    ]
    ++ lib.optionals (missingTenantBindings != [ ]) [
      "tenant attachments could not be bound to policy transit interfaces: ${builtins.toJSON missingTenantBindings}"
    ]
    ++ lib.optionals (upstreamSelectorNodeName != null && upstreamInterfaceNames == [ ]) [
      "upstream-selector transit binding could not be resolved for the policy node"
    ]
  );

  authoritativeBindings = authorityGaps == [ ];

  entityName =
    if builtins.isString containerName && containerName != "" then
      containerName
    else if builtins.isString unitName && unitName != "" then
      unitName
    else if runtimeTarget ? unitName && builtins.isString runtimeTarget.unitName then
      runtimeTarget.unitName
    else
      null;

  strictMode = roleName == "policy";
in
{
  inherit authoritativeBindings authorityGaps;

  strictCheck =
    if strictMode && !authoritativeBindings then
      throw ''
        s88/ControlModule/firewall/mapping/policy-endpoints.nix: refusing to synthesize policy endpoint bindings

        container: ${toString entityName}
        role: policy
        gaps:
        ${builtins.concatStringsSep "\n" (map (line: "  - ${line}") authorityGaps)}
      ''
    else
      null;
}
