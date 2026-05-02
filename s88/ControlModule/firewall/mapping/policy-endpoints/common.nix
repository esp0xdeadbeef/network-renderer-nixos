{ lib }:

let
  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

  stringHasPrefix = prefix: value: builtins.isString value && lib.hasPrefix prefix value;

  normalizeTenantKey =
    value:
    builtins.replaceStrings [ "_" "." "--" ] [ "-" "-" "-" ] (
      lib.toLower (toString value)
    );

  takeTenantSegment =
    prefix: value:
    let
      rest = builtins.substring (builtins.stringLength prefix) (builtins.stringLength value) value;
      segments = lib.splitString "-" rest;
    in
    if segments == [ ] then null else normalizeTenantKey (builtins.head segments);

  canonicalPolicyTenantKey =
    value:
    if value == "mgt" then
      "mgmt"
    else if value == "prn" then
      "printer"
    else
      value;

  policyTenantKeyFor =
    name:
    let
      raw =
        if stringHasPrefix "downstr-" name then
          takeTenantSegment "downstr-" name
        else if stringHasPrefix "downstream-" name then
          takeTenantSegment "downstream-" name
        else if stringHasPrefix "down-" name then
          takeTenantSegment "down-" name
        else if stringHasPrefix "upstream-" name then
          takeTenantSegment "upstream-" name
        else if stringHasPrefix "up-" name then
          takeTenantSegment "up-" name
        else if stringHasPrefix "policy-" name then
          takeTenantSegment "policy-" name
        else if stringHasPrefix "pol-" name then
          takeTenantSegment "pol-" name
        else
          null;
    in
    if raw == null then null else canonicalPolicyTenantKey raw;

  isPolicyLaneInterface =
    name:
    stringHasPrefix "downstr-" name
    || stringHasPrefix "downstream-" name
    || stringHasPrefix "down-" name
    || stringHasPrefix "upstream-" name
    || stringHasPrefix "up-" name
    || stringHasPrefix "policy-" name
    || stringHasPrefix "pol-" name;
in
rec {
  inherit sortedStrings stringHasPrefix policyTenantKeyFor isPolicyLaneInterface;

  asStringList =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      lib.filter builtins.isString value
    else
      [ ];

  fieldOr =
    attrs: name: fallback:
    if builtins.isAttrs attrs && builtins.hasAttr name attrs then attrs.${name} else fallback;

  lastStringSegment =
    separator: value:
    let
      parts = lib.splitString separator value;
      count = builtins.length parts;
    in
    if count == 0 then null else builtins.elemAt parts (count - 1);

  ifaceOf =
    entry:
    if builtins.isAttrs entry && entry ? iface && builtins.isAttrs entry.iface then
      entry.iface
    else if builtins.isAttrs entry then
      entry
    else
      { };

  entryFieldOr =
    entry: name: fallback:
    if builtins.isAttrs entry && builtins.hasAttr name entry then
      entry.${name}
    else
      let
        iface = ifaceOf entry;
      in
      if builtins.isAttrs iface && builtins.hasAttr name iface then iface.${name} else fallback;

  samePolicyTenantLane =
    fromIf: toIf:
    let
      fromTenant = policyTenantKeyFor fromIf;
      toTenant = policyTenantKeyFor toIf;
    in
    !(isPolicyLaneInterface fromIf && isPolicyLaneInterface toIf)
    || fromTenant == null
    || toTenant == null
    || fromTenant == toTenant;
}
