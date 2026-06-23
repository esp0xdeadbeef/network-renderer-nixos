{ renderedModel }:

let
  interfaces =
    if builtins.isAttrs (renderedModel.interfaces or null) then renderedModel.interfaces else { };

  hasRenderedInterface =
    logicalName:
    builtins.isString logicalName && logicalName != "" && builtins.hasAttr logicalName interfaces;

  hasResolvedPppoeLowerInterface =
    role: serviceInterface:
    let
      runtimeTarget =
        if builtins.isAttrs (renderedModel.runtimeTarget or null) then renderedModel.runtimeTarget else { };
      effective =
        if builtins.isAttrs (runtimeTarget.effectiveRuntimeRealization or null) then
          runtimeTarget.effectiveRuntimeRealization
        else
          { };
      effectiveInterfaces =
        if builtins.isAttrs (effective.interfaces or null) then effective.interfaces else { };
      pppoeSessions = builtins.filter (
        iface:
        builtins.isAttrs (iface.pppoe or null)
        && (iface.pppoe.serviceInterface or null) == serviceInterface
        && (iface.pppoe.role or null) == role
      ) (builtins.attrValues effectiveInterfaces);
      preferredSourceKind = if role == "client" then "wan" else "p2p";
      candidates = builtins.filter (
        name:
        let
          iface = effectiveInterfaces.${name};
        in
        (iface.sourceKind or null) == preferredSourceKind
      ) (builtins.attrNames effectiveInterfaces);
    in
    builtins.isString serviceInterface
    && serviceInterface != ""
    && pppoeSessions != [ ]
    && builtins.length candidates == 1;

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

  hasInlineCredential = credentials: field: builtins.isString (credentials.${field} or null);

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
      (
        hasRenderedInterface (clientConfig.interface or null)
        || hasResolvedPppoeLowerInterface "client" (clientConfig.interface or null)
      )
      && hasCredentialFileContract (clientConfig.credentials or null)
      && supportedImplementation clientConfig
    );

  serverAssertion =
    serverConfig:
    serverConfig == null
    || (
      (
        hasRenderedInterface (serverConfig.interface or null)
        || hasResolvedPppoeLowerInterface "server" (serverConfig.interface or null)
      )
      && builtins.isString (serverConfig.providerAddress or null)
      && builtins.isString (serverConfig.customerAddress or null)
      && hasCredentialFileContract (serverConfig.credentials or null)
      && supportedImplementation serverConfig
    );
}
