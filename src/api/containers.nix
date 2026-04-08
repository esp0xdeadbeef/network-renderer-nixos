{
  lib,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
  mapContainerModel,
  renderContainers,
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
      containerModel = mapContainerModel {
        inherit
          model
          disabled
          defaults
          ;
        boxName = deploymentHost.name;
        deploymentHostDef = deploymentHost.definition;
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
