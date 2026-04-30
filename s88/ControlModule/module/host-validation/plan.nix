{ lib, renderedHostNetwork ? null }:

let
  effectiveRenderedHostNetwork = if renderedHostNetwork != null then renderedHostNetwork else { };
in
{
  intervalSeconds = 5;
  expectedContainers = lib.sort builtins.lessThan (
    builtins.attrNames (effectiveRenderedHostNetwork.containers or { })
  );
  dnsProbeName = "example.com";
}
