{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ../../ControlModule/network/api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
