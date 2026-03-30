{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ./api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
