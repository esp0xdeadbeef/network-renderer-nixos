{ lib
, helpers
,
}:

let
  inherit (helpers)
    attachMapForUnit
    realizationNodesFor
    sortedAttrNames
    ;
in
rec {
  unitNamesForDeploymentHost =
    { source
    , deploymentHostName
    ,
    }:
    let
      realizationNodes = realizationNodesFor source;
    in
    lib.filter
      (
        unitName:
        let
          node = realizationNodes.${unitName};
        in
        (node.host or null) == deploymentHostName
      )
      (sortedAttrNames realizationNodes);

  attachTargetsForDeploymentHost =
    { source
    , deploymentHostName
    , file ? "s88/Unit/physical/realization-ports.nix"
    ,
    }:
    let
      unitNames = unitNamesForDeploymentHost {
        inherit source deploymentHostName;
      };

      attachTargetsByHostBridgeName = builtins.listToAttrs (
        lib.concatMap
          (
            unitName:
            let
              attachMap = attachMapForUnit {
                inherit source unitName file;
              };
            in
            map
              (portName: {
                name = attachMap.${portName}.hostBridgeName;
                value = attachMap.${portName};
              })
              (sortedAttrNames attachMap)
          )
          unitNames
      );
    in
    map (hostBridgeName: attachTargetsByHostBridgeName.${hostBridgeName}) (
      sortedAttrNames attachTargetsByHostBridgeName
    );
}
