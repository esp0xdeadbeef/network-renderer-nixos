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
      ) (builtins.attrNames attrs)
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

      sitePrefix = "network-artifacts/${boxName}";

      containerModel = containerModelBase // {
        containers = builtins.mapAttrs (
          containerName: container:
          let
            enterpriseName =
              if
                builtins.isAttrs controlPlaneOut
                && controlPlaneOut ? control_plane_model
                && builtins.isAttrs controlPlaneOut.control_plane_model
                && controlPlaneOut.control_plane_model ? data
                && builtins.isAttrs controlPlaneOut.control_plane_model.data
              then
                let
                  names = builtins.attrNames controlPlaneOut.control_plane_model.data;
                in
                if builtins.length names == 1 then builtins.head names else null
              else
                null;

            enterprisePrefix =
              if enterpriseName == null then
                null
              else
                let
                  enterpriseSites = controlPlaneOut.control_plane_model.data.${enterpriseName};
                  siteNames = builtins.attrNames enterpriseSites;
                in
                if builtins.length siteNames == 1 then
                  "network-artifacts/${enterpriseName}/${builtins.head siteNames}/${boxName}"
                else
                  null;

            hostPrefix = if enterprisePrefix == null then null else "${enterprisePrefix}/host-data/";

            containerPrefix =
              if enterprisePrefix == null then null else "${enterprisePrefix}/containers/${containerName}/";

            siteJsonPath =
              if enterprisePrefix == null then
                null
              else
                let
                  segments = builtins.split "/" enterprisePrefix;
                  enterpriseSegment = builtins.elemAt segments 1;
                  siteSegment = builtins.elemAt segments 2;
                in
                "network-artifacts/${enterpriseSegment}/${siteSegment}/site.json";

            siteDataJsonPath =
              if enterprisePrefix == null then
                null
              else
                let
                  segments = builtins.split "/" enterprisePrefix;
                  enterpriseSegment = builtins.elemAt segments 1;
                  siteSegment = builtins.elemAt segments 2;
                in
                "network-artifacts/${enterpriseSegment}/${siteSegment}/site-data.json";

            artifactEtc = filterAttrs (
              name: _:
              (hostPrefix != null && lib.hasPrefix hostPrefix name)
              || (containerPrefix != null && lib.hasPrefix containerPrefix name)
              || (siteJsonPath != null && name == siteJsonPath)
              || (siteDataJsonPath != null && name == siteDataJsonPath)
            ) allEtc;
          in
          container
          // {
            artifactEtc = artifactEtc;
          }
        ) containerModelBase.containers;
      };
    in
    renderContainers containerModel;
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
