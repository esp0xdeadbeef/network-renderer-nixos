{ lib }:

let
  stringHasPrefix = prefix: value: builtins.isString value && lib.hasPrefix prefix value;
in
{
  inherit stringHasPrefix;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  hasIpv6Address = address: builtins.isString address && lib.hasInfix ":" address;

  stringContains = needle: value: builtins.isString value && lib.hasInfix needle value;

  stripCidr =
    value:
    if builtins.isString value then builtins.head (lib.splitString "/" value) else null;

  interfaceNameFor =
    iface:
    if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
      iface.containerInterfaceName
    else if iface ? interfaceName && builtins.isString iface.interfaceName then
      iface.interfaceName
    else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
      iface.hostInterfaceName
    else if iface ? ifName && builtins.isString iface.ifName then
      iface.ifName
    else
      throw ''
        s88/CM/network/render/container-networks.nix: could not resolve container interface name

        iface:
        ${builtins.toJSON iface}
      '';

  policyTenantKeyFor =
    name:
    let
      normalizeTenantKey =
        raw:
        if raw == "adm" || raw == "admin" then
          "admin"
        else if raw == "cli" || raw == "client" then
          "client"
        else if raw == "cl2" || raw == "client2" then
          "client2"
        else if raw == "mgt" || raw == "mgmt" then
          "mgmt"
        else if raw == "med" || raw == "media" then
          "media"
        else if raw == "prn" || raw == "printer" then
          "printer"
        else if raw == "nas" then
          "nas"
        else if raw == "iot" then
          "iot"
        else if raw == "branch" then
          "branch"
        else if raw == "hostile" then
          "hostile"
        else
          raw;
      takeTenantSegment =
        prefix:
        let
          stripped = builtins.substring (builtins.stringLength prefix) (
            builtins.stringLength name - builtins.stringLength prefix
          ) name;
          parts = lib.splitString "-" stripped;
        in
        if parts == [ ] then null else normalizeTenantKey (builtins.elemAt parts 0);
    in
    if stringHasPrefix "downstr-" name then
      normalizeTenantKey (builtins.substring 8 (builtins.stringLength name - 8) name)
    else if stringHasPrefix "downstream-" name then
      normalizeTenantKey (builtins.substring 11 (builtins.stringLength name - 11) name)
    else if stringHasPrefix "down-" name then
      takeTenantSegment "down-"
    else if stringHasPrefix "up-" name then
      takeTenantSegment "up-"
    else if stringHasPrefix "upstream-" name then
      takeTenantSegment "upstream-"
    else if stringHasPrefix "pol-" name then
      takeTenantSegment "pol-"
    else if stringHasPrefix "policy-" name then
      takeTenantSegment "policy-"
    else
      null;

  downstreamPairKeyFor =
    name:
    if stringHasPrefix "access-" name then
      builtins.substring 7 (builtins.stringLength name - 7) name
    else if stringHasPrefix "policy-" name then
      builtins.substring 7 (builtins.stringLength name - 7) name
    else
      null;
}
