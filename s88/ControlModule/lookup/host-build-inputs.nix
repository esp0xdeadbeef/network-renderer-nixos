{
  selectors,
}:

let
  resolveSingleDeploymentHostName =
    {
      hostContext,
      selectorValue,
      file ? "s88/CM/network/lookup/host-build-inputs.nix",
    }:
    if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
      hostContext.deploymentHostName
    else if
      hostContext ? deploymentHostNames
      && builtins.isList hostContext.deploymentHostNames
      && builtins.length hostContext.deploymentHostNames == 1
    then
      builtins.head hostContext.deploymentHostNames
    else
      throw ''
        ${file}: selector '${selectorValue}' did not resolve to a single deployment host

        deploymentHostNames:
        ${builtins.toJSON (hostContext.deploymentHostNames or [ ])}
      '';

  resolveBuildInputs =
    {
      selector ? null,
      hostname ? null,
      intent ? null,
      inventory ? null,
      intentPath ? null,
      inventoryPath ? null,
      file ? "s88/CM/network/lookup/host-build-inputs.nix",
    }:
    let
      queried = selectors.query {
        inherit
          selector
          hostname
          intent
          inventory
          intentPath
          inventoryPath
          file
          ;
      };

      selectorValue =
        if selector != null then
          selector
        else if hostname != null then
          hostname
        else
          "<unknown>";

      deploymentHostName = resolveSingleDeploymentHostName {
        hostContext = queried.hostContext;
        inherit selectorValue file;
      };
    in
    queried
    // {
      inherit
        selectorValue
        deploymentHostName
        ;
    };
in
{
  inherit
    resolveSingleDeploymentHostName
    resolveBuildInputs
    ;
}
