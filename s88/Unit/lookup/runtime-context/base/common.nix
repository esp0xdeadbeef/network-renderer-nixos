{ lib }:

{
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  controlPlaneData =
    cpm: canonicalCollections:
    let
      sites =
        (if builtins.isAttrs canonicalCollections then canonicalCollections else { }).canonicalSites or { };
    in
    if builtins.isAttrs (sites.byEnterprise or null) then
      sites.byEnterprise
    else if
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
}
