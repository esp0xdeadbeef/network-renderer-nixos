{ }:

controlPlaneOut:

canonicalCollections:

let

  fromCanonical =
    let
      sites =
        (if builtins.isAttrs canonicalCollections then canonicalCollections else { }).canonicalSites or { };
    in
    if builtins.isAttrs (sites.byEnterprise or null) then sites.byEnterprise else null;

  controlPlaneData = if fromCanonical != null then fromCanonical else { };
in
builtins.listToAttrs (
  builtins.concatLists (
    builtins.map (
      enterpriseName:
      let
        enterprise = controlPlaneData.${enterpriseName};
      in
      builtins.concatLists (
        builtins.map (
          siteName:
          let
            site = enterprise.${siteName};
            runtimeTargets = site.runtimeTargets or { };
          in
          builtins.map (targetName: {
            name = "${enterpriseName}.${siteName}.${targetName}";
            value = runtimeTargets.${targetName};
          }) (builtins.attrNames runtimeTargets)
        ) (builtins.attrNames enterprise)
      )
    ) (builtins.attrNames controlPlaneData)
  )
)
