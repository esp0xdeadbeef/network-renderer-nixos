#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-SDS-020-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result="$(REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    system = builtins.currentSystem;
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    ipv6 = {
      mode = "dhcpv6-pd";
      defaultRoute = true;
      iaid = 7;
      prefixDelegationRequestId = 11;
      duidMode = "persistent";
      resolverMode = "disabled";
      ipv4Mode = "disabled";
      routerSolicitation = false;
      fallbackPolicy = "none";
    };
    renderedModel = {
      unitName = "test-core";
      interfaces.provider-handoff.containerInterfaceName = "ens20";
      services.pppoe.client = {
        interface = "provider-handoff";
        runtimeInterface = "ppp-test";
        defaultRoute = true;
        usePeerDns = false;
        mtu = 1492;
        credentials = {
          usernameFile = "/run/secrets/test-username";
          passwordFile = "/run/secrets/test-password";
        };
        inherit ipv6;
      };
    };
    module = import (repoRoot + "/s88/ControlModule/render/containers/module/pppoe.nix") {
      inherit lib pkgs renderedModel;
    };
    evaluated = lib.nixosSystem {
      inherit system;
      modules = [ module.config ];
    };
    pppd = evaluated.config.systemd.services."pppd-s88-pppoe-client-provider-handoff";
    pd = evaluated.config.systemd.services."s88-pppoe-ipv6-pd-provider-handoff";
  in {
    pppdOptions = pppd.preStart;
    dhcpcdConfig = builtins.readFile evaluated.config.environment.etc."s88/pppoe-ipv6-provider-handoff.conf".source;
    pdAfter = pd.after;
    pdRequires = pd.requires;
    pdBindsTo = pd.bindsTo;
    pdPartOf = pd.partOf;
    pdExecStartPre = builtins.toString pd.serviceConfig.ExecStartPre;
    pdExecStart = builtins.toString pd.serviceConfig.ExecStart;
    pdRestart = pd.serviceConfig.Restart;
    firewall = evaluated.config.networking.nftables.ruleset;
  }
')"

jq -e '
  (.pppdOptions | contains("defaultroute6"))
  and (.dhcpcdConfig | contains("nohook resolv.conf"))
  and (.dhcpcdConfig | contains("noipv6rs"))
  and (.dhcpcdConfig | contains("noipv4"))
  and (.dhcpcdConfig | contains("ipv6only"))
  and (.dhcpcdConfig | contains("interface ppp-test"))
  and (.dhcpcdConfig | contains("iaid 7"))
  and (.dhcpcdConfig | contains("ia_pd 11"))
  and (.pdAfter | index("nftables.service") != null)
  and (.pdAfter | index("pppd-s88-pppoe-client-provider-handoff.service") != null)
  and (.pdRequires | index("nftables.service") != null)
  and (.pdRequires | index("pppd-s88-pppoe-client-provider-handoff.service") != null)
  and .pdBindsTo == ["pppd-s88-pppoe-client-provider-handoff.service"]
  and .pdPartOf == ["pppd-s88-pppoe-client-provider-handoff.service"]
  and (.pdExecStartPre | contains("ip link show dev ppp-test"))
  and (.pdExecStart | contains("dhcpcd -6 -d -B"))
  and .pdRestart == "always"
  and (.firewall | contains("iifname ppp-test ip6 saddr fe80::/10 udp sport 547 udp dport 546"))
  and (.firewall | contains("udp dport 547") | not)
' <<<"${result}" >/dev/null

negative="$(REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    renderedModel.interfaces.provider-handoff.containerInterfaceName = "ens20";
    validation = import (repoRoot + "/s88/ControlModule/render/containers/module/pppoe/validation.nix") {
      inherit renderedModel;
    };
    ipv6 = {
      mode = "dhcpv6-pd";
      defaultRoute = true;
      iaid = 7;
      prefixDelegationRequestId = 11;
      duidMode = "persistent";
      resolverMode = "disabled";
      ipv4Mode = "disabled";
      routerSolicitation = false;
      fallbackPolicy = "none";
    };
    base = {
      interface = "provider-handoff";
      runtimeInterface = "ppp-test";
      credentials = {
        usernameFile = "/run/secrets/test-username";
        passwordFile = "/run/secrets/test-password";
      };
      inherit ipv6;
    };
    rejected = value: validation.clientAssertion value == false;
  in {
    missingIaid = rejected (base // { ipv6 = builtins.removeAttrs ipv6 [ "iaid" ]; });
    ipv4Enabled = rejected (base // { ipv6 = ipv6 // { ipv4Mode = "enabled"; }; });
    routerSolicitation = rejected (base // { ipv6 = ipv6 // { routerSolicitation = true; }; });
    fallbackEnabled = rejected (base // { ipv6 = ipv6 // { fallbackPolicy = "slaac"; }; });
    inventedField = rejected (base // { ipv6 = ipv6 // { inventedPppInterface = "ppp0"; }; });
  }
')"
jq -e 'all(.[]; . == true)' <<<"${negative}" >/dev/null

echo 'PASS FS-800-HDS-030-SDS-020-SMS-020: NixOS PPPoE IPv6/PD materialization'
