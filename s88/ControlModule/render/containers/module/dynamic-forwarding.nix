{
  lib,
  pkgs,
  dynamicSourceForwardRules,
  tableName ? "router",
}:

let
  scriptForRule =
    index: rule:
    let
      name = "s88-dynamic-forward-${builtins.toString index}";
      familyExpr = if (rule.family or 6) == 4 then "ip saddr" else "ip6 saddr";
      action = if (rule.action or "accept") == "drop" then "drop" else "accept";
      deriveTenantPrefix = rule.deriveTenantPrefix or false;
    in
    ''
      set -eu

      source_file=${lib.escapeShellArg rule.sourceFile}
      in_if=${lib.escapeShellArg rule.inIf}
      out_if=${lib.escapeShellArg rule.outIf}
      comment=${lib.escapeShellArg name}

      if [ ! -r "$source_file" ]; then
        exit 0
      fi

      if [ "${if deriveTenantPrefix then "1" else "0"}" = "1" ]; then
        prefix="$(${pkgs.python3Minimal}/bin/python3 ${./runtime-delegated-prefix.py} \
          --source "$source_file" \
          --family 6 \
          --delegated-prefix-length ${lib.escapeShellArg (toString rule.delegatedPrefixLength)} \
          --tenant-prefix-length ${lib.escapeShellArg (toString rule.perTenantPrefixLength)} \
          --slot ${lib.escapeShellArg (toString rule.slot)})"
      else
        prefix="$(${pkgs.coreutils}/bin/head -n 1 "$source_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')"
      fi
      if [ -z "$prefix" ]; then
        exit 0
      fi

      handle="$(${pkgs.nftables}/bin/nft -a list chain inet ${tableName} forward \
        | ${pkgs.gawk}/bin/awk -v comment="$comment" 'index($0, "comment \"" comment "\"") { print $NF; exit }')"

      if [ -n "$handle" ]; then
        ${pkgs.nftables}/bin/nft replace rule inet ${tableName} forward handle "$handle" \
          iifname "$in_if" oifname "$out_if" ${familyExpr} "$prefix" ${action} comment "$comment"
      else
        ${pkgs.nftables}/bin/nft add rule inet ${tableName} forward \
          iifname "$in_if" oifname "$out_if" ${familyExpr} "$prefix" ${action} comment "$comment"
      fi
    '';

  ruleServices = lib.listToAttrs (
    lib.imap0 (index: rule: {
      name = "s88-dynamic-forward-${builtins.toString index}";
      value = {
        description = "Install dynamic source-prefix forward rule ${builtins.toString index}";
        wantedBy = [ "multi-user.target" ];
        after = [ "nftables.service" ];
        path = [
          pkgs.nftables
          pkgs.coreutils
          pkgs.gawk
          pkgs.python3Minimal
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = scriptForRule index rule;
      };
    }) dynamicSourceForwardRules
  );

  pathUnits = lib.listToAttrs (
    lib.imap0 (index: rule: {
      name = "s88-dynamic-forward-${builtins.toString index}";
      value = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = rule.sourceFile;
          PathChanged = rule.sourceFile;
        };
      };
    }) dynamicSourceForwardRules
  );
in
{
  config = lib.optionalAttrs (dynamicSourceForwardRules != [ ]) {
    systemd.services = ruleServices;
    systemd.paths = pathUnits;
  };
}
