{}:

controlPlaneOut:

let
  controlPlaneData = ((controlPlaneOut.control_plane_model or { }).data or { });
in
builtins.listToAttrs (
  builtins.concatLists (
    builtins.map
      (
        enterpriseName:
        let
          enterprise = controlPlaneData.${enterpriseName};
        in
        builtins.concatLists (
          builtins.map
            (
              siteName:
              let
                site = enterprise.${siteName};
                runtimeTargets = site.runtimeTargets or { };
              in
              builtins.map
                (targetName: {
                  name = "${enterpriseName}.${siteName}.${targetName}";
                  value = runtimeTargets.${targetName};
                })
                (builtins.attrNames runtimeTargets)
            )
            (builtins.attrNames enterprise)
        )
      )
      (builtins.attrNames controlPlaneData)
  )
)
