# NOTE: vm-input-home.nix updated (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
# Previously provided intentPath/inventoryPath pointing to upstream data files.
# Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.
# Now provides cpmPath pointing to pre-built CPM JSON output.
# The pipeline (compiler→NFM→CPM) must be run separately before invoking the VM harness.

{
  boxName = "s-router-test";

  testingSpoofedHostHeadersEnabled = true;

  # cpmPath: path to pre-built CPM JSON output (built by pipeline harness, not renderer)
  cpmPath = /home/deadbeef/github/nixos/library/100-fabric-routing/outputs/control-plane.json;

  # inventory: optional inventory data (use {} if CPM carries inventory)
  inventory = { };
}
