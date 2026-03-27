{
  config,
  pkgs,
  lib,
  outPath,
  fabricCompiled,
  globalInventory,
  boxContext,
  ...
}:

let
  hostname = config.networking.hostName;

  runtimeContext = import "${outPath}/lib/runtime-context.nix" { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  renderHostConfig =
    if boxContext ? renderHostConfig && builtins.isAttrs boxContext.renderHostConfig then
      boxContext.renderHostConfig
    else
      { };

  deploymentHostName =
    if boxContext ? deploymentHostName && builtins.isString boxContext.deploymentHostName then
      boxContext.deploymentHostName
    else
      hostname;

  hostConfig =
    if boxContext ? box && builtins.isAttrs boxContext.box then
      boxContext.box
    else
      throw ''
        container-settings:

        boxContext.box missing.
      '';

  uplinks =
    if hostConfig ? uplinks && builtins.isAttrs hostConfig.uplinks then
      hostConfig.uplinks
    else
      throw ''
        container-settings:

        inventory.deployment.hosts.${deploymentHostName}.uplinks missing.

        host config:
        ${builtins.toJSON hostConfig}
      '';

  uplinkNames = sortedAttrNames uplinks;

  wanUplinkName =
    if renderHostConfig ? wanUplink
      && builtins.isString renderHostConfig.wanUplink
      && builtins.hasAttr renderHostConfig.wanUplink uplinks
    then
      renderHostConfig.wanUplink
    else if uplinks ? upstream-core && builtins.isAttrs uplinks.upstream-core then
      "upstream-core"
    else if builtins.length uplinkNames == 1 then
      builtins.head uplinkNames
    else
      throw ''
        container-settings:

        inventory.deployment.hosts.${deploymentHostName}.uplinks WAN selection missing and fallback is ambiguous.

        Known uplinks:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ uplinkNames)}
      '';

  wanConfig = uplinks.${wanUplinkName};

  _wanBridgePresent =
    if wanConfig ? bridge && builtins.isString wanConfig.bridge then
      true
    else
      throw ''
        container-settings:

        Selected WAN uplink has no bridge.

        wan config:
        ${builtins.toJSON wanConfig}
      '';

  pppoeConfig =
    if wanConfig ? pppoe && builtins.isAttrs wanConfig.pppoe then
      wanConfig.pppoe
    else
      { enable = false; };

  pppoeEnabled =
    if pppoeConfig ? enable then
      pppoeConfig.enable
    else
      false;

  realizationNodes =
    if boxContext ? realizationNodes && builtins.isAttrs boxContext.realizationNodes then
      boxContext.realizationNodes
    else
      throw ''
        container-settings:

        boxContext.realizationNodes missing.
      '';

  pppoeBindMounts =
    if pppoeEnabled then
      {
        "/dev/ppp" = {
          hostPath = "/dev/ppp";
          isReadOnly = false;
        };

        "/run/secrets/pppoe-username" = {
          hostPath = config.sops.secrets.pppoe-username.path;
          isReadOnly = true;
        };

        "/run/secrets/pppoe-password" = {
          hostPath = config.sops.secrets.pppoe-password.path;
          isReadOnly = true;
        };
      }
    else
      { };

  attrValues = attrs: map (name: attrs.${name}) (builtins.attrNames attrs);

  realizationNodeForUnit =
    unitName:
    if builtins.hasAttr unitName realizationNodes then
      realizationNodes.${unitName}
    else
      throw ''
        container-settings:

        Missing realization node for unit '${unitName}'.

        Known realization nodes:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames realizationNodes)}
      '';

  nodeContextForUnit =
    unitName:
    runtimeContext.runtimeTargetForUnit {
      cpm = fabricCompiled;
      inherit unitName;
      file = "s88/Unit/s-router-core/container-settings.nix";
    };

  runtimeRole =
    if renderHostConfig ? runtimeRole && builtins.isString renderHostConfig.runtimeRole then
      renderHostConfig.runtimeRole
    else
      "core";

  selectedUnits =
    runtimeContext.unitNamesForRoleOnDeploymentHost {
      cpm = fabricCompiled;
      inventory = globalInventory;
      inherit deploymentHostName;
      role = runtimeRole;
      file = "s88/Unit/s-router-core/container-settings.nix";
    };

  _selectedNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        container-settings:

        No ${runtimeRole}-role runtime targets matched this machine.

        Current hostname:
        ${hostname}

        Deployment host:
        ${deploymentHostName}
      '';

  runtimeTransitBridgeForUnit =
    unitName:
    let
      realizationNode = realizationNodeForUnit unitName;
      ports =
        if realizationNode ? ports && builtins.isAttrs realizationNode.ports then
          realizationNode.ports
        else
          throw ''
            container-settings:

            realization.nodes.${unitName}.ports missing or not an attrset.

            realization node:
            ${builtins.toJSON realizationNode}
          '';

      bridgePorts =
        builtins.filter
          (
            port:
            builtins.isAttrs port
            && port ? attach
            && builtins.isAttrs port.attach
            && (port.attach.kind or null) == "bridge"
            && port.attach ? bridge
            && builtins.isString port.attach.bridge
          )
          (attrValues ports);

      directPorts =
        builtins.filter
          (
            port:
            builtins.isAttrs port
            && port ? attach
            && builtins.isAttrs port.attach
            && (port.attach.kind or null) == "direct"
            && port ? link
            && builtins.isString port.link
          )
          (attrValues ports);
    in
    if builtins.length bridgePorts == 1 then
      (builtins.head bridgePorts).attach.bridge
    else if builtins.length bridgePorts == 0 && builtins.length directPorts == 1 then
      (builtins.head directPorts).link
    else
      throw ''
        container-settings:

        Expected exactly 1 bridge-backed runtime port or exactly 1 direct-link port for unit '${unitName}'.

        bridge-backed ports:
        ${builtins.toJSON bridgePorts}

        direct-link ports:
        ${builtins.toJSON directPorts}
      '';

  containerTemplate =
    if renderHostConfig ? containerTemplate && builtins.isString renderHostConfig.containerTemplate then
      renderHostConfig.containerTemplate
    else
      "wan";

  mkContainer =
    unitName:
    let
      fabricNodeContext = nodeContextForUnit unitName;
      containerName = containerTemplate;
      containerPath = ./. + "/container-${containerTemplate}";
      transitBridge = runtimeTransitBridgeForUnit unitName;
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          "${containerName}-wan" = {
            hostBridge = wanConfig.bridge;
          };
          "${containerName}-fabric" = {
            hostBridge = transitBridge;
          };
        };

        specialArgs = {
          inherit fabricNodeContext containerName wanConfig transitBridge;
          realizationNode = realizationNodeForUnit unitName;
        };

        bindMounts = pppoeBindMounts;

        allowedDevices =
          lib.optionals pppoeEnabled [
            {
              node = "/dev/ppp";
              modifier = "rw";
            }
          ];

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        config = containerPath;
      };
    };

  containersGenerated = builtins.listToAttrs (map mkContainer selectedUnits);
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = containersGenerated;
}
