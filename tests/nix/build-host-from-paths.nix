{
  selector ? builtins.getEnv "SELECTOR",
  intentPath ? builtins.getEnv "INTENT_PATH",
  inventoryPath ? builtins.getEnv "INVENTORY_PATH",
  system ? "x86_64-linux",
  ...
}@args:
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  cpmFlake = flake.inputs.network-control-plane-model;
  realizationModel = flake.inputs.network-realization-model;

  cpmOut = cpmFlake.lib.${system}.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
    validateForwardingModel = false;
    validateRuntimeModel = false;
  };

  bundle = realizationModel.lib.realize {
    input = {
      kind = "network-control-plane-artifact";
      artifactIdentity = "renderer-test-build-host-artifact";
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpmOut.control_plane_model);
      inherit (cpmOut) control_plane_model;
    };
    requestScope = {
      kind = "complete-artifact";
      identity = "renderer-test-build-host";
    };
    rootLockIdentity = "renderer-test-flake-lock";
    producerRevision = realizationModel.rev or "uncommitted";
  };

  hostBuild = flake.lib.renderer.buildHostFromControlPlane {
    controlPlaneOut = cpmOut;

    canonicalCollectionsInput = bundle.canonical or { };
    inherit selector system;
    containerDefaults = args.containerDefaults or { };
    disabled = args.disabled or { };
  };
in
hostBuild
