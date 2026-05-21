{ lib
, cpm
, flakeInputs ? null
, runtimeTarget ? { }
,
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
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? data
      && builtins.isAttrs cpm.control_plane_model.data
    then
      cpm.control_plane_model.data
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

  siteEntries = lib.concatMap
    (
      rootName:
      let
        siteTree = siteTreeFromRoot controlPlaneData.${rootName};
      in
      map
        (siteName: {
          inherit rootName siteName;
          site = siteTree.${siteName};
        })
        (sortedAttrNames siteTree)
    )
    (sortedAttrNames controlPlaneData);

  hintedSiteEntries = lib.filter
    (
      entry:
      (currentRootHint == null || entry.rootName == currentRootHint)
      && (currentSiteHint == null || entry.siteName == currentSiteHint)
    )
    siteEntries;

  siteNameMatches =
    if currentSiteHint == null then
      [ ]
    else
      lib.filter (entry: entry.siteName == currentSiteHint) siteEntries;

  directSiteEntry =
    if currentRootHint != null && currentSiteHint != null then
      let
        rootValue = attrPathOrNull controlPlaneData [ currentRootHint ];
        siteTree = if builtins.isAttrs rootValue then siteTreeFromRoot rootValue else { };
      in
      if builtins.hasAttr currentSiteHint siteTree then
        {
          rootName = currentRootHint;
          siteName = currentSiteHint;
          site = siteTree.${currentSiteHint};
        }
      else
        null
    else
      null;

  currentSiteEntry =
    if directSiteEntry != null then
      directSiteEntry
    else if builtins.length hintedSiteEntries == 1 then
      builtins.head hintedSiteEntries
    else if builtins.length siteNameMatches == 1 then
      builtins.head siteNameMatches
    else
      null;

  currentRootName = if currentSiteEntry != null then currentSiteEntry.rootName else currentRootHint;

  currentSiteName = if currentSiteEntry != null then currentSiteEntry.siteName else currentSiteHint;

  currentSite = if currentSiteEntry != null then currentSiteEntry.site else { };

  forwardingModel =
    if cpm ? forwardingModel && builtins.isAttrs cpm.forwardingModel then
      cpm.forwardingModel
    else if
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? forwardingModel
      && builtins.isAttrs cpm.control_plane_model.forwardingModel
    then
      cpm.control_plane_model.forwardingModel
    else
      { };

  forwardingSite =
    let
      candidate =
        if currentRootName != null && currentSiteName != null then
          attrPathOrNull forwardingModel [
            "enterprise"
            currentRootName
            "site"
            currentSiteName
          ]
        else
          null;
    in
    if builtins.isAttrs candidate then candidate else { };

  communicationContract = firstNonEmptyAttrs [
    (
      if currentSite ? communicationContract && builtins.isAttrs currentSite.communicationContract then
        mergeCommunicationContracts currentSite currentSite.communicationContract
      else
        canonicalCommunicationContract currentSite
    )
    (
      if
        forwardingSite ? communicationContract && builtins.isAttrs forwardingSite.communicationContract
      then
        mergeCommunicationContracts forwardingSite forwardingSite.communicationContract
      else
        canonicalCommunicationContract forwardingSite
    )
  ];

  ownership = firstNonEmptyAttrs [
    (
      if currentSite ? ownership && builtins.isAttrs currentSite.ownership then
        currentSite.ownership
      else
        { }
    )
    (
      if forwardingSite ? ownership && builtins.isAttrs forwardingSite.ownership then
        forwardingSite.ownership
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
    currentRootName
    currentSiteName
    currentSite
    forwardingModel
    forwardingSite
    communicationContract
    ownership
    ;
}
