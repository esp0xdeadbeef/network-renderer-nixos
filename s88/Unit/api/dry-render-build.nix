{ selectors
, renderDryConfig
,
}:

# CMC-NIXOS-REMOVE-INTENT-V2: Pipeline builders removed.
# Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM output.
# The renderer must NOT run compiler→NFM→CPM internally via filesystem paths.
# Pipeline orchestration belongs in a harness or host repo, not the renderer.
# Use renderDryConfig with pre-built CPM output instead.
#
# This module is a compatibility stub — the renderer requires pre-built CPM.
# buildAndRenderFromPaths was removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).

let
  # Placeholder: renderer now requires pre-built CPM, not file paths.
  # Callers should use renderDryConfig directly with cpm + inventory objects.
in
{
  # buildAndRenderFromPaths removed — renderer no longer discovers intent/inventory from disk.
}
