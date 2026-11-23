{
  repoRoot,
  system ? "x86_64-linux",
}:
let
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  labs = flake.inputs.network-labs.outPath;
  example = labs + "/examples/wireguard-provider-overlay";

  cpm = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
    inputPath = example + "/intent.nix";
    inventoryPath = example + "/inventory-nixos.nix";
  };
  canonical = cpm.control_plane_model.canonicalRoutes;

  hostModule = flake.lib.renderer.hostModule {
    inherit lib cpm;
    inherit system;
    hostName = "s-router-nixos";
    selectorFile = "tests/FS-310-HDS-020-SDS-010-SMS-060.sh";
  };
  evaluated = lib.nixosSystem {
    inherit system;
    modules = [ hostModule ];
  };
  containers = evaluated.config.containers or { };
in
{

  loses = lib.concatMap (
    containerName:
    let
      nets = (containers.${containerName}.config.systemd.network.networks or { });
      onInterface =
        ifName:
        builtins.map (r: r.Destination or "") (
          builtins.filter (r: (r.Table or null) != null) ((nets."10-${ifName}" or { }).routes or [ ])
        );
    in
    map (c: "${containerName}: ${c.runtimeIfName} ${c.dst}") (
      builtins.filter (
        c: builtins.isString c.dst && !(builtins.elem c.dst (onInterface c.runtimeIfName))
      ) canonical
    )
  ) (builtins.attrNames containers);
}
