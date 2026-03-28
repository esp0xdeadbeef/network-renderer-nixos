{ lib, activeRoles ? { }, s88Role ? null, ... }:

let
  effectiveRoles =
    if activeRoles != { } then
      builtins.attrValues activeRoles
    else
      lib.optionals (s88Role != null) [ s88Role ];

  containerEnabled =
    lib.any
      (role:
        role ? container
        && builtins.isAttrs role.container
        && (role.container.enable or false))
      effectiveRoles;
in
{
  imports =
    [
      ./fabric-input-loader.nix
      ./host-network.nix
    ]
    ++ lib.optionals containerEnabled [
      ./container-runtime.nix
    ];
}
