{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizeDebug =
    raw:
    if !builtins.isAttrs raw then
      { }
    else
      builtins.removeAttrs raw [
        "profilePath"
        "firewallPolicyPath"
      ];

  sanitizeContainer =
    containerName: container:
    let
      specialArgs =
        if container ? specialArgs && builtins.isAttrs container.specialArgs then
          container.specialArgs
        else
          { };

      firewall =
        if specialArgs ? s88Firewall then
          let
            rawFirewall = specialArgs.s88Firewall;
          in
          if builtins.isAttrs rawFirewall then
            {
              enable = rawFirewall.enable or false;
              ruleset = if rawFirewall ? ruleset then rawFirewall.ruleset else null;
            }
          else if builtins.isString rawFirewall then
            {
              enable = rawFirewall != "";
              ruleset = rawFirewall;
            }
          else
            {
              enable = false;
              ruleset = null;
            }
        else
          {
            enable = false;
            ruleset = null;
          };

      s88Debug =
        if specialArgs ? s88Debug && builtins.isAttrs specialArgs.s88Debug then
          sanitizeDebug specialArgs.s88Debug
        else
          { };

      s88Warnings =
        if specialArgs ? s88Warnings && builtins.isList specialArgs.s88Warnings then
          lib.filter builtins.isString specialArgs.s88Warnings
        else
          [ ];

      s88Alarms =
        if specialArgs ? s88Alarms && builtins.isList specialArgs.s88Alarms then
          specialArgs.s88Alarms
        else
          [ ];
    in
    {
      autoStart = container.autoStart or false;
      privateNetwork = container.privateNetwork or false;
      extraVeths = container.extraVeths or { };
      bindMounts = container.bindMounts or { };
      allowedDevices = container.allowedDevices or [ ];
      additionalCapabilities = container.additionalCapabilities or [ ];
      inherit firewall;
      warnings = s88Warnings;
      alarms = s88Alarms;
      specialArgs = {
        unitName = if specialArgs ? unitName then specialArgs.unitName else containerName;
        deploymentHostName =
          if specialArgs ? deploymentHostName then specialArgs.deploymentHostName else null;
        s88RoleName = if specialArgs ? s88RoleName then specialArgs.s88RoleName else null;
        s88Debug = s88Debug;
      };
    };
in
{
  sanitizedContainersForHost =
    hostRendering:
    builtins.listToAttrs (
      map
        (containerName: {
          name = containerName;
          value = sanitizeContainer containerName hostRendering.containers.${containerName};
        })
        (sortedAttrNames (hostRendering.containers or { }))
    );
}
