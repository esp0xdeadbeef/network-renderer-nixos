args@{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

import ../../Unit/lookup/host-runtime.nix args
