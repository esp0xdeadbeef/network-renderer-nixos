{ lib }:
{
  model,
  boxName,
}:
if builtins.hasAttr boxName model.deploymentHosts then
  {
    name = boxName;
    definition = model.deploymentHosts.${boxName};
  }
else
  throw "network-renderer-nixos: deployment host '${boxName}' is missing from control-plane output"
