{
  lib,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
  mapHostModel,
  renderHostNetwork,
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
      hostModel = mapHostModel {
        boxName = deploymentHost.name;
        deploymentHostDef = deploymentHost.definition;
      };
      renderedHost = renderHostNetwork hostModel;
      artifactModule = artifacts.controlPlaneSplitFromControlPlane {
        inherit controlPlaneOut;
        fileName = "control-plane-model.json";
        directory = "network-artifacts";
      };
    in
    lib.recursiveUpdate renderedHost artifactModule;
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
