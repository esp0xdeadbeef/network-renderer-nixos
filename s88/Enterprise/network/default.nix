{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ../../CM/network/api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
