{
  lib,
  fabricNodeContext,
  fabricSpec,
  ...
}:

let
  asList =
    value:
      if value == null then
        [ ]
      else if builtins.isList value then
        value
      else
        [ value ];

  mkRoute =
    route:
      if !(builtins.isAttrs route) || !(route ? dst) then
        throw ''
          container-upstream-selector/network/link-to-policy.nix: invalid route
          ${builtins.toJSON route}
        ''
      else
        {
          Destination = route.dst;
        }
        // lib.optionalAttrs (route ? via4) { Gateway = route.via4; }
        // lib.optionalAttrs (route ? via6) { Gateway = route.via6; };

  port =
    if fabricSpec ? ports && fabricSpec.ports ? policy then
      fabricSpec.ports.policy
    else
      throw "container-upstream-selector/network/link-to-policy.nix: missing fabricSpec.ports.policy";

  linkName =
    if port ? link then
      port.link
    else
      throw "container-upstream-selector/network/link-to-policy.nix: missing policy link";

  ifaces =
    if fabricNodeContext ? effectiveRuntimeRealization
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization
      && fabricNodeContext.effectiveRuntimeRealization ? interfaces
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization.interfaces
    then
      fabricNodeContext.effectiveRuntimeRealization.interfaces
    else if fabricNodeContext ? interfaces && builtins.isAttrs fabricNodeContext.interfaces then
      fabricNodeContext.interfaces
    else
      throw "container-upstream-selector/network/link-to-policy.nix: missing node interfaces";

  iface =
    if builtins.hasAttr linkName ifaces then
      ifaces.${linkName}
    else
      throw "container-upstream-selector/network/link-to-policy.nix: link '${linkName}' not found";

  addresses =
    (map (addr: { Address = addr; }) (asList (iface.addr4 or null)))
    ++ (map (addr: { Address = addr; }) (asList (iface.addr6 or null)));

  routes =
    map mkRoute (
      (iface.routes.ipv4 or [ ])
      ++ (iface.routes.ipv6 or [ ])
    );
in
{
  systemd.network.networks."20-policy" = {
    matchConfig.Name = "policy";

    linkConfig = {
      ActivationPolicy = "always-up";
      RequiredForOnline = false;
    };

    inherit addresses routes;

    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      ConfigureWithoutCarrier = true;
    };
  };
}
