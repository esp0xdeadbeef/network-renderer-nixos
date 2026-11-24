{
  lib,
  canonical,

  platformBinding ? null,
}:
let
  sites = canonical.canonicalSites or { };
  byEnterprise = sites.byEnterprise or { };

  canonicalTargets = (canonical.canonicalRuntimeTargets or { }).targets or [ ];

  targetsForSite =
    enterprise: siteName:
    let
      matching = builtins.filter (
        t: (t.enterprise or null) == enterprise && (t.site or null) == siteName
      ) canonicalTargets;
    in
    builtins.listToAttrs (
      map (t: {
        name = t.target or (t.logicalNode or { }).name;
        value = t;
      }) matching
    );

  siteWithCanonicalTargets =
    enterprise: siteName: siteRecord:
    let
      own = siteRecord.runtimeTargets or null;
      fromCollection = targetsForSite enterprise siteName;
    in
    if builtins.isAttrs own && own != { } then
      siteRecord
    else
      siteRecord // { runtimeTargets = fromCollection; };

  data = builtins.mapAttrs (
    enterprise: siteTree:
    builtins.mapAttrs (
      siteName: siteRecord: siteWithCanonicalTargets enterprise siteName siteRecord
    ) siteTree
  ) byEnterprise;

  bindingCategories =
    if builtins.isAttrs platformBinding then platformBinding.categories or { } else { };
  bindingDeployment =
    if builtins.isAttrs (bindingCategories.deployment or null) then
      bindingCategories.deployment
    else
      { };
  containerTargets =
    if builtins.isAttrs (bindingDeployment.containerTargets or null) then
      bindingDeployment.containerTargets
    else
      { };
  declaredHosts =
    if builtins.isAttrs (bindingDeployment.hosts or null) then bindingDeployment.hosts else { };
  bindingHosts =
    declaredHosts
    // builtins.listToAttrs (
      map (h: {
        name = h;
        value = declaredHosts.${h} or { };
      }) (builtins.attrNames containerTargets)
    );

  deploymentHosts = bindingHosts;
  deployment = bindingDeployment;
in
{

  inherit (canonical) canonicalRoutes canonicalForwarding canonicalOverlays;
  model = {
    inherit data;
  };
  inherit deploymentHosts deployment;

  canonical = canonical;
}
