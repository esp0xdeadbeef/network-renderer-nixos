{
  config,
  pkgs,
  lib,
  vlanId,
  outPath,
  fabricNodeContext,
  tenantNetwork ? null,
  ...
}:

let
  siteImported = import "${outPath}/library/100-fabric-routing/lib/site-defaults.nix";
  site =
    if builtins.isFunction siteImported then
      siteImported { inherit lib; }
    else
      siteImported;

  splitCIDR =
    cidr:
      let
        parts = lib.splitString "/" cidr;
      in
      if builtins.length parts == 2 then
        {
          address = builtins.elemAt parts 0;
          prefix = builtins.elemAt parts 1;
        }
      else
        throw ''
          kea:

          Invalid CIDR '${cidr}'.
        '';

  firstIPv4InSubnet =
    cidr:
      let
        ip = (splitCIDR cidr).address;
        octets = lib.splitString "." ip;
      in
      if builtins.length octets == 4 then
        "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.1"
      else
        throw ''
          kea:

          Cannot derive router IPv4 from subnet '${cidr}'.
        '';

  poolForSubnet =
    cidr:
      let
        ip = (splitCIDR cidr).address;
        octets = lib.splitString "." ip;
      in
      if builtins.length octets == 4 then
        "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.100 - ${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.200"
      else
        throw ''
          kea:

          Cannot derive DHCP pool from subnet '${cidr}'.
        '';

  tenantNetworkResolved =
    if tenantNetwork != null
      && builtins.isAttrs tenantNetwork
      && tenantNetwork ? ipv4
      && builtins.isString tenantNetwork.ipv4
    then
      tenantNetwork
    else
      let
        tenantNetworks =
          if fabricNodeContext ? networks && builtins.isAttrs fabricNodeContext.networks then
            fabricNodeContext.networks
          else
            { };

        tenantNetworkNames =
          builtins.filter (n: n != "loopback") (builtins.attrNames tenantNetworks);
      in
      if builtins.length tenantNetworkNames == 1 then
        tenantNetworks.${builtins.head tenantNetworkNames}
      else
        throw ''
          kea:

          Expected exactly 1 tenant network for access node.

          Found:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ tenantNetworkNames)}
        '';

  lanIf = "lan-${toString vlanId}";
  lanName = "lan${toString vlanId}";

  subnet = tenantNetworkResolved.ipv4;
  router4 = firstIPv4InSubnet tenantNetworkResolved.ipv4;
  pool = poolForSubnet tenantNetworkResolved.ipv4;

  domainRaw = site.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  outFile = "/run/etc/kea/${lanName}.json";

  genKea = pkgs.writeShellScript "gen-kea-${lanName}" ''
    set -euo pipefail
    mkdir -p /run/etc/kea /var/lib/kea

    cat > "${outFile}" <<'EOF'
    {
      "Dhcp4": {
        "interfaces-config": {
          "interfaces": ["${lanIf}"]
        },
        "lease-database": {
          "type": "memfile",
          "persist": true,
          "name": "/var/lib/kea/${lanName}.leases"
        },
        "subnet4": [
          {
            "id": ${toString vlanId},
            "subnet": "${subnet}",
            "pools": [
              { "pool": "${pool}" }
            ],
            "option-data": [
              { "name": "routers", "data": "${router4}" },
              { "name": "domain-name-servers", "data": "${router4}" },
              { "name": "domain-name", "data": "${domain}" }
            ]
          }
        ]
      }
    }
    EOF
  '';
in
{
  environment.systemPackages = [
    pkgs.kea
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.gawk
    pkgs.coreutils
  ];

  systemd.services."gen-kea-${lanName}" = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kea-dhcp4-${lanName}.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genKea;
      RemainAfterExit = true;
    };
  };
}
