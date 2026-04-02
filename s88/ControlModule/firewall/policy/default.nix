{
  roleName ? null,
  ...
}@args:

if roleName == "access" then
  import ./access.nix args
else if roleName == "core" then
  import ./core.nix args
else if roleName == "policy" then
  import ./policy.nix args
else if roleName == "upstream-selector" then
  import ./upstream-selector.nix args
else
  null
