{ lib, common }:

let
  inherit (common) hasIpv6Address stripCidr;
in
{
  addressForFamily =
    family: iface:
    let
      addresses = iface.addresses or [ ];
      matches =
        lib.filter (
          address:
          if family == 6 then
            hasIpv6Address address
          else
            builtins.isString address && !(hasIpv6Address address)
        ) addresses;
    in
    if matches == [ ] then null else stripCidr (builtins.head matches);

  ipv4PeerFor31 =
    address:
    let
      parts = if builtins.isString address then lib.splitString "." address else [ ];
      last = if builtins.length parts == 4 then builtins.fromJSON (builtins.elemAt parts 3) else null;
      peerLast = if last == null then null else if lib.mod last 2 == 0 then last + 1 else last - 1;
    in
    if peerLast == null then
      null
    else
      lib.concatStringsSep "." ((lib.take 3 parts) ++ [ (builtins.toString peerLast) ]);

  ipv6PeerFor127 =
    address:
    let
      len = if builtins.isString address then builtins.stringLength address else 0;
      prefix = builtins.substring 0 (len - 1) address;
      last = builtins.substring (len - 1) 1 address;
      peerLastByNibble = {
        "0" = "1";
        "1" = "0";
        "2" = "3";
        "3" = "2";
        "4" = "5";
        "5" = "4";
        "6" = "7";
        "7" = "6";
        "8" = "9";
        "9" = "8";
        a = "b";
        b = "a";
        c = "d";
        d = "c";
        e = "f";
        f = "e";
        A = "B";
        B = "A";
        C = "D";
        D = "C";
        E = "F";
        F = "E";
      };
    in
    if len == 0 || !(builtins.hasAttr last peerLastByNibble) then
      null
    else
      "${prefix}${peerLastByNibble.${last}}";
}
