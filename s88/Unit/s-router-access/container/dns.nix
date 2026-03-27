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
          dns:

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
          dns:

          Cannot derive router IPv4 from subnet '${cidr}'.
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

  tenantNetworkResolved =
    if tenantNetwork != null
      && builtins.isAttrs tenantNetwork
      && tenantNetwork ? ipv4
      && builtins.isString tenantNetwork.ipv4
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
          dns:

          Expected exactly 1 tenant network for access node.

          Found:
          ${builtins.concatStringsSep "\n  - " ([ "" ] ++ tenantNetworkNames)}
        '';

  domainRaw = site.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  lan4 = firstIPv4InSubnet tenantNetworkResolved.ipv4;
  lan6 = firstIPv6InSubnet tenantNetworkResolved.ipv6;

  v4Net = tenantNetworkResolved.ipv4;
  v6Net = tenantNetworkResolved.ipv6;

  upstream =
    site.defaultWanDns or [
      "1.1.1.1"
      "9.9.9.9"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
in
{
  services.bind.enable = lib.mkForce false;

  services.unbound = {
    enable = true;

    settings.server = {
      interface = [
        lan4
        lan6
        "127.0.0.1"
        "::1"
      ];

      outgoing-interface = [
        lan4
        lan6
      ];

      port = 53;
      do-ip4 = true;
      do-ip6 = true;
      do-udp = true;
      do-tcp = true;

      access-control = [
        "127.0.0.0/8 allow"
        "::1 allow"
        "${v4Net} allow"
        "${v6Net} allow"
      ];

      local-zone = [ "${domain} static" ];

      auto-trust-anchor-file = "/var/lib/unbound/root.key";
      hide-identity = true;
      hide-version = true;
      harden-glue = true;
      harden-dnssec-stripped = true;
      qname-minimisation = true;

      prefetch = true;
      cache-min-ttl = 60;
      cache-max-ttl = 86400;
    };

    settings.forward-zone = [
      {
        name = ".";
        forward-addr = upstream;
        forward-first = true;
      }
    ];
  };

  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];
}
