{
  lib,
  renderedHostNetwork ? null,
}:

let
  effectiveRenderedHostNetwork = if renderedHostNetwork != null then renderedHostNetwork else { };
  hostValidation = effectiveRenderedHostNetwork.hostValidation or { };
in
{
  intervalSeconds = 5;
  expectedContainers = lib.sort builtins.lessThan (
    builtins.attrNames (effectiveRenderedHostNetwork.containers or { })
  );
  dnsProbeName = "example.com";
  publicIpv4Probe = hostValidation.publicIpv4Probe or "1.1.1.1";
  publicIpv6Probe = hostValidation.publicIpv6Probe or "2606:4700:4700::1111";
  requireDefaultRoutes = hostValidation.requireDefaultRoutes or false;
  requireHostResolver = hostValidation.requireHostResolver or false;
  requirePublicIpv4Ping = hostValidation.requirePublicIpv4Ping or false;
  requirePublicIpv6Ping = hostValidation.requirePublicIpv6Ping or false;
}
