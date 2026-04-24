let
  flake = builtins.getFlake (toString ./.);
  exampleDir = flake.inputs.network-labs.outPath + "/examples/single-wan";
in
{
  boxName = "lab-host";
  testingSpoofedHostHeadersEnabled = true;

  intentPath = exampleDir + "/intent.nix";
  inventoryPath = exampleDir + "/inventory-nixos.nix";
}
