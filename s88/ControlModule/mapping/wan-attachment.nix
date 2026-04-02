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

import ../../EquipmentModule/mapping/wan-attachment.nix args
