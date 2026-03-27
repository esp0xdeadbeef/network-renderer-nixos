{ lib, outPath, config, globalInventory, ... }:

let
  inventory = globalInventory;
  hostname = config.networking.hostName;

  renderHosts =
    if inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  renderHostConfig =
    if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
      renderHosts.${hostname}
    else
      { };

  deploymentHosts =
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      abort "host-config/network.nix: inventory.deployment.hosts missing";

  deploymentHostNames = lib.sort builtins.lessThan (builtins.attrNames deploymentHosts);

  deploymentHostName =
    if renderHostConfig ? deploymentHost
      && builtins.isString renderHostConfig.deploymentHost
      && builtins.hasAttr renderHostConfig.deploymentHost deploymentHosts
    then
      renderHostConfig.deploymentHost
    else if builtins.hasAttr hostname deploymentHosts then
      hostname
    else if builtins.length deploymentHostNames == 1 then
      builtins.head deploymentHostNames
    else
      abort ''
        host-config/network.nix: no deployment host mapping for '${hostname}'

        known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';

  rendered = import ../lib/renderer/render-host-network.nix {
    inherit lib inventory;
    hostName = deploymentHostName;
  };
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs = rendered.netdevs;
  systemd.network.networks = rendered.networks;
}
