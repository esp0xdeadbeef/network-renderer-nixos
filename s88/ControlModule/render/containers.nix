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

import ./containers/default.nix (
  args
  // {

    canonicalRoutes =
      let
        envelope =
          if builtins.isAttrs (cpm.control_plane_model or null) then cpm.control_plane_model else cpm;
      in
      if builtins.isAttrs envelope then envelope.canonicalRoutes or [ ] else [ ];

    canonicalSites =
      let
        envelope =
          if builtins.isAttrs (cpm.control_plane_model or null) then cpm.control_plane_model else cpm;
      in
      if builtins.isAttrs envelope then envelope.canonicalSites or { } else { };
    canonicalForwarding =
      let
        envelope =
          if builtins.isAttrs (cpm.control_plane_model or null) then cpm.control_plane_model else cpm;
      in
      if builtins.isAttrs envelope then envelope.canonicalForwarding or { } else { };
  }
)
