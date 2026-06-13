# NOTE: build-cpm-from-paths.nix removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
# Previously used buildControlPlaneFromPaths with INTENT_PATH/INVENTORY_PATH env vars.
# Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM output.
# Pipeline orchestration (compiler→NFM→CPM) belongs in the host repo or a harness,
# NOT in the renderer.
#
# To build CPM from intent/inventory, use the pipeline in the host repo:
#   nix build .#pipeline --argstr intentPath ... --argstr inventoryPath ...
#
# Or use the renderer's builder functions directly:
#   let
#     intent = import ./intent.nix;
#     inventory = import ./inventory.nix;
#     compiler = renderer.buildCompiler { inherit intent; };
#     forwarding = renderer.buildForwarding { compilerOut = compiler; };
#     cpm = renderer.buildControlPlane { forwardingOut = forwarding; inherit inventory; };
#   in cpm

throw ''
  build-cpm-from-paths.nix has been removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
  Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.
  Pipeline orchestration (compiler→NFM→CPM) must run in the host repo, not the renderer.
  See flake.nix for the updated CPM-based hostModule API.
''
