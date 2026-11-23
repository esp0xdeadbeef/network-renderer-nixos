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

      octets = addr: builtins.filter builtins.isString (builtins.split "[.]" addr);
      normalise =
        dst:
        let
          parts = builtins.filter builtins.isString (builtins.split "/" dst);
          addr = builtins.head parts;
          len = if builtins.length parts > 1 then builtins.elemAt parts 1 else "";
          o = octets addr;
        in
        if len == "31" && builtins.length o == 4 then
          "${builtins.elemAt o 0}.${builtins.elemAt o 1}.${builtins.elemAt o 2}."
          + "${toString (builtins.bitAnd (builtins.fromJSON (builtins.elemAt o 3)) 1)}/31"
        else
          dst;

      onInterface =
        ifName:
        builtins.map (r: normalise (r.Destination or "")) ((nets."10-${ifName}" or { }).routes or [ ]);
      renderableInterfaces = builtins.map (n: lib.removePrefix "10-" n) (
        builtins.filter (n: lib.hasPrefix "10-" n) (builtins.attrNames nets)
      );
    in
    map (c: "${containerName}: ${c.runtimeIfName} ${c.dst}") (
      builtins.filter (
        c:
        builtins.isString c.dst
        && builtins.elem c.runtimeIfName renderableInterfaces
        && !(builtins.elem (normalise c.dst) (onInterface c.runtimeIfName))
      ) canonical
    )
  ) (builtins.attrNames containers);
}
