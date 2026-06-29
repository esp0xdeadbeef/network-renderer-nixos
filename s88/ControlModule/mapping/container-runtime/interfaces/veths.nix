{ lib, lookup }:

{
  vethsForInterfaces =
    interfaces:
    let
      attrsOrEmpty = value: if builtins.isAttrs value then value else { };
      isPppoeSessionInterface =
        iface:
        let
          connectivity = attrsOrEmpty (iface.connectivity or null);
          backingRef = attrsOrEmpty (iface.backingRef or null);
          connectivityBackingRef = attrsOrEmpty (connectivity.backingRef or null);
        in
        (iface.sourceKind or null) == "pppoe-session"
        || (connectivity.sourceKind or null) == "pppoe-session"
        || (backingRef.kind or null) == "pppoe-session"
        || (connectivityBackingRef.kind or null) == "pppoe-session";
      entries = map
        (
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
          if (iface.usePrimaryHostBridge or false) || isPppoeSessionInterface iface then
            null
          else
            {
              name = hostVethName;
              value = {
                hostBridge = iface.renderedHostBridgeName;
              };
            }
        )
        (lookup.sortedAttrNames interfaces);
    in
    builtins.listToAttrs (lib.filter (entry: entry != null) entries);
}
