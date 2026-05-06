{ lib }:

let
  profilesDir = ../../../ControlModule/profiles;
  policyDir = ../../../ControlModule/firewall/policy;

  profileFiles = builtins.readDir profilesDir;
  profileNames =
    lib.sort builtins.lessThan (
      lib.filter (
        name:
        let kind = profileFiles.${name};
        in
        kind == "regular"
        && lib.hasSuffix ".nix" name
        && !(lib.hasSuffix ".meta.nix" name)
        && name != "common-router.nix"
        && name != "registry.nix"
      ) (builtins.attrNames profileFiles)
    );

  roleNameForFile = name: lib.removeSuffix ".nix" name;

  metadataFor =
    roleName:
    let path = profilesDir + "/${roleName}.meta.nix";
    in
    if builtins.pathExists path then import path else { };

  policyPathFor =
    roleName:
    let path = policyDir + "/${roleName}.nix";
    in
    if builtins.pathExists path then path else null;

  defaultContainer = roleName: {
    enable = true;
    profilePath = profilesDir + "/${roleName}.nix";
    advertise = {
      dhcp4 = false;
      radvd = false;
    };
    enableEdgeServices = false;
    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];
  };

  mkRole = roleName:
    let metadata = metadataFor roleName;
    in
    {
      hostProfilePath = null;
      container = (defaultContainer roleName) // (metadata.container or { });
      firewallPolicyPath = metadata.firewallPolicyPath or (policyPathFor roleName);
      assumptionFamily = metadata.assumptionFamily or null;
      preferSiteNode = metadata.preferSiteNode or false;
      strictEndpointBindings = metadata.strictEndpointBindings or false;
    };
in
builtins.listToAttrs (
  map (name: {
    name = roleNameForFile name;
    value = mkRole (roleNameForFile name);
  }) profileNames
)
