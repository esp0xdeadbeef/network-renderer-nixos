{
  lib,
  hostPlan ? null,
  cpm ? null,
  inventory ? { },
  debugEnabled ? false,
  containerModelsByHost ? null,
  containerModels ? null,
  deploymentContainers ? null,
  models ? null,
  ...
}:

let
  inputs = import ./inputs.nix {
    inherit
      lib
      hostPlan
      containerModelsByHost
      containerModels
      deploymentContainers
      models
      ;
  };

  renderModel = model: import ./mapping.nix { inherit lib model; };

  firewallArgForModel =
    renderedModel:
    import ./firewall.nix {
      inherit
        lib
        cpm
        inventory
        renderedModel
        ;
      uplinks = inputs.uplinks;
    };

  emitContainer =
    deploymentHostName: containerName: model:
    let
      renderedModel = renderModel model;
      firewallArg = firewallArgForModel renderedModel;
    in
    import ./emission.nix {
      inherit
        lib
        debugEnabled
        deploymentHostName
        containerName
        renderedModel
        firewallArg
        ;
      uplinks = inputs.uplinks;
      wanUplinkName = inputs.wanUplinkName;
    };

  renderFlatContainers =
    containerModelsFlat:
    builtins.mapAttrs (
      containerName: model:
      emitContainer (
        if model ? deploymentHostName && builtins.isString model.deploymentHostName then
          model.deploymentHostName
        else
          inputs.defaultDeploymentHostName
      ) containerName model
    ) containerModelsFlat;

  renderNestedContainers =
    nestedModels:
    lib.mapAttrs (
      deploymentHostName: deploymentHostContainers:
      builtins.mapAttrs (
        containerName: model: emitContainer deploymentHostName containerName model
      ) deploymentHostContainers
    ) nestedModels;
in
if inputs.flatModels != null then
  renderFlatContainers inputs.flatModels
else if inputs.modelsByHost != null then
  renderNestedContainers inputs.modelsByHost
else
  { }
