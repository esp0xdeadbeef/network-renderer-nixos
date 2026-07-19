{
  lib,
  pkgs,
  dynamicDestinationForwardRules,
}:

let
  scriptForRule =
    index: rule:
    let
      name = "s88-runtime-destination-forward-${builtins.toString index}";
      action = if rule.action == "drop" then "drop" else if rule.action == "accept" then "accept" else
        throw "FS-230-HDS-010-SDS-010-SMS-040: unsupported runtime destination action";
    in
    pkgs.writeShellScript name ''
      set -eu

      source_file=${lib.escapeShellArg rule.sourceFile}
      in_if=${lib.escapeShellArg rule.inIf}
      out_if=${lib.escapeShellArg rule.outIf}
      protocol=${lib.escapeShellArg rule.protocol}
      destination_port=${lib.escapeShellArg (toString rule.destinationPort)}
      comment=${lib.escapeShellArg rule.comment}

      if [ ! -r "$source_file" ]; then
        echo "diagnostic.runtime-public-ingress-address-invalid: protected runtime source unavailable" >&2
        exit 1
      fi

      address="$(${pkgs.python3Minimal}/bin/python3 ${./runtime-delegated-prefix.py} \
        --source "$source_file" \
        --family 6 \
        --delegated-prefix-length ${lib.escapeShellArg (toString rule.delegatedPrefixLength)} \
        --tenant-prefix-length ${lib.escapeShellArg (toString rule.perTenantPrefixLength)} \
        --slot ${lib.escapeShellArg (toString rule.slot)} \
        --interface-identifier ${lib.escapeShellArg rule.interfaceIdentifier})"

      handles="$(${pkgs.nftables}/bin/nft -a list chain inet router forward \
        | ${pkgs.gawk}/bin/awk -v comment="$comment" 'index($0, "comment \"" comment "\"") { print $NF }')"
      if [ "$(printf '%s\n' "$handles" | ${pkgs.gnugrep}/bin/grep -c .)" -ne 1 ]; then
        echo "diagnostic.runtime-public-ingress-placeholder-invalid: exact rule owner missing or ambiguous" >&2
        exit 1
      fi

      ${pkgs.nftables}/bin/nft replace rule inet router forward handle "$handles" \
        iifname "$in_if" oifname "$out_if" meta nfproto ipv6 \
        ip6 daddr "$address" meta l4proto "$protocol" \
        "$protocol" dport "$destination_port" ${action} comment "$comment"
    '';

  services = lib.listToAttrs (
    lib.imap0 (index: rule: {
      name = "s88-runtime-destination-forward-${builtins.toString index}";
      value = {
        description = "Install exact protected runtime IPv6 destination forward rule";
        wantedBy = [ "multi-user.target" ];
        after = [ "nftables.service" ];
        wants = [ "nftables.service" ];
        partOf = [ "nftables.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = scriptForRule index rule;
        };
      };
    }) dynamicDestinationForwardRules
  );

  paths = lib.listToAttrs (
    lib.imap0 (index: rule: {
      name = "s88-runtime-destination-forward-${builtins.toString index}";
      value = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = rule.sourceFile;
          PathChanged = rule.sourceFile;
          Unit = "s88-runtime-destination-forward-${builtins.toString index}.service";
        };
      };
    }) dynamicDestinationForwardRules
  );
in
{
  config = lib.optionalAttrs (dynamicDestinationForwardRules != [ ]) {
    systemd.services = services;
    systemd.paths = paths;
  };
}
