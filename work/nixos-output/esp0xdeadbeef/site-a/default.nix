{ ... }:
{
  imports = [
    ./s-router-access-admin.nix
    ./s-router-access-client.nix
    ./s-router-access-mgmt.nix
    ./s-router-core-nebula.nix
    ./s-router-core-wan.nix
    ./s-router-policy.nix
    ./s-router-upstream-selector.nix
  ];
}
