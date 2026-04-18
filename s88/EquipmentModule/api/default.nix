{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ../../ControlModule/api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
