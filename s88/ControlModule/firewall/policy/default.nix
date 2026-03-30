{
  lib,
  roleName ? null,
  ...
}@args:

if roleName == "core" then import ./core.nix args else null
