#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-045
# GAMP-SCOPE: NixOS controlled iterative authority materialization
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
cd "${repo_root}"

result="$(nix eval --json --impure --expr '
let
  renderer = builtins.getFlake (toString ./.);
  cpmFlake = builtins.getFlake (toString /home/deadbeef/github/network-control-plane-model);
  labs = /home/deadbeef/github/network-labs;
  system = builtins.currentSystem;
  trace = "FS-540-HDS-010-SDS-010-SMS-045";
  row = labs + "/GAMP/SMT/${trace}";
  source = import (row + "/intent.nix");
  inventory = import (row + "/inventory-nixos.nix");
  cpm = cpmFlake.libBySystem.${system}.compileAndBuild {
    input = source;
    inherit inventory;
  };
  authority =
    let
      targets = cpm.control_plane_model.data."mini-smt".${trace}.runtimeTargets;
      core = builtins.head (builtins.filter
        (target: target.logicalNode.name == "core-primary")
        (builtins.attrValues targets));
    in core.services.dns.validationAuthority;
  targets = cpm.control_plane_model.data."mini-smt".${trace}.runtimeTargets;
  coreTargetName = builtins.head (builtins.filter
    (name: targets.${name}.logicalNode.name == "core-primary")
    (builtins.attrNames targets));
  evaluated = renderer.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      (renderer.libBySystem.${system}.renderer.hostModule {
        inherit cpm;
        hostName = "s-router-nixos";
      })
      ({ ... }: {
        boot.isContainer = true;
        system.stateVersion = "26.05";
      })
    ];
  };
  cfg = evaluated.config;
  core = cfg.containers."core-primary".config;
  unboundServer = core.services.unbound.settings.server;
  rootHintsPath = unboundServer."root-hints" or null;
  knotZones = builtins.attrNames cfg.services.knot.settings.zone;
  providerNetwork = cfg.systemd.network.networks."30-isp-primary";
  badCore = targets.${coreTargetName} // {
    services = targets.${coreTargetName}.services // {
      dns = targets.${coreTargetName}.services.dns // {
        validationAuthority = authority // { selectedUplink = "overlay-secondary"; };
      };
    };
  };
  badCpm = cpm // {
    control_plane_model = cpm.control_plane_model // {
      data = cpm.control_plane_model.data // {
        "mini-smt" = cpm.control_plane_model.data."mini-smt" // {
          ${trace} = cpm.control_plane_model.data."mini-smt".${trace} // {
            runtimeTargets = targets // { ${coreTargetName} = badCore; };
          };
        };
      };
    };
  };
  badEvaluation = renderer.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      (renderer.libBySystem.${system}.renderer.hostModule {
        cpm = badCpm;
        hostName = "s-router-nixos";
      })
      ({ ... }: {
        boot.isContainer = true;
        system.stateVersion = "26.05";
      })
    ];
  };
  badSelection = builtins.tryEval (builtins.deepSeq
    badEvaluation.config.containers."core-primary".config.services.unbound.settings
    true);
in {
  authorityPreserved = authority.kind == "controlled-iterative-hierarchy";
  coreControlled =
    core.services.unbound.enableRootTrustAnchor == false
    && rootHintsPath != null
    && unboundServer."domain-insecure" == [ "." ]
    && builtins.match ".*root[.]dns-validation[.]gamp[.].*" (builtins.readFile rootHintsPath) != null;
  coreRoutedSlaac =
    core.boot.kernel.sysctl."net.ipv6.conf.all.forwarding" == 1
    && core.systemd.network.networks."10-wan0".networkConfig.IPv6AcceptRA == true;
  providerDhcpRa =
    cfg.services.dnsmasq.enable
    && cfg.services.dnsmasq.resolveLocalQueries == false
    && cfg.services.dnsmasq.settings.interface == [ authority.provider.bridge ]
    && cfg.services.dnsmasq.settings."bind-interfaces" == [ true ]
    && cfg.services.dnsmasq.settings."enable-ra" == [ true ];
  providerAutonomousSlaac =
    builtins.any
      (range: builtins.match ".*,ra-only,slaac,64,.*" range != null)
      cfg.services.dnsmasq.settings."dhcp-range";
  providerIpv6Router =
    cfg.boot.kernel.sysctl."net.ipv6.conf.all.forwarding" == 1
    && providerNetwork.networkConfig.LinkLocalAddressing == "ipv6";
  providerAuthority =
    cfg.services.knot.enable
    && knotZones == [ "." "dns-validation.gamp." ]
    && builtins.all
      (address: builtins.elem "${address}@53" cfg.services.knot.settings.server.listen)
      (authority.root.ipv4 ++ authority.root.ipv6
        ++ authority.delegation.ipv4 ++ authority.delegation.ipv6);
  providerAddresses =
    builtins.elem authority.provider.ipv4.address providerNetwork.address
    && builtins.elem authority.provider.ipv6.address providerNetwork.address
    && builtins.all
      (address: builtins.elem "${address}/32" providerNetwork.address)
      (authority.root.ipv4 ++ authority.delegation.ipv4)
    && builtins.all
      (address: builtins.elem "${address}/128" providerNetwork.address)
      (authority.root.ipv6 ++ authority.delegation.ipv6);
  alternateUnanswered =
    builtins.all
      (address: !(builtins.elem address
        (cfg.systemd.network.networks."30-overlay-secondary".address or [ ])))
      (authority.root.ipv4 ++ authority.root.ipv6
        ++ authority.delegation.ipv4 ++ authority.delegation.ipv6);
  badSelectionRejected = badSelection.success == false;
}
')"

jq -e '
  .authorityPreserved == true
  and .coreControlled == true
  and .coreRoutedSlaac == true
  and .providerDhcpRa == true
  and .providerAutonomousSlaac == true
  and .providerIpv6Router == true
  and .providerAuthority == true
  and .providerAddresses == true
  and .alternateUnanswered == true
  and .badSelectionRejected == true
' <<<"${result}" >/dev/null

echo "PASS FS-540 NixOS controlled iterative authority materialization"
