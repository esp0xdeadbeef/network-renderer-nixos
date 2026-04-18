{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ../../Site/api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
