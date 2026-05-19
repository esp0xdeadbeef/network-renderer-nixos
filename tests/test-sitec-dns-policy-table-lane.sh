#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr '
    let
      flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
      labs = flake.inputs.network-labs.outPath;
      containers = flake.lib.containers.buildForBox {
        boxName = "s-router-hetzner-anywhere";
        system = "x86_64-linux";
        intentPath = labs + "/examples/s-router-overlay-dns-lane-policy/intent.nix";
        inventoryPath = labs + "/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix";
      };
      cfg = (flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ containers."c-router-upstream-selector".config ];
      }).config;
      networks = cfg.systemd.network.networks;
      coreNebulaRules = networks."10-core-nebula".routingPolicyRules or [ ];
      tableRules =
        builtins.filter
          (rule: (rule.IncomingInterface or null) == "core-nebula" && builtins.isInt (rule.Table or null) && rule.Table != 254)
          coreNebulaRules;
      coreNebulaTable = if tableRules == [ ] then null else (builtins.head tableRules).Table;
      allRoutes =
        builtins.concatMap
          (name: map (route: route // { networkName = name; }) (networks.${name}.routes or [ ]))
          (builtins.attrNames networks);
      hasRoute = destination: gateway:
        builtins.any
          (route:
            (route.Destination or null) == destination
            && (route.Gateway or null) == gateway
            && (route.Table or null) == coreNebulaTable)
          allRoutes;
      ok =
        coreNebulaTable != null
        && hasRoute "10.90.10.0/24" "10.80.0.16"
        && !(hasRoute "10.90.10.0/24" "10.80.0.18")
        && hasRoute "fd42:dead:cafe:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:10"
        && !(hasRoute "fd42:dead:cafe:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:12");
    in
      if ok then true else throw ("sitec-dns-policy-table-lane failed: " + builtins.toJSON {
        inherit coreNebulaTable;
        dnsRoutes =
          builtins.filter
            (route:
              (route.Destination or "") == "10.90.10.0/24"
              || (route.Destination or "") == "fd42:dead:cafe:0010:0000:0000:0000:0000/64")
            allRoutes;
      })
  ' >/dev/null

echo "PASS sitec-dns-policy-table-lane"
