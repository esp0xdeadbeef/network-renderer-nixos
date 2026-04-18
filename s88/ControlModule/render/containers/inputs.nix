{
  lib,
  hostPlan ? null,
  containerModelsByHost ? null,
  containerModels ? null,
  deploymentContainers ? null,
  models ? null,
  ...
}:

let
  defaultDeploymentHostName =
    if hostPlan != null && builtins.isAttrs hostPlan && hostPlan ? deploymentHostName then
      hostPlan.deploymentHostName
    else if hostPlan != null && builtins.isAttrs hostPlan && hostPlan ? hostName then
      hostPlan.hostName
    else
      null;

  uplinks =
    if
      hostPlan != null
      && builtins.isAttrs hostPlan
      && hostPlan ? uplinks
      && builtins.isAttrs hostPlan.uplinks
    then
      hostPlan.uplinks
    else
      { };

  wanUplinkName =
    if
      hostPlan != null
      && builtins.isAttrs hostPlan
      && hostPlan ? wanUplinkName
      && builtins.isString hostPlan.wanUplinkName
    then
      hostPlan.wanUplinkName
    else
      null;

  flatModels =
    if hostPlan != null then
      import ../../mapping/container-runtime.nix {
        inherit lib hostPlan;
      }
    else
      null;

  modelsByHost =
    if containerModelsByHost != null then
      containerModelsByHost
    else if containerModels != null then
      containerModels
    else if deploymentContainers != null then
      deploymentContainers
    else if models != null then
      models
    else
      null;
in
{
  inherit
    defaultDeploymentHostName
    uplinks
    wanUplinkName
    flatModels
    modelsByHost
    ;
}
