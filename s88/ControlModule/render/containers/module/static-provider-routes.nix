{
  lib,
  pkgs,
  staticProviderRoutes,
  staticProviderPolicyRules ? [ ],
}:

let
  providerInterfacePath = interfaceName: "/sys/class/net/${interfaceName}";
  providerInterfaces =
    lib.unique (
      (map (route: route.interfaceName) staticProviderRoutes)
      ++ (map (rule: rule.outputInterfaceName) staticProviderPolicyRules)
    );

  routeCommand =
    route:
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
      binary =
        if lib.hasInfix ":" route.destination then
          "${pkgs.iproute2}/bin/ip -6"
        else
          "${pkgs.iproute2}/bin/ip";
    in
    "${binary} route replace ${tableArg}${destination}${gatewayArg} dev ${interfaceName}${scopeArg}${metricArg} proto static${
      lib.optionalString (gatewayArg != "") " onlink"
    }";

  familyCommandsForRule =
    rule:
    let
      family = rule.Family or "both";
    in
    if family == "ipv4" then
      [ { binary = "${pkgs.iproute2}/bin/ip"; } ]
    else if family == "ipv6" then
      [ { binary = "${pkgs.iproute2}/bin/ip -6"; } ]
    else
      [
        { binary = "${pkgs.iproute2}/bin/ip"; }
        { binary = "${pkgs.iproute2}/bin/ip -6"; }
      ];

  ruleCommand =
    rule: familyCommand:
    let
      fromArg =
        if builtins.isString (rule.From or null) && rule.From != "" then
          " from ${lib.escapeShellArg rule.From}"
        else
          "";
      toArg =
        if builtins.isString (rule.To or null) && rule.To != "" then
          " to ${lib.escapeShellArg rule.To}"
        else
          "";
      incomingInterface =
        if builtins.isString (rule.IncomingInterface or null) && rule.IncomingInterface != "" then
          rule.IncomingInterface
        else
          rule.outputInterfaceName;
      iifArg = " iif ${lib.escapeShellArg incomingInterface}";
      priority = lib.escapeShellArg (toString (rule.Priority or 0));
      table =
        if (rule.SuppressPrefixLength or null) != null then
          " table main suppress_prefixlength ${lib.escapeShellArg (toString rule.SuppressPrefixLength)}"
        else
          " table ${lib.escapeShellArg (toString rule.Table)}";
    in
    ''
      while ${familyCommand.binary} rule del${fromArg}${toArg}${iifArg} priority ${priority} 2>/dev/null; do
        true
      done
      ${familyCommand.binary} rule add${fromArg}${toArg}${iifArg}${table} priority ${priority}
    '';

  routeServices = builtins.listToAttrs (
    map (
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
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = routeScript;
          };
        };
      }
    ) staticProviderRoutes
  );

  routePathUnits = builtins.listToAttrs (
    map (
      route:
      let
        serviceName = "s88-${route.name}";
      in
      {
        name = serviceName;
        value = {
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathExists = providerInterfacePath route.interfaceName;
            Unit = "${serviceName}.service";
          };
        };
      }
    ) staticProviderRoutes
  );

  ruleServices = builtins.listToAttrs (
    map (
      rule:
      let
        serviceName = "s88-${rule.name}";
        ruleScript = pkgs.writeShellScript serviceName ''
          set -eu
          ${pkgs.iproute2}/bin/ip link show dev ${lib.escapeShellArg rule.outputInterfaceName} >/dev/null 2>&1
          ${lib.concatMapStrings (familyCommand: ruleCommand rule familyCommand) (familyCommandsForRule rule)}
        '';
      in
      {
        name = serviceName;
        value = {
          description = "Install explicit policy rule for provider-created interface ${rule.outputInterfaceName}";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = ruleScript;
          };
        };
      }
    ) staticProviderPolicyRules
  );

  rulePathUnits = builtins.listToAttrs (
    map (
      rule:
      let
        serviceName = "s88-${rule.name}";
      in
      {
        name = serviceName;
        value = {
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathExists = providerInterfacePath rule.outputInterfaceName;
            Unit = "${serviceName}.service";
          };
        };
      }
    ) staticProviderPolicyRules
  );

  providerInterfaceWatchers = builtins.listToAttrs (
    map (
      interfaceName:
      let
        serviceName = "s88-provider-interface-${interfaceName}";
        routeUnitNames =
          map (route: "s88-${route.name}.service") (
            lib.filter (route: route.interfaceName == interfaceName) staticProviderRoutes
          );
        ruleUnitNames =
          map (rule: "s88-${rule.name}.service") (
            lib.filter (rule: rule.outputInterfaceName == interfaceName) staticProviderPolicyRules
          );
        unitNames = routeUnitNames ++ ruleUnitNames;
        startUnits = lib.concatMapStringsSep " " lib.escapeShellArg unitNames;
      in
      {
        name = serviceName;
        value = {
          description = "Start provider-created interface route/rule units for ${interfaceName}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            coreutils
            iproute2
            systemd
          ];
          serviceConfig = {
            Type = "simple";
            Restart = "on-failure";
            RestartSec = "2s";
          };
          script = ''
            set -eu
            while ! ip link show dev ${lib.escapeShellArg interfaceName} >/dev/null 2>&1; do
              sleep 1
            done
            systemctl start ${startUnits}
          '';
        };
      }
    ) providerInterfaces
  );
in
{
  config = lib.optionalAttrs (staticProviderRoutes != [ ] || staticProviderPolicyRules != [ ]) {
    systemd.services = routeServices // ruleServices // providerInterfaceWatchers;
    systemd.paths = routePathUnits // rulePathUnits;
  };
}
