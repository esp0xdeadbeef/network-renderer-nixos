{ lib }:

{
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  controlPlaneData =
    cpm:
    let
      model = if builtins.isAttrs cpm && builtins.isAttrs (cpm.model or null) then cpm.model else cpm;
      fromModel = (if builtins.isAttrs model then model else { }).canonicalSites or { };
    in
    if builtins.isAttrs (fromModel.byEnterprise or null) then
      fromModel.byEnterprise
    else if builtins.isAttrs (model.data or null) then
      model.data
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
