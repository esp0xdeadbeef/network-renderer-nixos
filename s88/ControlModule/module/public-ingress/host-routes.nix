{ lib }:

let
  routeForService = service:
    if builtins.isString (service.gateway4 or null) && service.gateway4 != "" then
      {
        Destination =
          if builtins.isString (service.routeDestination4 or null) && service.routeDestination4 != "" then
            service.routeDestination4
          else
            "${service.targetIPv4}/32";
        Gateway = service.gateway4;
      }
    else
      null;

  isRoute = value: value != null;
in
{ bridgeNetworkName, serviceIngresses }:
let
  routes = builtins.filter isRoute (map routeForService serviceIngresses);
in
if routes == [ ] then
  { }
else
  { systemd.network.networks.${bridgeNetworkName}.routes = routes; }
