args@{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

import ../../Unit/render/host-plan.nix args
