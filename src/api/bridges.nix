{
  lib,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
  mapBridgeModel,
  renderBridgeNetwork,
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
      bridgeModel = mapBridgeModel {
        boxName = deploymentHost.name;
        deploymentHostDef = deploymentHost.definition;
      };
    in
    renderBridgeNetwork bridgeModel;
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
