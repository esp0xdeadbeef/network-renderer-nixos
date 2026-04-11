{
  lib,
  helpers,
}:
controlPlaneOut:
let
  source =
    if builtins.isAttrs controlPlaneOut then
      controlPlaneOut
    else
      { control_plane_model = controlPlaneOut; };

  root =
    if builtins.hasAttr "control_plane_model" source && builtins.isAttrs source.control_plane_model then
      source.control_plane_model
    else if
      builtins.hasAttr "controlPlaneModel" source && builtins.isAttrs source.controlPlaneModel
    then
      source.controlPlaneModel
    else
      source;

  inventoryRoot =
    if source ? globalInventory && builtins.isAttrs source.globalInventory then
      source.globalInventory
    else if source ? inventory && builtins.isAttrs source.inventory then
      source.inventory
    else
      { };

  fabricInputs = if source ? fabricInputs then source.fabricInputs else { };

  pick =
    roots: paths: default:
    let
      values = lib.concatMap (
        currentRoot:
        lib.concatMap (
          path:
          let
            value = helpers.getAttrPathOr path null currentRoot;
          in
          if value == null then [ ] else [ value ]
        ) paths
      ) roots;
    in
    if values == [ ] then default else builtins.head values;

  deploymentHosts =
    pick
      [
        inventoryRoot
        root
        source
      ]
      [
        [
          "deployment"
          "hosts"
        ]
        [ "hosts" ]
      ]
      { };

  realizationNodes =
    pick
      [
        inventoryRoot
        root
        source
      ]
      [
        [
          "realization"
          "nodes"
        ]
        [ "nodes" ]
        [ "realizedNodes" ]
      ]
      { };

  renderHosts =
    pick
      [
        inventoryRoot
        root
        source
      ]
      [
        [
          "render"
          "hosts"
        ]
        [ "renderHosts" ]
      ]
      { };

  endpoints =
    pick
      [
        root
        source
      ]
      [
        [ "endpoints" ]
      ]
      { };

  meta =
    pick
      [
        root
        source
      ]
      [
        [ "meta" ]
      ]
      { };

  siteData = if root ? data then helpers.ensureAttrs "control_plane_model.data" root.data else { };
in
{
  source = source;
  raw = root;
  fabricInputs = fabricInputs;
  globalInventory = helpers.ensureAttrs "globalInventory" inventoryRoot;
  meta = helpers.ensureAttrs "control_plane_model.meta" meta;
  endpoints = helpers.ensureAttrs "control_plane_model.endpoints" endpoints;
  deploymentHosts = helpers.ensureAttrs "deployment.hosts" deploymentHosts;
  realizationNodes = helpers.ensureAttrs "realization.nodes" realizationNodes;
  renderHosts = helpers.ensureAttrs "render.hosts" renderHosts;
  siteData = siteData;
}
