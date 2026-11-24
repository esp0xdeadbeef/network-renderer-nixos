{
  lib,
  cpm,
  flakeInputs ? null,
  runtimeTarget ? { },
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalize = import ./communication-contract/normalize.nix { inherit lib; };

  inherit (normalize)
    attrPathOrNull
    firstNonEmptyAttrs
    canonicalCommunicationContract
    mergeCommunicationContracts
    ;

  logicalNode =
    if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then
      runtimeTarget.logicalNode
    else
      { };

  currentRootHint =
    if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
      logicalNode.enterprise
    else if runtimeTarget ? rootName && builtins.isString runtimeTarget.rootName then
      runtimeTarget.rootName
    else
      null;

  currentSiteHint =
    if logicalNode ? site && builtins.isString logicalNode.site then
      logicalNode.site
    else if runtimeTarget ? siteName && builtins.isString runtimeTarget.siteName then
      runtimeTarget.siteName
    else
      null;

  controlPlaneData =
    if
      cpm ? model && builtins.isAttrs cpm.model && cpm.model ? data && builtins.isAttrs cpm.model.data
    then
      cpm.model.data
    else if cpm ? data && builtins.isAttrs cpm.data then
      cpm.data
    else
      { };

  siteTreeFromRoot =
    rootValue:
    if rootValue ? site && builtins.isAttrs rootValue.site then
      rootValue.site
    else if builtins.isAttrs rootValue then
      rootValue
    else
      { };

  siteEntries = lib.concatMap (
    rootName:
    let
      siteTree = siteTreeFromRoot controlPlaneData.${rootName};
    in
    map (siteName: {
      inherit rootName siteName;
      site = siteTree.${siteName};
    }) (sortedAttrNames siteTree)
  ) (sortedAttrNames controlPlaneData);

  cpmEnvelope =
    if builtins.isAttrs cpm && builtins.isAttrs (cpm.model or null) then cpm.model else cpm;

  targetEnterprise =
    if builtins.isAttrs runtimeTarget then runtimeTarget.enterprise or null else null;

  targetSite = if builtins.isAttrs runtimeTarget then runtimeTarget.site or null else null;

  siteTree =
    let
      canonical = (cpmEnvelope.canonicalSites or { }).byEnterprise or null;
    in
    if builtins.isAttrs canonical then canonical else cpmEnvelope.data or { };

  canonicalSiteRecord =
    let
      byEnterprise = if builtins.isAttrs siteTree then siteTree else { };
    in
    if
      builtins.isAttrs byEnterprise
      && builtins.isString targetEnterprise
      && builtins.isString targetSite
      && builtins.isAttrs (byEnterprise.${targetEnterprise} or null)
      && builtins.isAttrs (byEnterprise.${targetEnterprise}.${targetSite} or null)
    then
      byEnterprise.${targetEnterprise}.${targetSite}
    else
      null;

  soleSiteRecord =
    let
      byEnterprise = if builtins.isAttrs siteTree then siteTree else { };
    in
    if !(builtins.isAttrs byEnterprise) then
      null
    else
      let
        enterprises = builtins.attrNames byEnterprise;
      in
      if builtins.length enterprises != 1 then
        null
      else
        let
          sites = builtins.attrNames (byEnterprise.${builtins.head enterprises});
        in
        if builtins.length sites == 1 then
          byEnterprise.${builtins.head enterprises}.${builtins.head sites}
        else
          null;

  currentSite =
    if canonicalSiteRecord != null then
      canonicalSiteRecord
    else if soleSiteRecord != null then
      soleSiteRecord
    else
      throw (
        "FS-540-HDS-010-SDS-010-SMS-040: cannot resolve the site record for the "
        + "firewall of runtime target '${toString (runtimeTarget.target or "<unknown>")}' "
        + "(enterprise='${toString targetEnterprise}', site='${toString targetSite}'). "
        + "The communication contract -- and every allow relation NFM authored -- lives on "
        + "that record. The renderer will not synthesise an empty policy: an empty contract "
        + "renders 'policy drop' with no allows, which silently blocks the whole site. "
        + "Supply the validated bundle's canonicalSites.byEnterprise, and make sure the "
        + "runtime target carries its enterprise and site identity from the CPM."
      );

  communicationContract = canonicalCommunicationContract currentSite;

  ownership = firstNonEmptyAttrs [
    (
      if currentSite ? ownership && builtins.isAttrs currentSite.ownership then
        currentSite.ownership
      else
        { }
    )
    (
      if communicationContract ? ownership && builtins.isAttrs communicationContract.ownership then
        communicationContract.ownership
      else
        { }
    )
  ];
in
{
  inherit
    currentSite
    communicationContract
    ownership
    ;

  inherit targetEnterprise targetSite;
}
