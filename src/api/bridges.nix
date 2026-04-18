{
  lib,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
  mapBridgeModel,
  renderBridgeNetwork,
  artifacts,
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
      renderedBridges = renderBridgeNetwork bridgeModel;
      artifactModule = artifacts.controlPlaneSplitFromControlPlane {
        inherit controlPlaneOut;
        fileName = "control-plane-model.json";
        directory = "network-artifacts";
      };
    in
    lib.recursiveUpdate renderedBridges artifactModule;
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
