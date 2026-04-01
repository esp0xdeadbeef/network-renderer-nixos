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
  requestedHostName =
    if hostContext ? hostname && builtins.isString hostContext.hostname then
      hostContext.hostname
    else
      config.networking.hostName;

  effectiveRenderedHostNetwork =
    if renderedHostNetwork != null then
      renderedHostNetwork
    else
      import ../render/host-network.nix {
        inherit lib;
        hostName = requestedHostName;
        inherit hostContext;
        cpm = controlPlaneOut;
        inventory = globalInventory;
      };
in
{
  systemd.network.netdevs = effectiveRenderedHostNetwork.netdevs or { };
  systemd.network.networks = effectiveRenderedHostNetwork.networks or { };
}
