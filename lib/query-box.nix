{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  importMaybeFunction =
    path:
    let
      imported =
        if builtins.pathExists path then
          import path
        else
          { };
    in
    if builtins.isFunction imported then
      imported { inherit lib; }
    else
      imported;

  renderHostsFor =
    inventory:
    if inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  deploymentHostsFor =
    inventory:
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      { };

  realizationNodesFor =
    inventory:
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  repoRootFromOutPath =
    outPath:
    builtins.dirOf (builtins.dirOf (builtins.dirOf outPath));

  fabricRootFromOutPath =
    outPath:
    builtins.toPath "${repoRootFromOutPath outPath}/library/100-fabric-routing";

  pathsFromOutPath =
    {
      outPath,
      fabricRoot ? null,
    }:
    let
      resolvedFabricRoot =
        if fabricRoot != null then
          fabricRoot
        else
          fabricRootFromOutPath outPath;
    in
    {
      intentPath = resolvedFabricRoot + /inputs/intent.nix;
      inventoryPath = resolvedFabricRoot + /inventory.nix;
    };

  resolveDeploymentHostName =
    {
      inventory,
      hostname,
      file ? "lib/query-box.nix",
    }:
    let
      renderHosts = renderHostsFor inventory;

      renderHostConfig =
        if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
          renderHosts.${hostname}
        else
          { };

      deploymentHosts = deploymentHostsFor inventory;
      deploymentHostNames = sortedAttrNames deploymentHosts;
      realizationNodes = realizationNodesFor inventory;
    in
    if renderHostConfig ? deploymentHost
      && builtins.isString renderHostConfig.deploymentHost
      && builtins.hasAttr renderHostConfig.deploymentHost deploymentHosts
    then
      renderHostConfig.deploymentHost
    else if builtins.hasAttr hostname realizationNodes
      && builtins.isAttrs realizationNodes.${hostname}
      && realizationNodes.${hostname} ? host
      && builtins.isString realizationNodes.${hostname}.host
      && builtins.hasAttr realizationNodes.${hostname}.host deploymentHosts
    then
      realizationNodes.${hostname}.host
    else if builtins.hasAttr hostname deploymentHosts then
      hostname
    else if builtins.length deploymentHostNames == 1 then
      builtins.head deploymentHostNames
    else
      throw ''
        ${file}: could not resolve deployment host for '${hostname}'

        known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';
in
{
  inherit
    importMaybeFunction
    repoRootFromOutPath
    fabricRootFromOutPath
    pathsFromOutPath
    resolveDeploymentHostName
    ;

  loadInputs =
    {
      intentPath,
      inventoryPath,
    }:
    {
      fabricInputs = importMaybeFunction intentPath;
      globalInventory = importMaybeFunction inventoryPath;
    };

  loadInputsFromOutPath =
    {
      outPath,
      fabricRoot ? null,
    }:
    let
      paths = pathsFromOutPath {
        inherit outPath fabricRoot;
      };
    in
    {
      fabricInputs = importMaybeFunction paths.intentPath;
      globalInventory = importMaybeFunction paths.inventoryPath;
    };

  boxForHost =
    {
      inventory,
      hostname,
      file ? "lib/query-box.nix",
    }:
    let
      renderHosts = renderHostsFor inventory;

      renderHostConfig =
        if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
          renderHosts.${hostname}
        else
          { };

      deploymentHosts = deploymentHostsFor inventory;
      deploymentHostNames = sortedAttrNames deploymentHosts;
      realizationNodes = realizationNodesFor inventory;

      deploymentHostName = resolveDeploymentHostName {
        inherit inventory hostname file;
      };
    in
    rec {
      inherit
        hostname
        renderHosts
        renderHostConfig
        deploymentHosts
        deploymentHostNames
        realizationNodes
        deploymentHostName
        ;

      boxName = deploymentHostName;
      box = deploymentHosts.${deploymentHostName};

      realizationNode =
        if builtins.hasAttr hostname realizationNodes && builtins.isAttrs realizationNodes.${hostname} then
          realizationNodes.${hostname}
        else
          null;
    };

  query =
    {
      intentPath,
      inventoryPath,
      hostname,
      file ? "lib/query-box.nix",
    }:
    let
      loaded = {
        fabricInputs = importMaybeFunction intentPath;
        globalInventory = importMaybeFunction inventoryPath;
      };
    in
    loaded
    // {
      boxContext = (builtins.getAttr "boxForHost" (import ./query-box.nix { inherit lib; })) {
        inventory = loaded.globalInventory;
        inherit hostname file;
      };
    };

  queryFromOutPath =
    {
      outPath,
      hostname,
      fabricRoot ? null,
      file ? "lib/query-box.nix",
    }:
    let
      paths = pathsFromOutPath {
        inherit outPath fabricRoot;
      };
    in
    (builtins.getAttr "query" (import ./query-box.nix { inherit lib; })) ({
      inherit hostname file;
    } // paths);
}
