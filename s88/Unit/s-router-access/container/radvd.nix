# ./s-router-access/container/radvd.nix
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

  tenantNetworkResolved =
    if tenantNetwork != null
      && builtins.isAttrs tenantNetwork
      && tenantNetwork ? ipv6
      && builtins.isString tenantNetwork.ipv6
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
          radvd:

          Expected exactly 1 tenant network for access node.

          Found:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ tenantNetworkNames)}
        '';

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
          radvd:

          Invalid CIDR '${cidr}'.
        '';

  firstIPv6InSubnet =
    cidr:
      let
        base = (splitCIDR cidr).address;
      in
      if lib.hasSuffix "::" base then
        "${base}1"
      else
        "${base}::1";

  domainRaw = site.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  lanIf = "lan-${toString vlanId}";
  prefixes = [ tenantNetworkResolved.ipv6 ];

  rdnss = firstIPv6InSubnet tenantNetworkResolved.ipv6;
  radvdConf = "/run/radvd.conf";

  gen = pkgs.writeShellScript "gen-radvd-${toString vlanId}" ''
    set -euo pipefail
    mkdir -p /run

    IFACE="${lanIf}"
    : > "${radvdConf}"

    if [ ! -d "/sys/class/net/$IFACE" ]; then
      echo "[radvd] $IFACE missing; not generating RA config" >&2
      exit 0
    fi

    ${pkgs.iproute2}/bin/ip link set "$IFACE" up || true

    cat >> "${radvdConf}" <<EOF
    interface $IFACE {
      AdvSendAdvert on;
      MinRtrAdvInterval 10;
      MaxRtrAdvInterval 30;

      AdvManagedFlag off;
      AdvOtherConfigFlag off;

      RDNSS ${rdnss} {
        AdvRDNSSLifetime 600;
      };

      DNSSL ${domain} {
        AdvDNSSLLifetime 600;
      };
    EOF

    ${lib.concatMapStrings (p: ''
      cat >> "${radvdConf}" <<EOF
      prefix ${p} {
        AdvOnLink on;
        AdvAutonomous on;
      };
      EOF
    '') prefixes}

    echo "};" >> "${radvdConf}"
  '';
in
{
  environment.systemPackages = [
    pkgs.radvd
    pkgs.iproute2
  ];

  systemd.services."radvd-generate-${toString vlanId}" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = gen;
      RemainAfterExit = true;
    };
  };

  systemd.services."radvd-${toString vlanId}" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "radvd-generate-${toString vlanId}.service" ];
    requires = [ "radvd-generate-${toString vlanId}.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C ${radvdConf}";
      Restart = "always";
      RestartSec = "2s";
    };
  };
}
