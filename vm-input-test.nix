# NOTE: vm-input-test.nix updated (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
# Previously constructed intentPath/inventoryPath pointing to upstream data files.
# Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.
# Now provides cpmPath pointing to pre-built CPM JSON output.
# The pipeline (compiler→NFM→CPM) must be run separately before invoking the VM harness.

let
  flake = builtins.getFlake (toString ./.);
  exampleDir = flake.inputs.network-labs.outPath + "/examples/single-wan";
in
{
  boxName = "lab-host";
  testingSpoofedHostHeadersEnabled = true;

  # cpmPath: path to pre-built CPM JSON output (built by pipeline harness, not renderer)
  cpmPath = exampleDir + "/outputs/control-plane.json";

  # inventory: optional inventory data (use {} if CPM carries inventory)
  inventory = { };
}
