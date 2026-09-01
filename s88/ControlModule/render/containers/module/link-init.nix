{
  lib,
  pkgs,
  renderedModel,
}:

let
  interfaces =
    if builtins.isAttrs (renderedModel.interfaces or null) then renderedModel.interfaces else { };
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  macSecretFileFor =
    iface:
    let
      ipv4 = attrsOrEmpty (iface.ipv4 or null);
    in
    if builtins.isString (ipv4.macSecretFile or null) && ipv4.macSecretFile != "" then
      ipv4.macSecretFile
    else
      null;

  wanWithMac = builtins.filter (
    name:
    (interfaces.${name}.sourceKind or null) == "wan" && macSecretFileFor interfaces.${name} != null
  ) (builtins.attrNames interfaces);

  sanitizeName = value: builtins.replaceStrings [ "/" ":" "." "@" ] [ "-" "-" "-" "-" ] value;

  ifaceNameFor =
    name:
    let
      iface = interfaces.${name} or { };
    in
    if builtins.isString (iface.runtimeIfName or null) && iface.runtimeIfName != "" then
      iface.runtimeIfName
    else
      name;

  serviceFor =
    name:
    let
      ifaceName = ifaceNameFor name;
      secretFile = macSecretFileFor interfaces.${name};
      unit = "s88-link-init-${sanitizeName name}";
    in
    {
      name = unit;
      value = {
        description = "Apply the provider WAN MAC to ${ifaceName} before networkd";
        wantedBy = [ "sysinit.target" ];
        before = [ "systemd-networkd.service" ];
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.iproute2
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail

          secret=${lib.escapeShellArg secretFile}
          if [ ! -r "$secret" ]; then
            echo "[link-init] ERROR: $secret is not readable" >&2
            exit 1
          fi

          mac="$(tr -d '[:space:]' < "$secret")"
          if ! printf '%s\n' "$mac" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
            echo "[link-init] ERROR: $secret does not contain a valid MAC address" >&2
            exit 1
          fi

          for _ in $(seq 1 40); do
            if ip link show ${lib.escapeShellArg ifaceName} >/dev/null 2>&1; then
              ip link set dev ${lib.escapeShellArg ifaceName} down || true
              ip link set dev ${lib.escapeShellArg ifaceName} address "$mac"
              exit 0
            fi
            sleep 0.25
          done

          echo "[link-init] ERROR: ${ifaceName} did not appear before networkd startup" >&2
          exit 1
        '';
      };
    };
in
{
  config = lib.mkIf (wanWithMac != [ ]) {
    systemd.services = builtins.listToAttrs (map serviceFor wanWithMac);
  };
}
