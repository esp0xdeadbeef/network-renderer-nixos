{
  lib,
  pkgs,
  scope,
}:

let
  cfgFile = "/run/radvd-${scope.fileStem}.conf";
  delegatedPrefix = scope.delegatedPrefix or null;
  delegatedPrefixSourceFile =
    if delegatedPrefix != null && builtins.isString (delegatedPrefix.sourceFile or null) then
      delegatedPrefix.sourceFile
    else
      null;

  waitIface = pkgs.writeShellScript "wait-iface-ready-radvd-${scope.fileStem}" ''
    set -euo pipefail
    IF="$1"

    for i in $(seq 1 80); do
      if ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1; then
        if ${pkgs.iproute2}/bin/ip link show "$IF" | ${pkgs.gnugrep}/bin/grep -q "UP"; then
          exit 0
        fi
      fi
      sleep 0.25
    done

    ${pkgs.iproute2}/bin/ip link show "$IF" || true
    exit 1
  '';

  genConfig = pkgs.writeShellScript "gen-radvd-${scope.fileStem}" ''
    set -euo pipefail
    mkdir -p /run

    pd_prefix=""
    ${lib.optionalString (delegatedPrefix != null) ''
            if [ -n "${delegatedPrefixSourceFile}" ] && [ -s "${delegatedPrefixSourceFile}" ]; then
              pd_prefix="$(${pkgs.python3}/bin/python3 - "${delegatedPrefixSourceFile}" "${toString delegatedPrefix.delegatedPrefixLength}" "${toString delegatedPrefix.perTenantPrefixLength}" "${toString delegatedPrefix.slot}" <<'PY'
      import ipaddress
      import pathlib
      import sys

      source_path = pathlib.Path(sys.argv[1])
      delegated_prefix_length = int(sys.argv[2])
      per_tenant_prefix_length = int(sys.argv[3])
      slot = int(sys.argv[4])

      raw = source_path.read_text().strip()
      network = ipaddress.ip_network(raw, strict=False)
      if network.version != 6:
          raise SystemExit(f"expected IPv6 delegated prefix, got {raw!r}")
      if per_tenant_prefix_length < delegated_prefix_length:
          raise SystemExit(
              f"per-tenant prefix /{per_tenant_prefix_length} cannot be shorter than delegated /{delegated_prefix_length}"
          )
      if network.prefixlen > delegated_prefix_length:
          raise SystemExit(
              f"runtime delegated prefix {network.with_prefixlen} is narrower than modeled /{delegated_prefix_length}"
          )

      slot_bits = per_tenant_prefix_length - delegated_prefix_length
      max_slot = (1 << slot_bits) - 1 if slot_bits > 0 else 0
      if slot > max_slot:
          raise SystemExit(f"slot {slot} exceeds capacity {max_slot} for /{per_tenant_prefix_length}")

      shift = 128 - per_tenant_prefix_length
      base = int(network.network_address)
      derived = ipaddress.ip_network((base | (slot << shift), per_tenant_prefix_length), strict=False)
      print(derived.with_prefixlen)
      PY
              )"
            fi
    ''}

    cat > ${lib.escapeShellArg cfgFile} <<'EOF'
    interface ${scope.interfaceName} {
      AdvSendAdvert on;
      MinRtrAdvInterval 10;
      MaxRtrAdvInterval 30;
      AdvManagedFlag off;
      AdvOtherConfigFlag off;
    ${lib.optionalString (scope.rdnss != [ ]) ''
      RDNSS ${builtins.concatStringsSep " " scope.rdnss} {
        AdvRDNSSLifetime 600;
      };
    ''}
    ${lib.optionalString (scope.domain != "") ''
      DNSSL ${scope.domain} {
        AdvDNSSLLifetime 600;
      };
    ''}
    ${lib.concatMapStrings (prefix: ''
      prefix ${prefix} {
        AdvOnLink on;
        AdvAutonomous on;
      };
    '') scope.prefixes}
    };
    EOF

    ${lib.optionalString (delegatedPrefix != null) ''
            if [ -n "$pd_prefix" ]; then
              tmp_cfg="$(mktemp)"
              sed '$d' ${lib.escapeShellArg cfgFile} > "$tmp_cfg"
              cat >> "$tmp_cfg" <<EOF_PD
            prefix $pd_prefix {
              AdvOnLink on;
              AdvAutonomous on;
            };
          };
      EOF_PD
              install -m 0644 "$tmp_cfg" ${lib.escapeShellArg cfgFile}
              rm -f "$tmp_cfg"
            fi
    ''}
  '';
in
{
  environment.systemPackages = [
    pkgs.radvd
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.coreutils
    pkgs.python3
  ];

  systemd.services."radvd-generate-${scope.fileStem}" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    path = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genConfig;
      RemainAfterExit = true;
    };
    postStart = ''
      systemctl try-restart radvd-${scope.fileStem}.service || true
    '';
  };

  systemd.paths = lib.optionalAttrs (delegatedPrefixSourceFile != null) {
    "radvd-prefix-${scope.fileStem}" = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = delegatedPrefixSourceFile;
        PathChanged = delegatedPrefixSourceFile;
        Unit = "radvd-generate-${scope.fileStem}.service";
      };
    };
  };

  systemd.services."radvd-${scope.fileStem}" = {
    description = "Router advertisements on ${scope.interfaceName}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "radvd-generate-${scope.fileStem}.service"
    ];
    requires = [
      "systemd-networkd.service"
      "radvd-generate-${scope.fileStem}.service"
    ];

    path = [
      pkgs.coreutils
      pkgs.iproute2
      pkgs.gnugrep
    ];

    serviceConfig = {
      Type = "simple";

      ExecStartPre = [
        "${waitIface} ${lib.escapeShellArg scope.interfaceName}"
      ];

      ExecStart = "${pkgs.radvd}/bin/radvd -n -C ${cfgFile}";
      Restart = "always";
      RestartSec = "2s";

      CapabilityBoundingSet = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];

      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };
}
