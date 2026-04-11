{ lib }:
{
  normalizedModel,
  enterpriseName,
  siteName,
}:
let
  getAttrPathOr =
    path: default: set:
    if path == [ ] then
      set
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if !(builtins.isAttrs set) || !(builtins.hasAttr key set) then
        default
      else
        getAttrPathOr rest default (builtins.getAttr key set);

  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  json = value: builtins.toJSON value;

  resolvedEnterpriseName = ensureString "enterpriseName" enterpriseName;
  resolvedSiteName = ensureString "siteName" siteName;
  model = ensureAttrs "normalizedModel" normalizedModel;

  siteRootCandidates = [
    {
      source = "normalizedModel.siteData";
      value = getAttrPathOr [
        resolvedEnterpriseName
        resolvedSiteName
      ] null (model.siteData or { });
    }
    {
      source = "normalizedModel.fabricInputs";
      value = getAttrPathOr [
        resolvedEnterpriseName
        resolvedSiteName
      ] null (model.fabricInputs or { });
    }
    {
      source = "normalizedModel.source.forwardingOut";
      value = getAttrPathOr [
        "forwardingOut"
        resolvedEnterpriseName
        resolvedSiteName
      ] null (model.source or { });
    }
    {
      source = "normalizedModel.raw";
      value = getAttrPathOr [
        resolvedEnterpriseName
        resolvedSiteName
      ] null (model.raw or { });
    }
    {
      source = "normalizedModel.source";
      value = getAttrPathOr [
        resolvedEnterpriseName
        resolvedSiteName
      ] null (model.source or { });
    }
  ];

  pickSiteAttr =
    attrName:
    let
      populatedCandidates = lib.filter (candidate: candidate.value != null) siteRootCandidates;

      matches = lib.filter (value: value != null) (
        map (
          candidate:
          if builtins.isAttrs candidate.value && builtins.hasAttr attrName candidate.value then
            candidate.value.${attrName}
          else
            null
        ) populatedCandidates
      );
    in
    if matches == [ ] then
      throw ''
        network-renderer-nixos: site-scoped '${attrName}' is missing for '${resolvedEnterpriseName}.${resolvedSiteName}'
        siteRootCandidates=${json populatedCandidates}
      ''
    else
      ensureAttrs "site-scoped '${attrName}' for '${resolvedEnterpriseName}.${resolvedSiteName}'" (
        builtins.head matches
      );
in
{
  communicationContract = pickSiteAttr "communicationContract";
  ownership = pickSiteAttr "ownership";
}
