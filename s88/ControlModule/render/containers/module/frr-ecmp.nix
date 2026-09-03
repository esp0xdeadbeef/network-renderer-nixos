{
  lib,
  pkgs,
  containerName,
  containerNetworkRender,
}:

let
  ecmpMembers = containerNetworkRender.ecmpMembers or [ ];
  fabricBfdPeers = containerNetworkRender.fabricBfdPeers or [ ];

  hostname = containerName;

  bfdFastProfile = ''
    profile fast
     detect-multiplier 3
     receive-interval 100
     transmit-interval 100
    !
  '';

  selectorConfig =
    let
      peers = lib.unique (map (member: member.gateway) ecmpMembers);
      bfdPeers = lib.concatMapStrings (
        peer:
        let
          member = builtins.head (lib.filter (m: m.gateway == peer) ecmpMembers);
        in
        ''
          peer ${peer} interface ${member.interface} local-address ${member.localAddress}
           profile fast
           no shutdown
          !
        ''
      ) peers;
      staticRoutes = lib.concatMapStrings (
        member:
        let
          family = if lib.hasInfix ":" member.destination then "ipv6" else "ip";
        in
        ''
          ${family} route ${member.destination} ${member.gateway} table ${member.table} bfd
        ''
      ) ecmpMembers;
    in
    ''
      frr defaults traditional
      hostname ${hostname}
      service integrated-vtysh-config
      !
      bfd
      ${bfdFastProfile}
      ${bfdPeers}
      !
      ${staticRoutes}
    '';

  coreConfig =
    let
      bfdPeers = lib.concatMapStrings (
        entry:
        let
          localLine =
            if entry ? localAddress && entry.localAddress != null then
              " local-address ${entry.localAddress}"
            else
              "";
        in
        ''
          peer ${entry.peer} interface ${entry.interface}${localLine}
           no shutdown
          !
        ''
      ) fabricBfdPeers;
    in
    ''
      frr defaults traditional
      hostname ${hostname}
      service integrated-vtysh-config
      !
      bfd
      ${bfdPeers}
      !
    '';

  frrConfig =
    if ecmpMembers != [ ] then
      selectorConfig
    else if fabricBfdPeers != [ ] then
      coreConfig
    else
      null;
in
{
  config = lib.mkIf (frrConfig != null) {
    services.frr = {
      bfdd.enable = true;
      config = frrConfig;
    };
  };
}
