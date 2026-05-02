{ lib, interfaces }:

{
  "net.ipv6.conf.all.accept_ra" = 2;
  "net.ipv6.conf.default.accept_ra" = 2;
}
// builtins.listToAttrs (
  map (interfaceName: {
    name = "net.ipv6.conf.${interfaceName}.accept_ra";
    value = 2;
  }) interfaces
)
