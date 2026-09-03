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
          ${family} route ${member.destination} ${member.gateway} table ${builtins.toString member.table} bfd
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
      bfdPeers = lib.concatMapStrings (entry: ''
        peer ${entry.peer} interface ${entry.interface} local-address ${entry.localAddress}
         profile fast
         no shutdown
        !
      '') fabricBfdPeers;
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
    '';

  frrConfig =
    if ecmpMembers != [ ] then
      selectorConfig
    else if fabricBfdPeers != [ ] then
      coreConfig
    else
      null;

  bfdInterfaces =
    if ecmpMembers != [ ] then
      lib.unique (map (member: member.interface) ecmpMembers)
    else
      lib.unique (map (entry: entry.interface) fabricBfdPeers);

  waitForAddresses = ''
    for _iface in ${lib.concatStringsSep " " bfdInterfaces}; do
      for _try in $(seq 1 120); do
        if ip -6 -o addr show dev "$_iface" 2>/dev/null | grep 'scope global' | grep -qv tentative; then
          break
        fi
        sleep 0.25
      done
    done
  '';
in
{
  config = lib.mkIf (frrConfig != null) {
    services.frr = {
      bfdd.enable = true;
      config = frrConfig;
    };
    systemd.services.frr = {
      after = [ "network.target" ];
      before = lib.mkForce [ ];
      preStart = waitForAddresses;
    };
  };
}
