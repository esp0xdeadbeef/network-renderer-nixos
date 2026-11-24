{
  boxName ? builtins.getEnv "BOX_NAME",
  selector ? builtins.getEnv "SELECTOR",
  intentPath ? builtins.getEnv "INTENT_PATH",
  inventoryPath ? builtins.getEnv "INVENTORY_PATH",
  system ? "x86_64-linux",
  defaults ? { },
  disabled ? { },
  ...
}:
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  cpmFlake = flake.inputs.network-control-plane-model;
  realizationModel = flake.inputs.network-realization-model;

  cpm = cpmFlake.lib.${system}.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
    validateForwardingModel = false;
    validateRuntimeModel = false;
  };

  cpmArtifact = {
    kind = "network-control-plane-artifact";
    artifactIdentity = "renderer-test-artifact";
    artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpm.control_plane_model);
    inherit (cpm) control_plane_model;
  };

  bundle = realizationModel.lib.realize {
    input = cpmArtifact;
    requestScope = {
      kind = "complete-artifact";
      identity = "renderer-test-build-containers";
    };
    rootLockIdentity = "renderer-test-flake-lock";
    producerRevision = realizationModel.rev or "uncommitted";
  };

  containers = flake.lib.containers.buildForBox {
    inherit
      boxName
      selector
      system
      defaults
      disabled
      cpm
      ;
    canonicalCollections = bundle.canonical or { };
  };
in
containers
