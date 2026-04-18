{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ../../ProcessCell/api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
