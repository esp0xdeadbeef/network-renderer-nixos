{ lib, interfaceEntries, common }:

let
  dhcp4Raw = lib.filter (entry: entry ? dhcp4) interfaceEntries;
in
{
  dhcp4Scopes = builtins.genList (
    idx:
    let
      entry = builtins.elemAt dhcp4Raw idx;
    in
    entry.dhcp4 // { subnetId = idx + 1; }
  ) (builtins.length dhcp4Raw);

  radvdScopes = map (entry: entry.radvd) (lib.filter (entry: entry ? radvd) interfaceEntries);

  derivedDhcp4Entries = lib.filter (entry: entry.derivedDhcp4) interfaceEntries;

  derivedRadvdEntries = lib.filter (entry: entry.derivedRadvd) interfaceEntries;
}
