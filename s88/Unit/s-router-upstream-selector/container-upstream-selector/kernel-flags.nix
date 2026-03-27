{ ... }:

let
  coreIf = "core";
in
{
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;

    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.${coreIf}.accept_ra" = 2;
  };
}
