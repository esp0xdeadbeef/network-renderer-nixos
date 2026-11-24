args@{
  lib,
  repoPath,
  hostPlan ? null,
  cpm ? null,
  source ? { },
  debugEnabled ? false,
  containerModelsByHost ? null,
  containerModels ? null,
  deploymentContainers ? null,
  models ? null,
  ...
}:

let
  canonicalCollection =
    name: default:
    let
      fromBundle = (args.canonicalCollections or { }).${name} or null;
    in
    if fromBundle != null then
      fromBundle
    else
      let
        envelope =
          if builtins.isAttrs (args.cpm.control_plane_model or null) then
            args.cpm.control_plane_model
          else
            args.cpm;
      in
      if builtins.isAttrs envelope then envelope.${name} or default else default;

in
import ./containers/default.nix (
  args
  // {

    canonicalRoutes = canonicalCollection "canonicalRoutes" [ ];
    canonicalSites = canonicalCollection "canonicalSites" { };
    canonicalForwarding = canonicalCollection "canonicalForwarding" { };

    canonicalRuntimeTargets = canonicalCollection "canonicalRuntimeTargets" { };
  }
)
