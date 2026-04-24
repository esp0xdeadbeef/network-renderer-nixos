{
  lib,
  pkgs,
  renderedModel,
}:

let
  runtimeTarget =
    if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
      renderedModel.runtimeTarget
    else
      { };

  mdnsService =
    if
      runtimeTarget ? services && builtins.isAttrs runtimeTarget.services && runtimeTarget.services ? mdns
    then
      runtimeTarget.services.mdns
    else
      null;
in
if !(builtins.isAttrs mdnsService) then
  { }
else
  let
    allowInterfaces =
      if mdnsService ? allowInterfaces && builtins.isList mdnsService.allowInterfaces then
        lib.filter builtins.isString mdnsService.allowInterfaces
      else
        [ ];

    denyInterfaces =
      if mdnsService ? denyInterfaces && builtins.isList mdnsService.denyInterfaces then
        lib.filter builtins.isString mdnsService.denyInterfaces
      else
        [ ];

    reflector = mdnsService.reflector or false;
    publish = if builtins.isAttrs (mdnsService.publish or null) then mdnsService.publish else { };

    nftRules = [
      "${pkgs.nftables}/bin/nft add rule inet router input udp dport 5353 accept comment \"allow-mdns-service\""
    ];
  in
  {
    services.avahi = {
      enable = true;
      reflector = reflector;
      openFirewall = false;
    }
    // lib.optionalAttrs (allowInterfaces != [ ]) {
      allowInterfaces = allowInterfaces;
    }
    // lib.optionalAttrs (denyInterfaces != [ ]) {
      denyInterfaces = denyInterfaces;
    }
    // lib.optionalAttrs (publish != { }) {
      publish = {
        enable = publish.enable or false;
        addresses = publish.addresses or false;
        userServices = publish.userServices or false;
        workstation = publish.workstation or false;
        domain = publish.domain or false;
      };
    };

    systemd.services.nft-allow-mdns-service = {
      description = "Allow mDNS for local avahi listeners";
      wantedBy = [ "multi-user.target" ];
      wants = [ "nftables.service" ];
      after = [ "nftables.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        if ! ${pkgs.nftables}/bin/nft list chain inet router input | grep -q 'allow-mdns-service'; then
          ${lib.concatStringsSep "\n          " nftRules}
        fi
      '';
    };
  }
