{
  lib,
  platformBinding ? null,
  hostName,
}:

let
  deployment =
    if
      platformBinding != null
      && builtins.isAttrs platformBinding
      && builtins.isAttrs ((platformBinding.categories or { }).deployment or null)
    then
      platformBinding.categories.deployment
    else
      { };
  vmTargets = if builtins.isAttrs (deployment.vmTargets or null) then deployment.vmTargets else { };
  bindingDeclaresVmTargets = deployment ? vmTargets;
  target = vmTargets.${hostName} or null;
  targetPresent = builtins.isAttrs target;
  explicitNicSet = targetPresent && (target.explicitNicSet or false) == true;
  nics = if targetPresent && builtins.isList (target.nics or null) then target.nics else [ ];

  nicIdFor =
    nic: if builtins.isAttrs nic && builtins.isString (nic.nicId or null) then nic.nicId else "";
  nicIds = map nicIdFor nics;
  uniqueNicIds = lib.unique nicIds;
  validMac =
    address:
    builtins.isString address
    &&
      builtins.match "[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]" address
      != null;
  validateNic =
    nic:
    let
      attachment = if builtins.isAttrs (nic.attachment or null) then nic.attachment else { };
      mac = nic.mac or null;
      macValid =
        mac == null
        || (
          builtins.isAttrs mac && (mac.sourceClass or null) == "public" && validMac (mac.address or null)
        );
    in
    builtins.isAttrs nic
    && nicIdFor nic != ""
    && (attachment.kind or null) == "bridge"
    && builtins.isString (attachment.name or null)
    && attachment.name != ""
    && (!(nic ? model) || (builtins.isString nic.model && nic.model != ""))
    && (!(nic.stableMacRequired or false) || mac != null)
    && macValid;
  validNics = builtins.all validateNic nics;

  missingTarget = bindingDeclaresVmTargets && !targetPresent;
  invalidTarget = targetPresent && (!explicitNicSet || nics == [ ] || !validNics);
  duplicateIds = targetPresent && builtins.length nicIds != builtins.length uniqueNicIds;
  expectedCountValid =
    !targetPresent
    || !(target ? expectedNicCount)
    || (builtins.isInt target.expectedNicCount && target.expectedNicCount == builtins.length nics);
  valid =
    targetPresent && explicitNicSet && nics != [ ] && validNics && !duplicateIds && expectedCountValid;

  warning = code: message: "FS-982-HDS-010-SDS-010-SMS-130: ${code} [platform-binding]: ${message}";
  warnings =
    lib.optional missingTarget (
      warning "VM_NIC_PLATFORM_BINDING_MISSING" "the validated NixOS binding declares VM targets but has no target for host '${hostName}'; QEMU NIC output is suppressed"
    )
    ++ lib.optional invalidTarget (
      warning "VM_NIC_BINDING_INVALID" "the host target must declare explicitNicSet=true and an ordered non-empty NIC set with stable IDs and explicit bridge attachments; QEMU NIC output is suppressed"
    )
    ++ lib.optional duplicateIds (
      warning "VM_NIC_DUPLICATE_OWNER" "the host target repeats a nicId; QEMU NIC output is suppressed"
    )
    ++ lib.optional (!expectedCountValid) (
      warning "VM_NIC_CARDINALITY_MISMATCH" "expectedNicCount does not match the ordered NIC set; QEMU NIC output is suppressed"
    );

  vhostQueues = nic: if builtins.isInt (nic.queues or null) then nic.queues else 1;
  vhostTapName = nic: "tap-${nic.nicId}";
  isVhostNic = nic: (nic.vhost or false) == true;

  plainOptionFor =
    nic:
    let
      bridge = nic.attachment.name;
      model = nic.model or "virtio-net-pci";
      macOption = if nic.mac or null == null then "" else ",mac=${nic.mac.address}";
    in
    "-nic bridge,br=${bridge}${macOption},model=${model}";

  vhostOptionsFor =
    nic:
    let
      queues = vhostQueues nic;
      macDevice = if nic.mac or null == null then "" else ",mac=${nic.mac.address}";
    in
    [
      "-netdev"
      "tap,id=vnic-${nic.nicId},ifname=${vhostTapName nic},script=no,downscript=no,vhost=on,queues=${toString queues}"
      "-device"
      "virtio-net-pci,netdev=vnic-${nic.nicId}${macDevice},mq=on,vectors=${toString (2 * queues + 2)}"
    ];

  optionFor = nic: if isVhostNic nic then vhostOptionsFor nic else [ (plainOptionFor nic) ];
in
{
  handled = bindingDeclaresVmTargets;
  rendered = valid;
  networkingOptions = if valid then [ "-nic none" ] ++ lib.concatMap optionFor nics else [ ];
  provenance =
    if !valid then
      [ ]
    else
      map (nic: {
        inherit (nic) nicId attachment;
        model = nic.model or "virtio-net-pci";
        macSourceClass = if nic.mac or null == null then null else nic.mac.sourceClass;
        bindingIdentity = platformBinding.bindingIdentity;
      }) nics;

  vhostTapAttachments =
    if !valid then
      [ ]
    else
      map (nic: {
        tap = vhostTapName nic;
        bridge = nic.attachment.name;
      }) (builtins.filter isVhostNic nics);

  inherit warnings;
}
