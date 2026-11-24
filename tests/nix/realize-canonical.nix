{
  flake,
  cpm,
  identity,
}:
let
  realizationModel = flake.inputs.network-realization-model;

  artifact = {
    kind = "network-control-plane-artifact";
    artifactIdentity = identity;
    artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpm.control_plane_model);
    inherit (cpm) control_plane_model;
  };

  bundle = realizationModel.lib.realize {
    input = artifact;
    requestScope = {
      kind = "complete-artifact";
      inherit identity;
    };
    rootLockIdentity = "${identity}-flake-lock";
    producerRevision = realizationModel.rev or "uncommitted";
  };
in
bundle.canonical or { }
