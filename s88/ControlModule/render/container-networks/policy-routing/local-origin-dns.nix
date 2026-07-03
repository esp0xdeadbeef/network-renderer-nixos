{ lib
, interfaces
, routeHelpers
, services ? { }
,
}:

let
  dns = if builtins.isAttrs (services.dns or null) then services.dns else { };
  outgoingInterfaces =
    if builtins.isList (dns.outgoingInterfaces or null) then dns.outgoingInterfaces else [ ];

  stripCidr =
    address:
    if !(builtins.isString address) || address == "" then
      null
    else
      builtins.head (lib.splitString "/" address);

  addressFamily =
    address:
    if !(builtins.isString address) || address == "" then
      null
    else if lib.hasInfix ":" (stripCidr address) then
      6
    else
      4;

  candidateCidrsForFamily =
    family: iface:
    lib.filter
      (address: addressFamily address == family)
      ((iface.addresses or [ ])
        ++ lib.optional (builtins.isString (iface.addr4 or null) && iface.addr4 != "") iface.addr4
        ++ lib.optional (builtins.isString (iface.addr6 or null) && iface.addr6 != "") iface.addr6);

  addressForFamily =
    family: iface:
    let
      candidates = candidateCidrsForFamily family iface;
    in
    if candidates == [ ] then null else stripCidr (builtins.head candidates);

  cidrForFamily =
    family: iface:
    let
      candidates = candidateCidrsForFamily family iface;
    in
    if candidates == [ ] then null else builtins.head candidates;

  hostPrefixFor =
    family: address:
    if family == 6 then "${address}/128" else "${address}/32";

  bindingsForFamily =
    sourceIfNames: family:
    let
      sourceNames = lib.filter (name: builtins.hasAttr name interfaces) sourceIfNames;
      bindingForOutgoing =
        outgoing:
        if !(builtins.isString outgoing) || outgoing == "" then
          null
        else
          let
            match =
              lib.findFirst
                (ifName: addressForFamily family interfaces.${ifName} == outgoing)
                null
                sourceNames;
          in
          if match == null then
            null
          else
            let
              iface = interfaces.${match};
              cidr = cidrForFamily family iface;
              subnet = routeHelpers.addressNetworkPrefix cidr;
            in
            if subnet == null then
              null
            else
              {
                ifName = match;
                prefix = hostPrefixFor family outgoing;
                inherit subnet;
                inherit family;
              };
    in
    lib.unique (lib.filter (binding: binding != null) (map bindingForOutgoing outgoingInterfaces));

  bindingsFor = sourceIfNames:
    bindingsForFamily sourceIfNames 4 ++ bindingsForFamily sourceIfNames 6;

  routeForBinding = tableId: binding: {
    Destination = binding.subnet;
    Scope = "link";
    Table = tableId;
    policyOnly = true;
    _s88IntentKind = "service-dns-local-origin-return";
  };

  ruleForBinding = tableId: priority: binding: {
    Family = if binding.family == 6 then "ipv6" else "ipv4";
    From = binding.prefix;
    Priority = priority;
    Table = tableId;
  };
in
{
  routesByInterface =
    tableId: sourceIfNames:
    builtins.foldl'
      (
        acc: binding:
          acc
          // {
            ${binding.ifName} = (acc.${binding.ifName} or [ ]) ++ [ (routeForBinding tableId binding) ];
          }
      )
      { }
      (bindingsFor sourceIfNames);

  rules = tableId: priority: sourceIfNames:
    map (ruleForBinding tableId priority) (bindingsFor sourceIfNames);
}
