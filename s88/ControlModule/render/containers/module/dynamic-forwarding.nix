{ lib, pkgs, dynamicSourceForwardRules }:

let
  scriptForRule =
    index: rule:
    let
      name = "s88-dynamic-forward-${builtins.toString index}";
      familyExpr = if (rule.family or 6) == 4 then "ip saddr" else "ip6 saddr";
      action = if (rule.action or "accept") == "drop" then "drop" else "accept";
    in
    ''
      source_file=${lib.escapeShellArg rule.sourceFile}
      in_if=${lib.escapeShellArg rule.inIf}
      out_if=${lib.escapeShellArg rule.outIf}
      comment=${lib.escapeShellArg name}

      if [ ! -r "$source_file" ]; then
        exit 0
      fi

      prefix="$(${pkgs.coreutils}/bin/head -n 1 "$source_file" | ${pkgs.coreutils}/bin/tr -d '[:space:]')"
      if [ -z "$prefix" ]; then
        exit 0
      fi

      ${pkgs.nftables}/bin/nft -a list chain inet router forward \
        | ${pkgs.gawk}/bin/awk -v comment="$comment" '$0 ~ "comment \\"" comment "\\"" { print $NF }' \
        | while read -r handle; do
            [ -n "$handle" ] && ${pkgs.nftables}/bin/nft delete rule inet router forward handle "$handle" || true
          done

      ${pkgs.nftables}/bin/nft add rule inet router forward \
        iifname "$in_if" oifname "$out_if" ${familyExpr} "$prefix" ${action} comment "$comment"
    '';

  ruleServices =
    lib.listToAttrs (
      lib.imap0
        (index: rule: {
          name = "s88-dynamic-forward-${builtins.toString index}";
          value = {
            description = "Install dynamic source-prefix forward rule ${builtins.toString index}";
            wantedBy = [ "multi-user.target" ];
            after = [ "nftables.service" ];
            path = [ pkgs.nftables pkgs.coreutils pkgs.gawk ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = scriptForRule index rule;
          };
        })
        dynamicSourceForwardRules
    );

  pathUnits =
    lib.listToAttrs (
      lib.imap0
        (index: rule: {
          name = "s88-dynamic-forward-${builtins.toString index}";
          value = {
            wantedBy = [ "multi-user.target" ];
            pathConfig = {
              PathExists = rule.sourceFile;
              PathChanged = rule.sourceFile;
            };
          };
        })
        dynamicSourceForwardRules
    );
in
{
  config = lib.optionalAttrs (dynamicSourceForwardRules != [ ]) {
    systemd.services = ruleServices;
    systemd.paths = pathUnits;
  };
}
