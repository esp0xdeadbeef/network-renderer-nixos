{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ../../Area/api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
