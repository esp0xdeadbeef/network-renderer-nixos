{ lib
, renderedModel
,
}:

let
  model = import ./bgp-services/model.nix {
    inherit lib renderedModel;
  };

  inherit (model)
    bgp
    ipv4Neighbors
    ipv6Neighbors
    loopback
    networks4
    networks6
    runtimeTarget
    stripCidr
    ;

  routingModeRaw = runtimeTarget.routingMode or "static";
  routingMode = if builtins.isString routingModeRaw then lib.toLower routingModeRaw else "static";

  asn = bgp.asn or null;

  routerId =
    let
      candidates = lib.filter builtins.isString [
        (stripCidr (loopback.addr4 or null))
      ];
    in
    if candidates != [ ] then builtins.head candidates else "1.1.1.1";

  neighborPrelude =
    neighbors:
    lib.concatMap
      (
        neighbor:
        [
          "  neighbor ${neighbor.peer} remote-as ${toString neighbor.peerAsn}"
        ]
        ++ lib.optional
          (
            neighbor.updateSource != null
          ) "  neighbor ${neighbor.peer} update-source ${neighbor.updateSource}"
      )
      neighbors;

  neighborFamilyLines =
    neighborKey: neighbors: family: networks:
    [
      "  address-family ${family} unicast"
    ]
    ++ map (network: "    network ${network}") networks
    ++ lib.concatMap
      (
        neighbor:
        [
          "    neighbor ${neighbor.${neighborKey}} activate"
        ]
        ++ lib.optional neighbor.routeReflectorClient "    neighbor ${neighbor.${neighborKey}} route-reflector-client"
      )
      neighbors
    ++ [
      "  exit-address-family"
    ];

  frrConfig =
    lib.concatStringsSep "\n"
      (
        [
          "ip forwarding"
          "ipv6 forwarding"
          "!"
          "router bgp ${toString asn}"
          "  bgp router-id ${routerId}"
          "  no bgp ebgp-requires-policy"
          "  no bgp network import-check"
        ]
        ++ neighborPrelude (map (neighbor: neighbor // { peer = neighbor.peerAddr4; }) ipv4Neighbors)
        ++ neighborPrelude (map (neighbor: neighbor // { peer = neighbor.peerAddr6; }) ipv6Neighbors)
        ++ [
          "  !"
        ]
        ++ neighborFamilyLines "peerAddr4" ipv4Neighbors "ipv4" networks4
        ++ [
          "  !"
        ]
        ++ neighborFamilyLines "peerAddr6" ipv6Neighbors "ipv6" networks6
      )
    + "\n";

  enableBgp = routingMode == "bgp" && builtins.isInt asn;
in
lib.optionalAttrs enableBgp {
  services.frr = {
    bgpd.enable = true;
    config = frrConfig;
  };
}
