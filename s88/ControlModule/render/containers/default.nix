{ lib
, repoPath
, hostPlan ? null
, cpm ? null
, source ? { }
, debugEnabled ? false
, containerModelsByHost ? null
, containerModels ? null
, deploymentContainers ? null
, models ? null
, ...
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

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

  sortedNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  renderModel =
    model:
    import ./mapping.nix { inherit lib model; };

  firewallArgForModel =
    renderedModel:
    import ./firewall.nix {
      inherit
        lib
        cpm
        source
        renderedModel
        ;
      uplinks = inputs.uplinks;
    };

  alarmModelForRenderedModel =
    renderedModel: firewallArg:
    import ./alarms.nix {
      inherit
        lib
        cpm
        renderedModel
        ;
      uplinks = inputs.uplinks;
      interfaceView = (firewallArg.lookup or { }).interfaceView or null;
      forwardingIntent = (firewallArg.lookup or { }).forwardingIntent or null;
      communication = (firewallArg.lookup or { }).communication or null;
      endpointMap = (firewallArg.lookup or { }).endpointMap or null;
    };

  emitContainer =
    deploymentHostName: containerName: model:
    let
      renderedModel = trace.emit "containers:${deploymentHostName}:${containerName}:model" (renderModel model);
      firewallArg = trace.emit "containers:${deploymentHostName}:${containerName}:firewall" (firewallArgForModel renderedModel);
      alarmModel = trace.emit "containers:${deploymentHostName}:${containerName}:alarms" (
        alarmModelForRenderedModel renderedModel firewallArg
      );
    in
    trace.emit "containers:${deploymentHostName}:${containerName}:emission" (import ./emission.nix {
      inherit
        lib
        debugEnabled
        deploymentHostName
        containerName
        renderedModel
        firewallArg
        alarmModel
        ;
      uplinks = inputs.uplinks;
      wanUplinkName = inputs.wanUplinkName;
    });

  renderFlatContainers =
    containerModelsFlat:
    builtins.mapAttrs
      (
        containerName: model:
        emitContainer
          (
            if model ? deploymentHostName && builtins.isString model.deploymentHostName then
              model.deploymentHostName
            else
              inputs.defaultDeploymentHostName
          )
          containerName
          model
      )
      containerModelsFlat;

  renderNestedContainers =
    nestedModels:
    lib.mapAttrs
      (
        deploymentHostName: deploymentHostContainers:
        builtins.mapAttrs
          (
            containerName: model: emitContainer deploymentHostName containerName model
          )
          deploymentHostContainers
      )
      nestedModels;
in
if inputs.flatModels != null then
  renderFlatContainers inputs.flatModels
else if inputs.modelsByHost != null then
  renderNestedContainers inputs.modelsByHost
else
  { }
