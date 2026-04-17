{
  lib,
  selectFirewallRuntimeTargetModel,
  renderNftablesRuntimeTarget,
  selectContainerRuntimeTargetServiceModels,
}:
{
  normalizedModel,
  enterpriseName,
  siteName,
  hostName,
  containerName,
  runtimeTargetName,
  runtimeTarget,
}:
let
  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  validPathSegment =
    name: value:
    let
      s = toString value;
    in
    if s == "" then
      throw "network-renderer-nixos: ${name} must not be empty"
    else if s == "." || s == ".." then
      throw "network-renderer-nixos: ${name} '${s}' is not a valid artifact path segment"
    else if lib.hasInfix "/" s then
      throw "network-renderer-nixos: ${name} '${s}' must not contain '/'"
    else
      s;

  enterpriseSegment = validPathSegment "enterprise name" enterpriseName;
  siteSegment = validPathSegment "site name" siteName;
  hostSegment = validPathSegment "host name" hostName;
  containerSegment = validPathSegment "container name" containerName;
  runtimeTargetSegment = validPathSegment "runtime target name" runtimeTargetName;

  containerRoot = "${enterpriseSegment}/${siteSegment}/${hostSegment}/containers/${containerSegment}";
  hostArtifactPath = "${enterpriseSegment}/${siteSegment}/${hostSegment}/host-data/host.json";
  containerArtifactPath = "${containerRoot}/container.json";
  runtimeTargetRoot = "${containerRoot}/runtime-targets/${runtimeTargetSegment}";
  runtimeTargetArtifactPath = "${runtimeTargetRoot}/runtime-target.json";
  firewallArtifactPath = "${runtimeTargetRoot}/firewall/nftables.nft";

  siteData =
    if
      normalizedModel ? siteData
      && builtins.isAttrs normalizedModel.siteData
      && builtins.hasAttr enterpriseName normalizedModel.siteData
      && builtins.isAttrs normalizedModel.siteData.${enterpriseName}
      && builtins.hasAttr siteName normalizedModel.siteData.${enterpriseName}
      && builtins.isAttrs normalizedModel.siteData.${enterpriseName}.${siteName}
    then
      normalizedModel.siteData.${enterpriseName}.${siteName}
    else
      { };

  artifactContext = {
    inherit
      enterpriseName
      siteName
      hostName
      containerName
      runtimeTargetName
      runtimeTarget
      siteData
      hostArtifactPath
      containerArtifactPath
      runtimeTargetArtifactPath
      ;
    siteArtifactPath = "${enterpriseSegment}/${siteSegment}/site.json";
    siteDataArtifactPath = "${enterpriseSegment}/${siteSegment}/site-data.json";
  };

  firewallArtifact =
    if runtimeTarget ? forwardingIntent && builtins.isAttrs runtimeTarget.forwardingIntent then
      {
        format = "text";
        value = renderNftablesRuntimeTarget (selectFirewallRuntimeTargetModel {
          inherit normalizedModel artifactContext;
        });
      }
    else
      null;

  selectedServices = selectContainerRuntimeTargetServiceModels { inherit artifactContext; };

  serviceEntries = lib.filter (entry: entry != null) [
    (
      if selectedServices.kea == null then
        null
      else
        {
          name = "${containerRoot}/services/kea/kea.json";
          value = {
            format = "json";
            value = selectedServices.kea;
          };
        }
    )
    (
      if selectedServices.radvd == null then
        null
      else
        {
          name = "${containerRoot}/services/radvd/radvd.json";
          value = {
            format = "json";
            value = selectedServices.radvd;
          };
        }
    )
  ];

  serviceNames = map (entry: builtins.elemAt (lib.splitString "/" entry.name) 4) serviceEntries;

  files = {
    "${containerArtifactPath}" = {
      format = "json";
      value = {
        enterprise = enterpriseName;
        site = siteName;
        host = hostName;
        container = containerName;
        artifactPath = containerArtifactPath;
        runtimeTargetNames = [ runtimeTargetName ];
        runtimeTargetArtifactPaths = [ runtimeTargetArtifactPath ];
        serviceNames = serviceNames;
      };
    };

    "${runtimeTargetArtifactPath}" = {
      format = "json";
      value = ensureAttrs "runtimeTarget" runtimeTarget;
    };
  }
  // lib.optionalAttrs (serviceEntries != [ ]) {
    "${containerRoot}/services/index.json" = {
      format = "json";
      value = {
        enterprise = enterpriseName;
        site = siteName;
        host = hostName;
        container = containerName;
        artifactPath = "${containerRoot}/services/index.json";
        serviceNames = serviceNames;
        runtimeTargetNames = [ runtimeTargetName ];
        runtimeTargetArtifactPaths = [ runtimeTargetArtifactPath ];
      };
    };
  }
  // builtins.listToAttrs serviceEntries
  // lib.optionalAttrs (firewallArtifact != null) {
    "${firewallArtifactPath}" = firewallArtifact;
  };
in
{
  inherit files;
  nftablesArtifactPath = if firewallArtifact == null then null else firewallArtifactPath;
}
