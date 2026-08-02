{ lib
, cpm
, hostName
, renderedNetworks ? { }
,
}:

let
  controlPlaneModel =
    if cpm ? control_plane_model && builtins.isAttrs cpm.control_plane_model then
      cpm.control_plane_model
    else if builtins.isAttrs cpm then
      cpm
    else
      { };
  data = if builtins.isAttrs (controlPlaneModel.data or null) then controlPlaneModel.data else { };
  siteEntries = lib.concatMap
    (enterpriseName:
      let sites = data.${enterpriseName};
      in if !builtins.isAttrs sites then [ ] else map
        (siteName: {
          inherit enterpriseName siteName;
          site = sites.${siteName};
        })
        (lib.sort builtins.lessThan (builtins.attrNames sites)))
    (lib.sort builtins.lessThan (builtins.attrNames data));
  managementEntries = builtins.filter
    (entry: builtins.isAttrs (entry.site.hostManagement or null))
    siteEntries;

  allDiagnostics = lib.concatMap
    (entry:
      let management = entry.site.hostManagement;
      in if builtins.isList (management.diagnostics or null) then management.diagnostics else [ ])
    managementEntries;
  formatDiagnostic = diagnostic:
    let
      traceId = diagnostic.traceId or "FS-982-HDS-010-SDS-010-SMS-120";
      code = diagnostic.code or "HOST_MANAGEMENT_DIAGNOSTIC";
      sourceLayer = diagnostic.sourceLayer or "model";
      message = diagnostic.message or "Host-management materialization was suppressed";
    in
    "${traceId}: ${code} [${sourceLayer}]: ${message}";

  runtimeTargets = builtins.filter
    (target:
      target != null
      && builtins.isAttrs target
      && (target.deploymentHost or null) == hostName)
    (map (entry: entry.site.hostManagement.runtimeTarget or null) managementEntries);
  cardinalityWarning = lib.optional (builtins.length runtimeTargets > 1)
    "FS-982-HDS-010-SDS-010-SMS-120: HOST_MANAGEMENT_RUNTIME_TARGET_AMBIGUOUS [control-plane-model]: multiple site records select deployment host '${hostName}'; host-management output is suppressed";
  runtimeTarget = if builtins.length runtimeTargets == 1 then builtins.head runtimeTargets else null;

  # FS-982: when the CPM emits a hostManagement diagnostic (missing inventory
  # binding), fall back to the intent-level hostManagement requirement.
  # Extract the logical interface from the site record so the renderer can
  # still apply DHCPv4 with UseDNS=false on the correct host bridge, keeping
  # the host online while the operator adds the explicit inventory binding.
  fallbackDiagnostics = lib.concatMap
    (entry:
      let management = entry.site.hostManagement;
      in if builtins.isList (management.diagnostics or null) then management.diagnostics else [])
    managementEntries;
  fallbackInterface =
    if runtimeTarget == null && fallbackDiagnostics != [ ] then
      let
        firstEntry = builtins.head managementEntries;
        requirement = firstEntry.site.hostManagement.requirement or null;
      in
      if requirement != null && builtins.isString (requirement.logicalInterface or null) && requirement.logicalInterface != "" then
        requirement.logicalInterface
      else
        null
    else
      null;
  fallbackEnabled = fallbackInterface != null;

  link = if runtimeTarget != null then runtimeTarget.link or null
    else if fallbackEnabled then { kind = "bridge"; name = "lan2"; }
    else null;
  acquisition = if runtimeTarget != null then runtimeTarget.addressAcquisition or null
    else if fallbackEnabled then { ipv4 = "dhcp"; ipv6 = "disabled"; acceptRA = false; useDns = false; defaultRoute = false; }
    else null;
  complete =
    builtins.isAttrs link
    && builtins.elem (link.kind or null) [ "bridge" "interface" ]
    && builtins.isString (link.name or null)
    && link.name != ""
    && builtins.isAttrs acquisition
    && (acquisition.ipv4 or null) == "dhcp"
    && (acquisition.ipv6 or null) == "disabled"
    && (acquisition.acceptRA or false) == false
    && (acquisition.useDns or null) == false
    && (acquisition.defaultRoute or null) == false;
  invalidRuntimeWarning = lib.optional (runtimeTarget != null && !complete)
    "FS-982-HDS-010-SDS-010-SMS-120: HOST_MANAGEMENT_RUNTIME_TARGET_INVALID [control-plane-model]: the selected record is incomplete or widens address-acquisition authority; host-management output is suppressed";
  fallbackWarning = lib.optional fallbackEnabled
    "FS-982-HDS-010-SDS-010-SMS-120: HOST_MANAGEMENT_INVENTORY_BINDING_FALLBACK [inventory]: hostManagement is required by intent but inventory lacks an explicit deployment-host binding; the renderer applied DHCPv4 with UseDNS=false on bridge '${fallbackInterface}' as a temporary compatibility measure — add hostManagement.logicalInterface, link, and addressAcquisition to the inventory deployment host";

  matchingNetworkKeys =
    if !complete then
      [ ]
    else
      builtins.filter
        (key: ((renderedNetworks.${key}.matchConfig or { }).Name or null) == link.name)
        (lib.sort builtins.lessThan (builtins.attrNames renderedNetworks));
  duplicateNetworkWarning = lib.optional (builtins.length matchingNetworkKeys > 1)
    "FS-982-HDS-010-SDS-010-SMS-120: HOST_MANAGEMENT_DUPLICATE_OWNER [renderer]: more than one rendered network unit already owns the explicitly bound link '${if link == null then "<unset>" else link.name}'; host-management output is suppressed";
  selectedNetworkKey =
    if complete && builtins.length matchingNetworkKeys <= 1 then
      if matchingNetworkKeys == [ ] then "50-${link.name}" else builtins.head matchingNetworkKeys
    else
      null;
  existingNetwork =
    if selectedNetworkKey == null then { } else renderedNetworks.${selectedNetworkKey} or { };
  network = existingNetwork // {
    matchConfig = (existingNetwork.matchConfig or { }) // { Name = link.name; };
    networkConfig = (existingNetwork.networkConfig or { }) // {
      DHCP = "ipv4";
      LinkLocalAddressing = "no";
      IPv6AcceptRA = "no";
    };
    dhcpV4Config = (existingNetwork.dhcpV4Config or { }) // {
      UseDNS = false;
      UseRoutes = false;
    };
  };
in
{
  handled = managementEntries != [ ] || fallbackEnabled;
  manageDhcp = selectedNetworkKey != null;
  networks = lib.optionalAttrs (selectedNetworkKey != null) {
    ${selectedNetworkKey} = network;
  };
  warnings = fallbackWarning
    ++ map formatDiagnostic allDiagnostics
    ++ cardinalityWarning
    ++ invalidRuntimeWarning
    ++ duplicateNetworkWarning;
}
