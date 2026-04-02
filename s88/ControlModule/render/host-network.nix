args@{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

import ../../Unit/render/host-network.nix args
