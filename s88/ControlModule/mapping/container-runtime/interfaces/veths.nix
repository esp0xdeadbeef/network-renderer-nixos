{ lib, lookup }:

{
  vethsForInterfaces =
    interfaces:
    let
      entries = map (
        ifName:
        let
          iface = interfaces.${ifName};
          hostVethName =
            if iface ? hostVethName && builtins.isString iface.hostVethName then
              iface.hostVethName
            else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
              iface.hostInterfaceName
            else if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
              iface.containerInterfaceName
            else
              ifName;
        in
        if iface.usePrimaryHostBridge or false then
          null
        else
          {
            name = hostVethName;
            value = {
              hostBridge = iface.renderedHostBridgeName;
            };
          }
      ) (lookup.sortedAttrNames interfaces);
    in
    builtins.listToAttrs (lib.filter (entry: entry != null) entries);
}
