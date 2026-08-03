#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-130
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${NETWORK_RENDERER_NIXOS_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

REPO_ROOT="${repo_root}" nix eval --impure --raw --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    render = platformBinding: hostName:
      import (repoRoot + "/s88/ControlModule/render/vm-nics.nix") {
        inherit lib platformBinding hostName;
      };
    nic = nicId: bridge: address: {
      inherit nicId;
      attachment = { kind = "bridge"; name = bridge; };
      model = "virtio-net-pci";
      mac = { sourceClass = "public"; inherit address; };
      stableMacRequired = true;
    };
    nics = [
      (nic "lan-trunk" "fixture-bridge-a" "52:54:00:12:34:56")
      (nic "upstream-core" "fixture-bridge-b" "52:54:00:12:34:57")
    ];
    bindingFor = target: {
      bindingIdentity = "fixture-binding-identity";
      categories.deployment.vmTargets.fixture-host = target;
    };
    complete = render (bindingFor {
      explicitNicSet = true;
      expectedNicCount = 2;
      inherit nics;
    }) "fixture-host";
    moved = render (bindingFor {
      explicitNicSet = true;
      expectedNicCount = 2;
      nics = [
        (nic "lan-trunk" "moved-bridge" "52:54:00:12:34:56")
        (builtins.elemAt nics 1)
      ];
    }) "fixture-host";
    missing = render {
      bindingIdentity = "fixture-binding-identity";
      categories.deployment.vmTargets.another-host = {
        explicitNicSet = true;
        inherit nics;
      };
    } "fixture-host";
    duplicate = render (bindingFor {
      explicitNicSet = true;
      nics = [ (builtins.head nics) (builtins.head nics) ];
    }) "fixture-host";
    cardinality = render (bindingFor {
      explicitNicSet = true;
      expectedNicCount = 3;
      inherit nics;
    }) "fixture-host";
    require = condition: message: if condition then true else throw message;
  in
    if
      require complete.rendered "complete VM NIC binding was rejected"
      && require (complete.networkingOptions == [
        "-nic none"
        "-nic bridge,br=fixture-bridge-a,mac=52:54:00:12:34:56,model=virtio-net-pci"
        "-nic bridge,br=fixture-bridge-b,mac=52:54:00:12:34:57,model=virtio-net-pci"
      ]) "renderer changed NIC order, bridge, MAC, model, or default-NIC suppression"
      && require ((builtins.head moved.provenance).nicId == "lan-trunk")
        "bridge movement changed stable NIC identity"
      && require ((builtins.head moved.provenance).attachment.name == "moved-bridge")
        "renderer ignored the explicit bridge movement"
      && require (lib.hasInfix "VM_NIC_PLATFORM_BINDING_MISSING" (builtins.head missing.warnings))
        "missing host target did not produce a renderer warning"
      && require (!duplicate.rendered && lib.hasInfix "VM_NIC_DUPLICATE_OWNER" (builtins.concatStringsSep "\n" duplicate.warnings))
        "duplicate nicId did not fail closed"
      && require (!cardinality.rendered && lib.hasInfix "VM_NIC_CARDINALITY_MISMATCH" (builtins.concatStringsSep "\n" cardinality.warnings))
        "NIC cardinality mismatch did not fail closed"
    then "ok" else throw "unreachable"
' >/dev/null

echo "PASS FS-982-HDS-010-SDS-010-SMS-130 renderer VM NIC platform binding"
