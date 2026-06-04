{ renderedModel }:

let
  interfaces = if builtins.isAttrs (renderedModel.interfaces or null) then renderedModel.interfaces else { };

  hasRenderedInterface =
    logicalName:
    builtins.isString logicalName
    && logicalName != ""
    && builtins.hasAttr logicalName interfaces;

  supportedImplementation =
    config:
    !(builtins.isString (config.implementation or null))
    || (config.implementation or null) == "rp-pppoe";
in
{
  clientAssertion =
    clientConfig:
    clientConfig == null
    || (
      hasRenderedInterface (clientConfig.interface or null)
      && builtins.isAttrs (clientConfig.credentials or null)
      && supportedImplementation clientConfig
    );

  serverAssertion =
    serverConfig:
    serverConfig == null
    || (
      hasRenderedInterface (serverConfig.interface or null)
      && builtins.isString (serverConfig.providerAddress or null)
      && builtins.isString (serverConfig.customerAddress or null)
      && builtins.isAttrs (serverConfig.credentials or null)
      && supportedImplementation serverConfig
    );
}
