{
  lib,
  pkgs,
  renderedModel,
  ipv6AcceptRAInterfaces ? [ ],
}:

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

  containerInterfaceRenames = lib.filter (entry: entry != null) (
    map (
      iface:
      let
        initialInterfaceName =
          if builtins.isString (iface.hostVethName or null) then iface.hostVethName else null;
        finalInterfaceName =
          if
            builtins.isString (iface.containerInterfaceName or null) && iface.containerInterfaceName != ""
          then
            iface.containerInterfaceName
          else
            null;
      in
      if
        !isPppoeSessionInterface iface
        && initialInterfaceName != null
        && finalInterfaceName != null
        && initialInterfaceName != finalInterfaceName
      then
        { inherit initialInterfaceName finalInterfaceName; }
      else
        null
    ) (builtins.attrValues (renderedModel.interfaces or { }))
  );

  routedSlaacInterfaces = lib.unique ipv6AcceptRAInterfaces;

  services =
    if containerInterfaceRenames == [ ] && routedSlaacInterfaces == [ ] then
      { }
    else
      {
        s88-rename-interfaces = {
          description = "Materialize rendered container interface lifecycle";
          wantedBy = [ "multi-user.target" ];
          requiredBy = [ "systemd-networkd.service" ];
          before = [
            "systemd-networkd.service"
            "multi-user.target"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script =
            let
              renameCommands = map (rename: ''
                for _ in $(seq 1 30); do
                  if ${pkgs.iproute2}/bin/ip link show dev ${rename.finalInterfaceName} >/dev/null 2>&1; then
                    break
                  fi
                  if ${pkgs.iproute2}/bin/ip link show dev ${rename.initialInterfaceName} >/dev/null 2>&1; then
                    ${pkgs.iproute2}/bin/ip link set dev ${rename.initialInterfaceName} down || true
                    ${pkgs.iproute2}/bin/ip link set dev ${rename.initialInterfaceName} name ${rename.finalInterfaceName}
                    ${pkgs.iproute2}/bin/ip link set dev ${rename.finalInterfaceName} up || true
                    break
                  fi
                  sleep 1
                done
              '') containerInterfaceRenames;
              routedSlaacCommands = map (interfaceName: ''
                for _ in $(seq 1 30); do
                  if test -e /proc/sys/net/ipv6/conf/${interfaceName}/accept_ra; then
                    ${pkgs.systemd}/lib/systemd/systemd-sysctl --prefix=/net/ipv6/conf/${interfaceName}
                    test "$(cat /proc/sys/net/ipv6/conf/${interfaceName}/accept_ra)" = 2
                    break
                  fi
                  sleep 1
                done
                test -e /proc/sys/net/ipv6/conf/${interfaceName}/accept_ra
                test "$(cat /proc/sys/net/ipv6/conf/${interfaceName}/accept_ra)" = 2
              '') routedSlaacInterfaces;
            in
            lib.concatStringsSep "\n" (renameCommands ++ routedSlaacCommands);
        };
      };
in
{
  config = lib.optionalAttrs (services != { }) {
    systemd.services = services;
  };
}
