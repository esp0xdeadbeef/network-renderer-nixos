{ lib }:
{
  enterpriseName,
  siteName,
  hostName,
  containerName,
  runtimeTargetName,
  runtimeTarget,
}:
let
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

  siteRoot = "${enterpriseSegment}/${siteSegment}";
  hostRoot = "${siteRoot}/${hostSegment}";
  hostDataAndContainersRoot = "${hostRoot}/host-data-and-containers";
  hostDataRoot = "${hostDataAndContainersRoot}/host-data";
  containersRoot = "${hostDataAndContainersRoot}/containers";
  containerRoot = "${containersRoot}/${containerSegment}";
  runtimeTargetRoot = "${containerRoot}/runtime-targets/${runtimeTargetSegment}";
in
{
  inherit
    enterpriseName
    siteName
    hostName
    containerName
    runtimeTargetName
    runtimeTarget
    ;

  siteArtifactPath = "${siteRoot}/site.json";
  siteDataArtifactPath = "${siteRoot}/site-data.json";
  hostArtifactPath = "${hostDataRoot}/host.json";
  containerArtifactPath = "${containerRoot}/container.json";
  runtimeTargetArtifactPath = "${runtimeTargetRoot}/runtime-target.json";
  firewallArtifactPath = "${runtimeTargetRoot}/firewall/nftables.nft";
  servicesRoot = "${containerRoot}/services";
}
