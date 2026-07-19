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

  hasIpv6PrefixDelegationContract =
    value:
    value == null
    || (
      builtins.isAttrs value
      && builtins.attrNames value == builtins.attrNames {
        mode = null;
        defaultRoute = null;
        iaid = null;
        prefixDelegationRequestId = null;
        duidMode = null;
        resolverMode = null;
        ipv4Mode = null;
        routerSolicitation = null;
        fallbackPolicy = null;
      }
      && (value.mode or null) == "dhcpv6-pd"
      && builtins.isBool (value.defaultRoute or null)
      && builtins.isInt (value.iaid or null)
      && value.iaid > 0
      && builtins.isInt (value.prefixDelegationRequestId or null)
      && value.prefixDelegationRequestId > 0
      && (value.duidMode or null) == "persistent"
      && (value.resolverMode or null) == "disabled"
      && (value.ipv4Mode or null) == "disabled"
      && (value.routerSolicitation or null) == false
      && (value.fallbackPolicy or null) == "none"
    );
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
      && hasIpv6PrefixDelegationContract (clientConfig.ipv6 or null)
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
