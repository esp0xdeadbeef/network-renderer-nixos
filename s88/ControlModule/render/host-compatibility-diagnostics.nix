{ lib
, config
, vmNicHandled ? false
,
}:

let
  services = lib.attrByPath [ "systemd" "services" ] { } config;
  reservationPostProcessorServices =
    if !builtins.isAttrs services then
      [ ]
    else
      builtins.filter
        (serviceName:
          let
            service = services.${serviceName};
            serviceConfig = if builtins.isAttrs (service.serviceConfig or null) then service.serviceConfig else { };
            execStartPost = serviceConfig.ExecStartPost or null;
          in
          lib.hasPrefix "gen-kea-" serviceName
          && execStartPost != null
          && execStartPost != [ ]
          && execStartPost != "")
        (lib.sort builtins.lessThan (builtins.attrNames services));

  localQemuOptions =
    if vmNicHandled then
      null
    else
      lib.attrByPath [ "virtualisation" "qemu" "networkingOptions" ] null config;
  hasLocalQemuOptions =
    localQemuOptions != null
    && ((builtins.isList localQemuOptions && localQemuOptions != [ ])
      || (builtins.isString localQemuOptions && localQemuOptions != ""));
in
{
  inherit reservationPostProcessorServices hasLocalQemuOptions;
  warnings =
    lib.optional (reservationPostProcessorServices != [ ])
      "FS-970-HDS-010-SDS-020-SMS-040: RUNTIME_RESERVATION_SOURCE_OUTSIDE_CPM [inventory]: host-local Kea reservation post-processing is present without renderer-owned protected reservation-set materialization; declare advertisement.reservationSource in inventory and remove the host-local post-processor"
    ++ lib.optional hasLocalQemuOptions
      "FS-982-HDS-010-SDS-010-SMS-130: VM_NIC_PLATFORM_BINDING_MISSING [inventory]: the host profile supplies QEMU networking options without a validated canonical VM-target binding; move NIC identity, attachment, model, and accepted MAC sources into the platform binding";
}
