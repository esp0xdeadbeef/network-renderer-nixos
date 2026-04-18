{ lib, pkgs, ... }:

let
  inherit (lib)
    all
    attrNames
    concatLists
    filter
    foldl'
    genAttrs
    hasAttrByPath
    isAttrs
    isList
    isString
    mapAttrs
    mapAttrsToList
    mkForce
    nameValuePair
    optional
    optionalAttrs
    stringLength
    ;

  fail = msg: throw "network-renderer-nixos: ${msg}";

  isNonEmptyString = value: isString value && stringLength value > 0;

  vmInput = import ./vm-input-test.nix;
  inventory = import vmInput.inventoryPath;

  realizationNodes =
    if
      inventory ? realization && inventory.realization ? nodes && isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      fail "inventory.realization.nodes is required";

  deploymentHosts =
    if inventory ? deployment && inventory.deployment ? hosts && isAttrs inventory.deployment.hosts then
      inventory.deployment.hosts
    else
      { };

  normalizeInventoryContainerEntry =
    runtimeTarget: logicalName: entry:
    if isNonEmptyString entry then
      {
        name = logicalName;
        logicalName = logicalName;
        runtimeName = entry;
        container = entry;
      }
    else if isAttrs entry then
      let
        runtimeName =
          if entry ? runtimeName && isNonEmptyString entry.runtimeName then
            entry.runtimeName
          else if entry ? container && isNonEmptyString entry.container then
            entry.container
          else if entry ? name && isNonEmptyString entry.name then
            entry.name
          else
            fail "expected runtime target '${runtimeTarget}' container entry '${logicalName}' to define runtimeName";
      in
      entry
      // {
        name = logicalName;
        logicalName = logicalName;
        runtimeName = runtimeName;
        container = runtimeName;
      }
    else
      fail "expected runtime target '${runtimeTarget}' container entry '${logicalName}' to be an attribute set or non-empty string";

  normalizeInventoryContainers =
    runtimeTarget: node:
    let
      rawContainers = node.containers or null;
    in
    if rawContainers == null then
      {
        default = {
          name = "default";
          logicalName = "default";
          runtimeName = runtimeTarget;
          container = runtimeTarget;
        };
      }
    else if !isAttrs rawContainers then
      fail "expected runtime target '${runtimeTarget}' containers to be an attribute set"
    else
      mapAttrs (
        logicalName: entry: normalizeInventoryContainerEntry runtimeTarget logicalName entry
      ) rawContainers;

  runtimeTargets = mapAttrs (
    runtimeTarget: node:
    let
      normalizedContainers = normalizeInventoryContainers runtimeTarget node;
      containerNames = attrNames normalizedContainers;
      primaryContainer =
        if normalizedContainers ? default then
          normalizedContainers.default
        else if builtins.length containerNames == 1 then
          normalizedContainers.${builtins.head containerNames}
        else
          fail "expected runtime target '${runtimeTarget}' to define a default container or exactly one container";
      hostName =
        if node ? host && isNonEmptyString node.host then
          node.host
        else
          fail "runtime target '${runtimeTarget}' must define host";
      hostDef = if deploymentHosts ? ${hostName} then deploymentHosts.${hostName} else { };
    in
    node
    // {
      __containers = normalizedContainers;
      __primaryContainer = primaryContainer;
      __primaryContainerName = primaryContainer.runtimeName;
      __hostDef = hostDef;
    }
  ) realizationNodes;

  nixosContainerTargets = filter (
    runtimeTarget:
    let
      node = runtimeTargets.${runtimeTarget};
    in
    (node.platform or null) == "nixos-container"
  ) (attrNames runtimeTargets);

  containerPortList =
    node:
    if node ? ports && isAttrs node.ports then
      mapAttrsToList (
        portName: port:
        let
          attach =
            if port ? attach && isAttrs port.attach then
              port.attach
            else
              fail "runtime target '${node.__primaryContainerName}' port '${portName}' is missing attach";
          iface =
            if port ? interface && isAttrs port.interface then
              port.interface
            else
              fail "runtime target '${node.__primaryContainerName}' port '${portName}' is missing interface";
          ifaceName =
            if iface ? name && isNonEmptyString iface.name then
              iface.name
            else
              fail "runtime target '${node.__primaryContainerName}' port '${portName}' is missing interface.name";
          bridgeName =
            if attach ? bridge && isNonEmptyString attach.bridge then
              attach.bridge
            else
              fail "runtime target '${node.__primaryContainerName}' port '${portName}' is missing attach.bridge";
        in
        {
          inherit
            portName
            attach
            iface
            ifaceName
            bridgeName
            ;
        }
      ) node.ports
    else
      [ ];

  mkInterfaceAddresses = iface: {
    ipv4 = optional (iface ? addr4 && isNonEmptyString iface.addr4) {
      address = builtins.head (lib.splitString "/" iface.addr4);
      prefixLength = lib.toInt (builtins.elemAt (lib.splitString "/" iface.addr4) 1);
    };
    ipv6 = optional (iface ? addr6 && isNonEmptyString iface.addr6) {
      address = builtins.head (lib.splitString "/" iface.addr6);
      prefixLength = lib.toInt (builtins.elemAt (lib.splitString "/" iface.addr6) 1);
    };
  };

  mkInterfaceConfig =
    iface:
    let
      addrs = mkInterfaceAddresses iface;
    in
    {
      useDHCP = mkForce false;
      ipv4.addresses = addrs.ipv4;
      ipv6.addresses = addrs.ipv6;
    };

  mkExtraVeth = port: {
    hostBridge = port.bridgeName;
    containerInterface = port.ifaceName;
  };

  mkArtifactEtcEntries =
    runtimeTarget: node:
    let
      portsJson = builtins.toJSON (node.ports or { });
      containersJson = builtins.toJSON node.__containers;
      nodeJson = builtins.toJSON node;
    in
    {
      "network-artifacts/runtime-target".text = runtimeTarget;
      "network-artifacts/runtime-target.json".text = nodeJson;
      "network-artifacts/ports.json".text = portsJson;
      "network-artifacts/containers.json".text = containersJson;
    };

  mkContainer =
    runtimeTarget:
    let
      node = runtimeTargets.${runtimeTarget};
      containerName = node.__primaryContainerName;
      ports = containerPortList node;
      interfaceConfigs = foldl' (
        acc: port:
        acc
        // {
          ${port.ifaceName} = mkInterfaceConfig port.iface;
        }
      ) { } ports;
      extraVeths = map mkExtraVeth ports;
      etcEntries = mkArtifactEtcEntries runtimeTarget node;
    in
    {
      autoStart = true;
      ephemeral = false;
      privateNetwork = false;
      extraVeths = extraVeths;

      config =
        { ... }:
        {
          networking.hostName = containerName;
          networking.useDHCP = mkForce false;
          networking.useHostResolvConf = mkForce false;
          networking.nftables.enable = true;
          networking.interfaces = interfaceConfigs;

          environment.shells = [ pkgs.bashInteractive ];
          users.defaultUserShell = pkgs.bashInteractive;
          users.users.root.shell = pkgs.bashInteractive;
          programs.bash.enable = true;
          programs.zsh.enable = mkForce false;

          environment.etc = etcEntries;

          system.stateVersion = "24.11";
        };
    };

in
{
  environment.shells = [ pkgs.bashInteractive ];
  users.defaultUserShell = pkgs.bashInteractive;
  users.users.root.shell = pkgs.bashInteractive;
  programs.bash.enable = true;
  programs.zsh.enable = mkForce false;

  assertions = concatLists (
    map (
      runtimeTarget:
      let
        node = runtimeTargets.${runtimeTarget};
        containers = node.__containers;
      in
      [
        {
          assertion = all (
            logicalName:
            let
              entry = containers.${logicalName};
            in
            isAttrs entry && isNonEmptyString entry.runtimeName
          ) (attrNames containers);
          message = "network-renderer-nixos: expected runtime target '${runtimeTarget}' container entries to define non-empty runtimeName values";
        }
      ]
    ) nixosContainerTargets
  );

  containers = genAttrs nixosContainerTargets mkContainer;
}
