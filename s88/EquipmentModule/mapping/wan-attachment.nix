args@{
  lib,
  hostName,
  deploymentHostName,
  deploymentHost,
  renderHostConfig,
  cpm,
  inventory ? { },
  attachTargetsBase,
}:

import ./wan-attachment/default.nix args
