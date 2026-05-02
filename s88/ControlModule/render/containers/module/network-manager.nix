{ lib, pkgs, renderedModel }:

let
  networkManagerWanInterfaces =
    if renderedModel ? networkManagerWanInterfaces && builtins.isList renderedModel.networkManagerWanInterfaces then
      lib.filter builtins.isString renderedModel.networkManagerWanInterfaces
    else
      [ ];

  interfaceNameFor =
    iface:
    if builtins.isString (iface.containerInterfaceName or null) then
      iface.containerInterfaceName
    else if builtins.isString (iface.hostInterfaceName or null) then
      iface.hostInterfaceName
    else if builtins.isString (iface.interfaceName or null) then
      iface.interfaceName
    else if builtins.isString (iface.ifName or null) then
      iface.ifName
    else
      null;

  networkdManagedInterfaces = lib.filter (
    interfaceName: builtins.isString interfaceName && !(builtins.elem interfaceName networkManagerWanInterfaces)
  ) (map interfaceNameFor (builtins.attrValues (renderedModel.interfaces or { })));

  connections = builtins.listToAttrs (
    map (interfaceName: {
      name = "NetworkManager/system-connections/s88-${interfaceName}.nmconnection";
      value = {
        mode = "0600";
        text = ''
          [connection]
          id=s88-${interfaceName}
          type=ethernet
          interface-name=${interfaceName}
          autoconnect=true

          [ethernet]

          [ipv4]
          method=auto

          [ipv6]
          method=auto
        '';
      };
    }) networkManagerWanInterfaces
  );

  activationServices = builtins.listToAttrs (
    map (interfaceName: {
      name = "s88-networkmanager-${interfaceName}";
      value = {
        description = "Activate NetworkManager WAN profile on ${interfaceName}";
        wantedBy = [ "multi-user.target" ];
        after = [ "NetworkManager.service" ];
        wants = [ "NetworkManager.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [ pkgs.networkmanager ];
        script = ''
          nmcli connection reload
          nmcli connection up s88-${interfaceName} ifname ${interfaceName}
        '';
      };
    }) networkManagerWanInterfaces
  );
in
{
  config = lib.optionalAttrs (networkManagerWanInterfaces != [ ]) {
    networking.networkmanager.enable = lib.mkForce true;
    networking.networkmanager.unmanaged = map (interfaceName: "interface-name:${interfaceName}") networkdManagedInterfaces;
    environment.etc = connections;
    systemd.services = activationServices;
  };
}
