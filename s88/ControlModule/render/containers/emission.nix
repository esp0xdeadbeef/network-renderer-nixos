{
  lib,
  debugEnabled ? false,
  deploymentHostName,
  containerName,
  renderedModel,
  firewallArg,
  alarmModel,
  uplinks,
  wanUplinkName,
}:

let
  uniqueStrings =
    values: lib.unique (lib.filter (value: builtins.isString value && value != "") values);

  allowedDeviceFor =
    device:
    if builtins.isAttrs device && builtins.isString (device.node or null) && device.node != "" then
      {
        node = device.node;
        modifier =
          if builtins.isString (device.modifier or null) && device.modifier != "" then
            device.modifier
          else
            "rw";
      }
    else if builtins.isString device && device != "" then
      {
        node = device;
        modifier = "rw";
      }
    else
      null;

  uniqueAllowedDevices =
    values:
    builtins.attrValues (
      builtins.listToAttrs (
        map
          (device: {
            name = device.node;
            value = device;
          })
          (lib.filter (device: device != null) (map allowedDeviceFor values))
      )
    );

  routeSourceFile =
    route:
    if builtins.isString (route.sourceFile or null) && route.sourceFile != "" then
      route.sourceFile
    else if
      builtins.isAttrs (route.delegatedPrefix or null)
      && builtins.isString (route.delegatedPrefix.sourceFile or null)
      && route.delegatedPrefix.sourceFile != ""
    then
      route.delegatedPrefix.sourceFile
    else
      "";

  runtimeRouteSourceFiles = uniqueStrings (
    lib.filter (path: lib.hasPrefix "/run/secrets/" path) (
      lib.concatLists (
        lib.mapAttrsToList (
          _ifName: iface:
          map routeSourceFile (
            if builtins.isAttrs iface && builtins.isList (iface.routes or null) then iface.routes else [ ]
          )
        ) (renderedModel.interfaces or { })
      )
    )
  );

  tenantPrefixSourceFiles =
    let
      owners =
        if builtins.isAttrs (renderedModel.site.tenantPrefixOwners or null) then
          renderedModel.site.tenantPrefixOwners
        else
          { };
      sourceFileFor =
        key: value:
        if builtins.isString (value.sourceFile or null) && value.sourceFile != "" then
          value.sourceFile
        else
          let
            parts = lib.splitString "|" key;
            prefixPart = if builtins.length parts >= 2 then builtins.elemAt parts 1 else "";
          in
          if lib.hasPrefix "source:" prefixPart then lib.removePrefix "source:" prefixPart else "";
    in
    uniqueStrings (lib.mapAttrsToList sourceFileFor owners);

  # Runtime-secret DHCPv4/DHCPv6 reservation identity source files
  # (FS-970-HDS-010-SDS-020-SMS-040). Each reservation whose CPM record
  # carries identitySource.sourceFile under /run/secrets/ must have that
  # protected source file bind-mounted read-only into the container that
  # runs Kea, so runtime materialization can read it. The protected MAC and
  # private hostname are never emitted here; only the source file path is.
  reservationRuntimeSourceFiles =
    let
      advertisements =
        if
          builtins.isAttrs (renderedModel.runtimeTarget or null)
          && builtins.isAttrs (renderedModel.runtimeTarget.advertisements or null)
        then
          renderedModel.runtimeTarget.advertisements
        else
          { };
      reservationsFor =
        name:
        if builtins.isList (advertisements.${name} or null) then advertisements.${name} else [ ];
      allReservations =
        lib.concatLists (
          map
            (adv: if builtins.isAttrs adv && builtins.isList (adv.reservations or null) then adv.reservations else [ ])
            (reservationsFor "dhcp4" ++ reservationsFor "dhcpv6")
        );
      sourceFileFor =
        reservation:
        if
          builtins.isAttrs reservation
          && builtins.isAttrs (reservation.identitySource or null)
          && builtins.isString (reservation.identitySource.sourceFile or null)
        then
          reservation.identitySource.sourceFile
        else
          "";
    in
    uniqueStrings (
      lib.filter (path: lib.hasPrefix "/run/secrets/" path) (map sourceFileFor allReservations)
    );

  runtimeRouteSourceFileMounts = lib.genAttrs runtimeRouteSourceFiles (sourceFile: {
    hostPath = sourceFile;
    isReadOnly = true;
  });

  tenantPrefixSourceFileMounts = lib.genAttrs tenantPrefixSourceFiles (sourceFile: {
    hostPath = sourceFile;
    isReadOnly = true;
  });

  reservationRuntimeSourceFileMounts = lib.genAttrs reservationRuntimeSourceFiles (sourceFile: {
    hostPath = sourceFile;
    isReadOnly = true;
  });

  nonEmptyBindMounts =
    mounts:
    lib.filterAttrs (
      destination: mount:
      destination != ""
      && builtins.isAttrs mount
      && builtins.isString (mount.hostPath or null)
      && mount.hostPath != ""
    ) mounts;

  warningMessages =
    if alarmModel ? warningMessages && builtins.isList alarmModel.warningMessages then
      uniqueStrings alarmModel.warningMessages
    else
      [ ];

  alarms =
    if alarmModel ? alarms && builtins.isList alarmModel.alarms then alarmModel.alarms else [ ];

  containerConfigModule = import ./module.nix {
    inherit
      lib
      containerName
      renderedModel
      firewallArg
      alarmModel
      uplinks
      wanUplinkName
      ;
  };

  firewallSpecialArg = {
    enable = firewallArg.enable or false;
    ruleset = firewallArg.ruleset or null;
  };
in
{
  autoStart =
    if renderedModel ? autoStart && builtins.isBool renderedModel.autoStart then
      renderedModel.autoStart
    else
      true;

  privateNetwork = true;

  hostBridge =
    if renderedModel ? hostBridge && builtins.isString renderedModel.hostBridge then
      renderedModel.hostBridge
    else
      null;

  bindMounts =
    nonEmptyBindMounts (
      if renderedModel ? bindMounts && builtins.isAttrs renderedModel.bindMounts then
        renderedModel.bindMounts
      else
        { }
    )
    // runtimeRouteSourceFileMounts
    // tenantPrefixSourceFileMounts
    // reservationRuntimeSourceFileMounts;

  extraVeths = renderedModel.veths or { };

  allowedDevices = uniqueAllowedDevices (
    if renderedModel ? allowedDevices && builtins.isList renderedModel.allowedDevices then
      renderedModel.allowedDevices
    else
      [ ]
  );

  additionalCapabilities = uniqueStrings (
    [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ]
    ++ (
      if
        renderedModel ? additionalCapabilities && builtins.isList renderedModel.additionalCapabilities
      then
        renderedModel.additionalCapabilities
      else
        [ ]
    )
  );

  config = containerConfigModule;

  specialArgs = {
    inherit deploymentHostName;
    s88RoleName = renderedModel.roleName or null;
    s88Firewall = firewallSpecialArg;
    s88Warnings = warningMessages;
    s88Alarms = alarms;
    unitName =
      if renderedModel ? unitName && builtins.isString renderedModel.unitName then
        renderedModel.unitName
      else
        containerName;
  }
  // lib.optionalAttrs debugEnabled {
    s88Debug = renderedModel;
  };
}
