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

      _renderedArtifacts = artifacts.controlPlaneSplitFromControlPlane {
        inherit controlPlaneOut;
        fileName = "control-plane-model.json";
        directory = "network-artifacts";
      };
    in
    renderContainers containerModelBase;
in
{
  buildForBox =
    {
      intentPath ? null,
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
