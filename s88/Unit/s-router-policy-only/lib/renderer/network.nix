{ lib }:

d: {
  name = "20-${d.renderedIfName}";
  value = {
    matchConfig.Name = d.renderedIfName;

    linkConfig = {
      ActivationPolicy = "always-up";
      RequiredForOnline = false;
    };

    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      ConfigureWithoutCarrier = true;
    };

    addresses = d.addresses;

    routes = map (
      route:
      route
      // lib.optionalAttrs (route ? Gateway) {
        GatewayOnLink = true;
      }
      // lib.optionalAttrs (
        (d.preferredSource4 or null) != null
        && (route.Destination or "") == "0.0.0.0/0"
      ) {
        PreferredSource = d.preferredSource4;
      }
    ) d.routes;
  };
}
