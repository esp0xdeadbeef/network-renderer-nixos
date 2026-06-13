# CMC: Pipeline builders (buildCompiler, buildForwarding, buildControlPlane)
# removed (CMC-NIXOS-REMOVE-INTENT-V2). Per FS-310-HDS-010-SDS-010-SMS-100,
# renderers must consume ONLY CPM output. Pipeline orchestration
# (compiler → NFM → CPM) belongs in the nixos host repo or a harness,
# NOT inside this renderer. The renderer's buildHostFromControlPlane
# accepts pre-built CPM output and skips internal pipeline compilation.
#
# This module exists as a compatibility stub. All builder functions are gone.
# The renderer requires callers to provide pre-built CPM output via
# buildHostFromControlPlane or renderDryConfig.

{ }:
{ }
