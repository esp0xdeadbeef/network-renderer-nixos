{ lib }:
bridgeModel:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  bridgeNames =
    if bridgeModel ? bridges && builtins.isAttrs bridgeModel.bridges then
      sortedAttrNames bridgeModel.bridges
    else
      [ ];

  keepaliveNameFor = bridgeName: "ka-${bridgeName}";

  netdevs = builtins.listToAttrs (
    lib.concatMap (
      bridgeName:
      let
        keepaliveName = keepaliveNameFor bridgeName;
      in
      [
        {
          name = bridgeName;
          value = {
            netdevConfig = {
              Kind = "bridge";
              Name = bridgeName;
            };
          };
        }
        {
          name = keepaliveName;
          value = {
            netdevConfig = {
              Kind = "dummy";
              Name = keepaliveName;
            };
          };
        }
      ]
    ) bridgeNames
  );

  networks = builtins.listToAttrs (
    lib.concatMap (
      bridgeName:
      let
        keepaliveName = keepaliveNameFor bridgeName;
      in
      [
        {
          name = "85-${keepaliveName}";
          value = {
            matchConfig.Name = keepaliveName;
            networkConfig = {
              Bridge = bridgeName;
              ConfigureWithoutCarrier = true;
            };
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
          };
        }
        {
          name = "90-${bridgeName}";
          value = {
            matchConfig.Name = bridgeName;
            networkConfig = {
              ConfigureWithoutCarrier = true;
            };
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
          };
        }
      ]
    ) bridgeNames
  );
in
{
  hostName = bridgeModel.hostName or bridgeModel.deploymentHostName;
  deploymentHostName = bridgeModel.deploymentHostName;
  netdevs = netdevs;
  networks = networks;
  debug = bridgeModel.debug or { } // {
    renderedNetdevs = builtins.attrNames netdevs;
    renderedNetworks = builtins.attrNames networks;
  };
}
