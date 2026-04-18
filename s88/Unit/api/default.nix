{
  lib,
  repoRoot ? ../../..,
  flakeInputs ? { },
}:

import ../../EquipmentModule/api/default.nix {
  inherit
    lib
    repoRoot
    flakeInputs
    ;
}
