{ lib }:

let
  nftQuotedIfNames = names: builtins.concatStringsSep ", " (map (name: ''"${name}"'') names);
  nftIfSet = names: "{ ${nftQuotedIfNames names} }";
in
{
  core =
    { wanIfs, lanIfs, ... }:
    if wanIfs != [ ] && lanIfs != [ ] then
      ''
        table inet filter {
          chain input {
            type filter hook input priority 0; policy accept;
            iifname "lo" accept
            ct state { established, related } accept
          }

          chain forward {
            type filter hook forward priority 0; policy drop;
            ct state { established, related } accept
            iifname ${nftIfSet lanIfs} oifname ${nftIfSet wanIfs} accept
          }

          chain output {
            type filter hook output priority 0; policy accept;
          }
        }

        table ip nat {
          chain postrouting {
            type nat hook postrouting priority 100; policy accept;
            oifname ${nftIfSet wanIfs} masquerade
          }
        }

        table inet mangle {
          chain forward {
            type filter hook forward priority mangle; policy accept;
            oifname ${nftIfSet wanIfs} tcp flags syn tcp option maxseg size set rt mtu
          }
        }
      ''
    else
      null;

  policy = _: null;

  access = _: null;

  upstream-selector = _: null;
}
