args@{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

import ./host-runtime/default.nix args
