{
  lib,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
}:
let
  buildHostFromControlPlane =
    {
      controlPlaneOut,
      selector,
      file ? null,
    }:
    let
      model = normalizeControlPlane controlPlaneOut;
      deploymentHost = selectDeploymentHost {
        inherit model;
        boxName = selector;
      };
    in
    {
      inherit file selector;
      globalInventory = model.globalInventory;
      fabricInputs = model.fabricInputs;
      compilerOut =
        if model.source ? compilerOut && builtins.isAttrs model.source.compilerOut then
          model.source.compilerOut
        else
          { };
      forwardingOut =
        if model.source ? forwardingOut && builtins.isAttrs model.source.forwardingOut then
          model.source.forwardingOut
        else
          { };
      controlPlaneOut = controlPlaneOut;

      hostContext = {
        boxName = selector;
        hostName = selector;
        deploymentHostName = deploymentHost.name;
        deploymentHost = deploymentHost.definition;
        file = file;
      };
    };
in
{
  buildControlPlaneFromPaths =
    {
      intentPath ? null,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
    }:
    buildControlPlaneOutput {
      inherit
        intentPath
        inventoryPath
        intent
        inventory
        ;
    };

  buildHostFromControlPlane = buildHostFromControlPlane;

  buildHostFromPaths =
    {
      selector,
      file ? null,
      intentPath ? null,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
    }:
    buildHostFromControlPlane {
      controlPlaneOut = buildControlPlaneOutput {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      };
      inherit
        selector
        file
        ;
    };
}
