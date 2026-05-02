{ lib, pkgs, renderedModel }:

let
  containerInterfaceRenames = lib.filter (entry: entry != null) (
    map (
      iface:
      let
        initialInterfaceName = if builtins.isString (iface.hostVethName or null) then iface.hostVethName else null;
        finalInterfaceName =
          if builtins.isString (iface.containerInterfaceName or null) && iface.containerInterfaceName != "" then
            iface.containerInterfaceName
          else
            null;
      in
      if initialInterfaceName != null && finalInterfaceName != null && initialInterfaceName != finalInterfaceName then
        { inherit initialInterfaceName finalInterfaceName; }
      else
        null
    ) (builtins.attrValues (renderedModel.interfaces or { }))
  );

  services =
    if containerInterfaceRenames == [ ] then
      { }
    else
      {
        s88-rename-interfaces = {
          description = "Rename rendered container interfaces to semantic names";
          wantedBy = [ "multi-user.target" ];
          requiredBy = [ "systemd-networkd.service" ];
          before = [ "systemd-networkd.service" "multi-user.target" ];
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
            in
            lib.concatStringsSep "\n" renameCommands;
        };
      };
in
{
  config = lib.optionalAttrs (services != { }) {
    systemd.services = services;
  };
}
