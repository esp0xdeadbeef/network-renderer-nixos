args@{ lib
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

import ./containers/default.nix args
