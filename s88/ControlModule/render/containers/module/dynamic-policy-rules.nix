{
  lib,
  pkgs,
  dynamicPolicySourceRules,
}:

let
  serviceForRule =
    index: rule:
    let
      serviceName = "s88-dynamic-policy-rule-${builtins.toString index}";
      script = pkgs.writeShellScript serviceName ''
        set -eu
        source_file=${lib.escapeShellArg rule.sourceFile}
        interface=${lib.escapeShellArg rule.interfaceName}
        table=${lib.escapeShellArg (toString rule.table)}
        priority=${lib.escapeShellArg (toString rule.priority)}
        suppress=${
          if (rule.suppressPrefixLength or null) == null then
            "''"
          else
            lib.escapeShellArg (toString rule.suppressPrefixLength)
        }
        family=${lib.escapeShellArg (toString rule.family)}

        [ -s "$source_file" ] || exit 0
        prefix="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < "$source_file")"
        [ -n "$prefix" ] || exit 0
        if ! printf '%s' "$prefix" | ${pkgs.gnugrep}/bin/grep -q '/'; then
          if [ "$family" = "6" ]; then
            prefix="$prefix/128"
          else
            prefix="$prefix/32"
          fi
        fi

        if [ "$family" = "6" ]; then
          ip_cmd="${pkgs.iproute2}/bin/ip -6"
        else
          ip_cmd="${pkgs.iproute2}/bin/ip"
        fi

        while $ip_cmd rule del from "$prefix" iif "$interface" priority "$priority" 2>/dev/null; do
          true
        done

        # `ip rule add` is not idempotent and returns EEXIST when an equal
        # rule is already present. Multiple runtime sources can map to the
        # same prefix (e.g. several tenants sharing one delegated /48), so
        # treat EEXIST as success instead of failing the unit and tripping
        # systemd's start rate limit.
        add_rule() {
          err="$($ip_cmd rule "$@" 2>&1)" && return 0
          case "$err" in
            *"File exists"*) return 0 ;;
            *) printf '%s\n' "$err" >&2; return 1 ;;
          esac
        }

        if [ -n "$suppress" ]; then
          add_rule add from "$prefix" iif "$interface" table main suppress_prefixlength "$suppress" priority "$priority"
        else
          add_rule add from "$prefix" iif "$interface" table "$table" priority "$priority"
        fi
      '';
    in
    {
      name = serviceName;
      value = {
        description = "Install runtime source-prefix policy rule ${builtins.toString index}";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-networkd.service" ];
        wants = [ "systemd-networkd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = script;
        };
      };
    };

  pathForRule =
    index: rule:
    let
      serviceName = "s88-dynamic-policy-rule-${builtins.toString index}";
    in
    {
      name = serviceName;
      value = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = rule.sourceFile;
          PathChanged = rule.sourceFile;
          Unit = "${serviceName}.service";
        };
      };
    };
in
{
  config = lib.optionalAttrs (dynamicPolicySourceRules != [ ]) {
    systemd.services = builtins.listToAttrs (lib.imap0 serviceForRule dynamicPolicySourceRules);
    systemd.paths = builtins.listToAttrs (lib.imap0 pathForRule dynamicPolicySourceRules);
  };
}
