args@{
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

import ./containers/default.nix args
