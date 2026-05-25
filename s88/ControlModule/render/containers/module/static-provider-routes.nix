{ lib, pkgs, staticProviderRoutes }:

let
  routeCommand = route:
    let
      destination = lib.escapeShellArg route.destination;
      interfaceName = lib.escapeShellArg route.interfaceName;
      tableArg =
        if builtins.isInt (route.table or null) then
          "table ${lib.escapeShellArg (toString route.table)} "
        else
          "";
      metricArg =
        if builtins.isInt (route.metric or null) then
          " metric ${lib.escapeShellArg (toString route.metric)}"
        else
          "";
      gatewayArg =
        if builtins.isString (route.gateway or null) && route.gateway != "" then
          " via ${lib.escapeShellArg route.gateway}"
        else
          "";
      scopeArg =
        if gatewayArg == "" && builtins.isString (route.scope or null) && route.scope != "" then
          " scope ${lib.escapeShellArg route.scope}"
        else
          "";
      binary = if lib.hasInfix ":" route.destination then "${pkgs.iproute2}/bin/ip -6" else "${pkgs.iproute2}/bin/ip";
    in
    "${binary} route replace ${tableArg}${destination}${gatewayArg} dev ${interfaceName}${scopeArg}${metricArg} proto static${lib.optionalString (gatewayArg != "") " onlink"}";

  services = builtins.listToAttrs (
    map
      (
        route:
        let
          serviceName = "s88-${route.name}";
          routeScript = pkgs.writeShellScript serviceName ''
            set -eu
            ${pkgs.iproute2}/bin/ip link show dev ${lib.escapeShellArg route.interfaceName} >/dev/null 2>&1
            ${routeCommand route}
          '';
        in
        {
          name = serviceName;
          value = {
            description = "Install explicit route on provider-created interface ${route.interfaceName}";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = routeScript;
            };
          };
        }
      )
      staticProviderRoutes
  );
in
{
  config = lib.optionalAttrs (staticProviderRoutes != [ ]) {
    systemd.services = services;
  };
}
