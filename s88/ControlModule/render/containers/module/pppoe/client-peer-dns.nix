{ lib, pkgs, peerName, scriptSuffix, usePeerDns }:

let
  runtimeResolvConf = "/run/pppd/${peerName}.resolv.conf";
in
{
  options = lib.optionalString usePeerDns ''
    usepeerdns
    noresolvconf
  '';

  ipUpBlock = lib.optionalString usePeerDns ''
    ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg runtimeResolvConf}
    if [ -n "''${DNS1:-}" ] || [ -n "''${DNS2:-}" ]; then
      {
        if [ -n "''${DNS1:-}" ]; then
          printf 'nameserver %s\n' "$DNS1"
        fi
        if [ -n "''${DNS2:-}" ]; then
          printf 'nameserver %s\n' "$DNS2"
        fi
      } > ${lib.escapeShellArg runtimeResolvConf}
    fi
  '';

  ipDownOption = lib.optionalString usePeerDns "ip-down-script ${
    pkgs.writeShellScript "s88-pppoe-ip-down-${scriptSuffix}" ''
      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg runtimeResolvConf}
    ''
  }";
}
