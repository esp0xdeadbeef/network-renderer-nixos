{ lib, base, deployment }:

let
  requestedHostNameFor =
    { hostContext, file }:
    if hostContext ? hostname && builtins.isString hostContext.hostname then
      hostContext.hostname
    else if hostContext ? selector && builtins.isString hostContext.selector then
      hostContext.selector
    else if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
      hostContext.deploymentHostName
    else
      throw ''
        ${file}: hostContext is missing hostname
      '';

  requestedNames =
    hostContext: plural: singular:
    if builtins.hasAttr plural hostContext && builtins.isList hostContext.${plural} then
      hostContext.${plural}
    else if builtins.hasAttr singular hostContext && builtins.isString hostContext.${singular} then
      [ hostContext.${singular} ]
    else
      [ ];
in
{
  selectedUnitsForHostContext =
    { cpm, inventory ? { }, hostContext, runtimeRole ? null, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      requestedHostName = requestedHostNameFor { inherit hostContext file; };
      deploymentHostName =
        if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
          hostContext.deploymentHostName
        else
          requestedHostName;
      requestedSiteNames = requestedNames hostContext "matchedSites" "siteName";
      requestedEnterpriseNames = requestedNames hostContext "matchedEnterprises" "enterpriseName";
      matchesRequestedIdentity =
        unitName:
        let
          logicalNode = base.logicalNodeForUnit { inherit cpm inventory unitName file; };
          unitSite = logicalNode.site or null;
          unitEnterprise = logicalNode.enterprise or null;
        in
        (requestedSiteNames == [ ] || builtins.elem unitSite requestedSiteNames)
        && (requestedEnterpriseNames == [ ] || builtins.elem unitEnterprise requestedEnterpriseNames);
      deploymentCandidates = deployment.unitNamesForDeploymentHost { inherit cpm inventory deploymentHostName file; };
      fallbackCandidates = base.sortedAttrNames (base.runtimeTargets cpm);
      identityFallbackCandidates = lib.filter matchesRequestedIdentity fallbackCandidates;
      hostScopedCandidates = lib.filter (
        unitName:
        deployment.requestedHostMatchesUnit {
          inherit cpm inventory unitName file;
          requestedHostName = requestedHostName;
        }
      ) (if deploymentCandidates == [ ] then identityFallbackCandidates else deploymentCandidates);
      baseCandidatesOrFallback =
        if requestedHostName != deploymentHostName && hostScopedCandidates != [ ] then
          hostScopedCandidates
        else if deploymentCandidates != [ ] then
          deploymentCandidates
        else
          identityFallbackCandidates;
      identityScopedCandidates = lib.filter matchesRequestedIdentity baseCandidatesOrFallback;
    in
    if runtimeRole == null then
      identityScopedCandidates
    else
      lib.filter (
        unitName: base.roleForUnit { inherit cpm inventory unitName file; } == runtimeRole
      ) identityScopedCandidates;
}
