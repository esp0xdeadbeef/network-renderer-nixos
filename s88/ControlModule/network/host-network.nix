{
  config,
  lib,
  controlPlaneOut,
  globalInventory,
  hostContext ? { },
  renderedHostNetwork ? null,
  ...
}:

let
  deploymentHostName =
    if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
      hostContext.deploymentHostName
    else
      config.networking.hostName;

  effectiveRenderedHostNetwork =
    if renderedHostNetwork != null then
      renderedHostNetwork
    else
      import ./render/host-network.nix {
        inherit lib;
        hostName = deploymentHostName;
        cpm = controlPlaneOut;
        inventory = globalInventory;
      };
in
{
  systemd.network.netdevs = effectiveRenderedHostNetwork.netdevs or { };
  systemd.network.networks = effectiveRenderedHostNetwork.networks or { };
}
