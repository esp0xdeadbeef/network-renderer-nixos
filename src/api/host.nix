{
  lib,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
  mapHostModel,
  renderHostNetwork,
}:
let
  buildFromControlPlane =
    {
      controlPlaneOut,
      boxName,
    }:
    let
      model = normalizeControlPlane controlPlaneOut;
      deploymentHost = selectDeploymentHost {
        inherit model;
        boxName = boxName;
      };
      hostModel = mapHostModel {
        boxName = deploymentHost.name;
        deploymentHostDef = deploymentHost.definition;
      };
    in
    renderHostNetwork hostModel;
in
{
  build =
    {
      intentPath ? null,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      boxName,
      ...
    }:
    buildFromControlPlane {
      controlPlaneOut = buildControlPlaneOutput {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      };
      inherit boxName;
    };

  buildFromControlPlane = buildFromControlPlane;
}
