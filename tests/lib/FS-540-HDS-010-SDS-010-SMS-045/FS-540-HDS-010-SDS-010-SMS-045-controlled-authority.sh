#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-045
# GAMP-SCOPE: NixOS controlled iterative authority materialization
#
# MEASURED, STILL OPEN (2026-11-24): the two variant cases patch records the renderer no longer
# reads. `s88/Unit/api/host-build/runtime-targets.nix` builds a host runtime target from
# `canonicalSites.byEnterprise`, while the container loop reads
# `canonicalRuntimeTargets.targets` (a LIST of targets, keys: containers, enterprise, facts,
# interfaces, logicalNode, placementHost, role, site, target -- no `services`). The fixture
# patches `services.dns.infraHostTtl` / `validationAuthority.selectedUplink`; measured, the
# rendered `infra-host-ttl` stays at its production default 900 no matter which of the two
# records is patched, so `fixtureTtlOverride` and `badSelectionRejected` assert a data path that
# no longer exists. The authority assertions (the row's subject) all pass. Fixing this needs a
# decision on where a service override is declared in canonical content, which is a model
# question -- not a test edit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
cd "${repo_root}"

result="$(nix eval --json --impure --expr '
let
  renderer = builtins.getFlake (toString ./.);
  # Resolve the upstream layers from this repo flake inputs (CI checks them out
  # at the pinned revisions); never from a machine-local path.
  cpmFlake = renderer.inputs.network-control-plane-model;
  labs = renderer.inputs.network-labs.outPath;
  system = builtins.currentSystem;
  # The renderer maps the validated bundle, so the collections it publishes are realized from
  # the same artifact this test compiled (FS-310-HDS-040-SDS-010-SMS-100). The previous
  # `canonicalCollections = cpm.control_plane_model` was the plain producer model wearing the
  # name of the bundle -- the exact substitution RR_RAW_CPM_INPUT forbids.
  canonical = realize cpm;
  realize = artifact: (renderer.inputs.network-realization-model.lib.realize {
    input = {
      kind = "network-control-plane-artifact";
      artifactIdentity = "fs540-045";
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON artifact.control_plane_model);
      inherit (artifact) control_plane_model;
    };
    requestScope = { kind = "complete-artifact"; identity = "fs540-045"; };
    rootLockIdentity = "fs540-045";
    producerRevision = "fs540-045";
  }).canonical or { };
  # The renderer reads a host runtime target from `canonicalSites.byEnterprise`
  # (s88/Unit/api/host-build/runtime-targets.nix), NOT from the CPM. The two variant cases
  # below used to patch `cpm.control_plane_model.data...` and therefore asserted nothing:
  # measured, the patched CPM left `infra-host-ttl` at 900. Patch the canonical record.
  patchCoreTarget = collections: fn:
    let
      patchSite = site: site // {
        runtimeTargets = builtins.mapAttrs
          (targetName: target: if targetName == coreTargetName then fn target else target)
          (site.runtimeTargets or { });
      };
    in
    collections // {
      canonicalSites = collections.canonicalSites // {
        byEnterprise = builtins.mapAttrs (_: builtins.mapAttrs (_: patchSite))
          collections.canonicalSites.byEnterprise;
      };
    };
  patchDns = fn: target: target // {
    services = target.services // { dns = fn target.services.dns; };
  };
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
        canonicalCollections = canonical;
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
  badCollections = patchCoreTarget canonical (patchDns (dns: dns // {
    validationAuthority = (dns.validationAuthority or { }) // { selectedUplink = "overlay-secondary"; };
  }));
  badEvaluation = renderer.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      (renderer.libBySystem.${system}.renderer.hostModule {
        inherit cpm;
        hostName = "s-router-nixos";
        canonicalCollections = badCollections;
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

  # Production posture: infra-host-ttl=900, no infra-lame-ttl
  productionHostTtl = unboundServer."infra-host-ttl" or null;
  productionLameTtl = unboundServer."infra-lame-ttl" or null;

  # Fixture with explicit timer acceleration, declared on the canonical record.
  fixtureCollections = patchCoreTarget canonical (patchDns (dns: dns // {
    infraHostTtl = 1;
    infraLameTtl = 1;
  }));
  fixtureEvaluation = renderer.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      (renderer.libBySystem.${system}.renderer.hostModule {
        inherit cpm;
        hostName = "s-router-nixos";
        canonicalCollections = fixtureCollections;
      })
      ({ ... }: {
        boot.isContainer = true;
        system.stateVersion = "26.05";
      })
    ];
  };
  fixtureUnbound = fixtureEvaluation.config.containers."core-primary".config.services.unbound.settings.server;
  fixtureHostTtl = fixtureUnbound."infra-host-ttl" or null;
  fixtureLameTtl = fixtureUnbound."infra-lame-ttl" or null;

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
  productionTtlDefault = productionHostTtl == 900 && productionLameTtl == null;
  fixtureTtlOverride = fixtureHostTtl == 1 && fixtureLameTtl == 1;
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
  and .productionTtlDefault == true
  and .fixtureTtlOverride == true
' <<<"${result}" >/dev/null

echo "PASS FS-540 NixOS controlled iterative authority materialization"
