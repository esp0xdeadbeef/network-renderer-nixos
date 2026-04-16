{
  lib,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
  mapContainerModel,
  renderContainers,
  artifacts,
}:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  filterAttrs =
    predicate: attrs:
    builtins.listToAttrs (
      lib.concatMap (
        name:
        let
          value = attrs.${name};
        in
        if predicate name value then
          [
            {
              inherit name value;
            }
          ]
        else
          [ ]
      ) (sortedAttrNames attrs)
    );

  ensureSingleSiteContext =
    controlPlaneOut:
    let
      sourceRoot =
        if
          builtins.isAttrs controlPlaneOut
          && controlPlaneOut ? control_plane_model
          && builtins.isAttrs controlPlaneOut.control_plane_model
        then
          controlPlaneOut.control_plane_model
        else
          throw "network-renderer-nixos: expected control_plane_model in controlPlaneOut for container artifact selection";

      siteData =
        if sourceRoot ? data && builtins.isAttrs sourceRoot.data then
          sourceRoot.data
        else
          throw "network-renderer-nixos: control_plane_model.data is missing for container artifact selection";

      enterpriseNames = sortedAttrNames siteData;

      _singleEnterprise =
        if builtins.length enterpriseNames == 1 then
          true
        else
          throw "network-renderer-nixos: expected exactly one enterprise in control-plane output for container artifact selection";

      enterpriseName = builtins.head enterpriseNames;

      enterpriseSites = siteData.${enterpriseName};

      siteNames =
        if builtins.isAttrs enterpriseSites then
          sortedAttrNames enterpriseSites
        else
          throw "network-renderer-nixos: expected enterprise site set for container artifact selection";

      _singleSite =
        if builtins.length siteNames == 1 then
          true
        else
          throw "network-renderer-nixos: expected exactly one site in control-plane output for container artifact selection";

      siteName = builtins.head siteNames;
    in
    builtins.seq _singleEnterprise (
      builtins.seq _singleSite {
        inherit
          enterpriseName
          siteName
          ;
      }
    );

  buildForBoxFromControlPlane =
    {
      controlPlaneOut,
      boxName,
      disabled ? { },
      defaults ? { },
    }:
    let
      model = normalizeControlPlane controlPlaneOut;

      deploymentHost = selectDeploymentHost {
        inherit model;
        boxName = boxName;
      };

      containerModelBase = mapContainerModel {
        inherit
          model
          disabled
          defaults
          ;
        boxName = deploymentHost.name;
        deploymentHostDef = deploymentHost.definition;
      };

      siteContext = ensureSingleSiteContext controlPlaneOut;

      renderedArtifacts = artifacts.controlPlaneSplitFromControlPlane {
        inherit controlPlaneOut;
        fileName = "control-plane-model.json";
        directory = "network-artifacts";
      };

      allEtc =
        if
          renderedArtifacts ? environment
          && builtins.isAttrs renderedArtifacts.environment
          && renderedArtifacts.environment ? etc
          && builtins.isAttrs renderedArtifacts.environment.etc
        then
          renderedArtifacts.environment.etc
        else
          { };

      enterpriseSitePrefix = "network-artifacts/${siteContext.enterpriseName}/${siteContext.siteName}";

      hostPrefix = "${enterpriseSitePrefix}/${boxName}/host-data/";
    in
    renderContainers (
      containerModelBase
      // {
        containers = builtins.mapAttrs (
          containerName: container:
          let
            containerPrefix = "${enterpriseSitePrefix}/${boxName}/containers/${containerName}/";

            selectedArtifactEtc = filterAttrs (
              name: _:
              name == "${enterpriseSitePrefix}/site.json"
              || name == "${enterpriseSitePrefix}/site-data.json"
              || lib.hasPrefix hostPrefix name
              || lib.hasPrefix containerPrefix name
            ) allEtc;
          in
          container
          // {
            artifactEtc = selectedArtifactEtc;
          }
        ) containerModelBase.containers;
      }
    );
in
{
  buildForBox =
    {
      intentPath,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      boxName,
      disabled ? { },
      defaults ? { },
      ...
    }:
    buildForBoxFromControlPlane {
      controlPlaneOut = buildControlPlaneOutput {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      };
      inherit
        boxName
        disabled
        defaults
        ;
    };

  buildForBoxFromControlPlane = buildForBoxFromControlPlane;
}
