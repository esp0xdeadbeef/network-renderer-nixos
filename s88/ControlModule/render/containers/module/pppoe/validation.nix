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

  hasFileCredential =
    credentials: field:
    let
      value = credentials.${field} or null;
    in
    builtins.isString value && value != "";

  hasInlineCredential =
    credentials: field:
    builtins.isString (credentials.${field} or null);

  hasCredentialFileContract =
    credentials:
    builtins.isAttrs credentials
    && hasFileCredential credentials "usernameFile"
    && hasFileCredential credentials "passwordFile"
    && !(hasInlineCredential credentials "username")
    && !(hasInlineCredential credentials "password");
in
{
  clientAssertion =
    clientConfig:
    clientConfig == null
    || (
      hasRenderedInterface (clientConfig.interface or null)
      && hasCredentialFileContract (clientConfig.credentials or null)
      && supportedImplementation clientConfig
    );

  serverAssertion =
    serverConfig:
    serverConfig == null
    || (
      hasRenderedInterface (serverConfig.interface or null)
      && builtins.isString (serverConfig.providerAddress or null)
      && builtins.isString (serverConfig.customerAddress or null)
      && hasCredentialFileContract (serverConfig.credentials or null)
      && supportedImplementation serverConfig
    );
}
