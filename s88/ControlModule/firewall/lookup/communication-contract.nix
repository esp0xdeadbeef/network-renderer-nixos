{
  lib,
  cpm,
  flakeInputs ? null,
  topology ? null,
}:

let
  isNonEmptyAttrs = value: builtins.isAttrs value && value != { };

  attrPathOrNull =
    attrs: path:
    if path == [ ] then
      attrs
    else if !builtins.isAttrs attrs then
      null
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if builtins.hasAttr key attrs then attrPathOrNull attrs.${key} rest else null;

  firstNonEmptyAttrs =
    candidates:
    let
      matches = lib.filter isNonEmptyAttrs candidates;
    in
    if matches == [ ] then { } else builtins.head matches;

  canonicalCommunicationContract =
    attrs:
    if
      builtins.isAttrs attrs
      && (
        (attrs ? relations && builtins.isList attrs.relations)
        || (attrs ? allowedRelations && builtins.isList attrs.allowedRelations)
        || (attrs ? services && builtins.isList attrs.services)
        || (attrs ? trafficTypes && builtins.isList attrs.trafficTypes)
        || (attrs ? interfaceTags && builtins.isAttrs attrs.interfaceTags)
        || (attrs ? ownership && builtins.isAttrs attrs.ownership)
      )
    then
      {
        relations =
          if attrs ? relations && builtins.isList attrs.relations then
            attrs.relations
          else if attrs ? allowedRelations && builtins.isList attrs.allowedRelations then
            attrs.allowedRelations
          else
            [ ];
        services = if attrs ? services && builtins.isList attrs.services then attrs.services else [ ];
        trafficTypes =
          if attrs ? trafficTypes && builtins.isList attrs.trafficTypes then attrs.trafficTypes else [ ];
        interfaceTags =
          if attrs ? interfaceTags && builtins.isAttrs attrs.interfaceTags then attrs.interfaceTags else { };
        ownership = if attrs ? ownership && builtins.isAttrs attrs.ownership then attrs.ownership else { };
      }
    else
      { };

  topologyCurrent =
    if
      topology != null
      && builtins.isAttrs topology
      && topology ? current
      && builtins.isAttrs topology.current
    then
      topology.current
    else
      { };

  currentSite =
    if
      topology != null
      && builtins.isAttrs topology
      && topology ? currentSite
      && builtins.isAttrs topology.currentSite
    then
      topology.currentSite
    else if topologyCurrent ? site && builtins.isAttrs topologyCurrent.site then
      topologyCurrent.site
    else
      { };

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

  currentRootName =
    if topology != null && builtins.isAttrs topology && topology ? currentRootName then
      topology.currentRootName
    else
      null;

  currentSiteName =
    if topology != null && builtins.isAttrs topology && topology ? currentSiteName then
      topology.currentSiteName
    else
      null;

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
        canonicalCommunicationContract currentSite.communicationContract
      else
        { }
    )
    (canonicalCommunicationContract currentSite)
    (
      if
        forwardingSite ? communicationContract && builtins.isAttrs forwardingSite.communicationContract
      then
        canonicalCommunicationContract forwardingSite.communicationContract
      else
        { }
    )
    (canonicalCommunicationContract forwardingSite)
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
