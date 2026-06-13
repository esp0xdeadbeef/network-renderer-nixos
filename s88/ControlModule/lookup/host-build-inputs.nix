{ selectors
,
}:

let
  resolveSingleDeploymentHostName =
    { hostContext
    , selectorValue
    , file ? "s88/CM/network/lookup/host-build-inputs.nix"
    ,
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

  # NOTE: intentPath/inventoryPath params removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
  # Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM-mediated data.
  resolveBuildInputs =
    { selector ? null
    , hostname ? null
    , intent ? null
    , inventory ? null
    , file ? "s88/CM/network/lookup/host-build-inputs.nix"
    ,
    }:
    let
      queried = selectors.query {
        inherit
          selector
          hostname
          intent
          inventory
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
