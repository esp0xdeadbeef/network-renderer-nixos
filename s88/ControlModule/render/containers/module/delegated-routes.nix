{ lib, pkgs, dynamicDelegatedRoutes }:

let
  services = builtins.listToAttrs (
    map (
      route:
      let
        serviceName = "s88-${route.name}";
        routeScript = pkgs.writeShellScript serviceName ''
          set -eu
          source_file=${lib.escapeShellArg route.sourceFile}
          interface=${lib.escapeShellArg route.interfaceName}
          gateway=${if route.gateway == null then "''" else lib.escapeShellArg route.gateway}
          metric=${if route.metric == null then "''" else lib.escapeShellArg (toString route.metric)}

          [ -s "$source_file" ] || exit 0
          prefix="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < "$source_file")"
          [ -n "$prefix" ] || exit 0

          if [ -n "$gateway" ]; then
            if [ -n "$metric" ]; then
              ${pkgs.iproute2}/bin/ip -6 route replace "$prefix" via "$gateway" dev "$interface" metric "$metric" proto static onlink
            else
              ${pkgs.iproute2}/bin/ip -6 route replace "$prefix" via "$gateway" dev "$interface" proto static onlink
            fi
          else
            if [ -n "$metric" ]; then
              ${pkgs.iproute2}/bin/ip -6 route replace "$prefix" dev "$interface" metric "$metric" proto static
            else
              ${pkgs.iproute2}/bin/ip -6 route replace "$prefix" dev "$interface" proto static
            fi
          fi
        '';
      in
      {
        name = serviceName;
        value = {
          description = "Install delegated external-validation IPv6 route on ${route.interfaceName}";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-networkd.service" ];
          wants = [ "systemd-networkd.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = routeScript;
          };
        };
      }
    ) dynamicDelegatedRoutes
  );

  paths = builtins.listToAttrs (
    map (
      route:
      let serviceName = "s88-${route.name}";
      in
      {
        name = serviceName;
        value = {
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathExists = route.sourceFile;
            PathChanged = route.sourceFile;
            Unit = "${serviceName}.service";
          };
        };
      }
    ) dynamicDelegatedRoutes
  );
in
{
  config = lib.optionalAttrs (dynamicDelegatedRoutes != [ ]) {
    systemd.services = services;
    systemd.paths = paths;
  };
}
