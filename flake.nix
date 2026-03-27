{
  description = "Shared NixOS network renderer helpers and router units";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;

      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      queryBox = import ./lib/query-box.nix { inherit lib; };

      realizationPorts =
        let
          sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);
        in
        rec {
          realizationNodesFor =
            inventory:
            if inventory ? realization
              && builtins.isAttrs inventory.realization
              && inventory.realization ? nodes
              && builtins.isAttrs inventory.realization.nodes
            then
              inventory.realization.nodes
            else
              { };

          nodeForUnit =
            {
              inventory,
              unitName,
              file ? "flake.nix",
            }:
            let
              realizationNodes = realizationNodesFor inventory;
            in
            if builtins.hasAttr unitName realizationNodes
              && builtins.isAttrs realizationNodes.${unitName}
            then
              realizationNodes.${unitName}
            else
              throw ''
                ${file}: missing realization node for unit '${unitName}'

                known realization nodes:
                ${builtins.concatStringsSep "\n  - " ([ "" ] ++ sortedAttrNames realizationNodes)}
              '';

          portsForUnit =
            {
              inventory,
              unitName,
              file ? "flake.nix",
            }:
            let
              node = nodeForUnit {
                inherit inventory unitName file;
              };
            in
            if node ? ports && builtins.isAttrs node.ports then
              node.ports
            else
              throw ''
                ${file}: realization node '${unitName}' is missing ports

                node:
                ${builtins.toJSON node}
              '';

          attachForPort =
            {
              port,
              unitName ? "<unknown>",
              portName ? "<unknown>",
              file ? "flake.nix",
            }:
            let
              attach =
                if port ? attach && builtins.isAttrs port.attach then
                  port.attach
                else
                  { };
            in
            if (attach.kind or null) == "bridge"
              && attach ? bridge
              && builtins.isString attach.bridge
            then
              {
                kind = "bridge";
                name = attach.bridge;
              }
            else if (attach.kind or null) == "direct"
              && port ? link
              && builtins.isString port.link
            then
              {
                kind = "direct";
                name = port.link;
              }
            else
              throw ''
                ${file}: could not resolve host attach target for unit '${unitName}', port '${portName}'

                port:
                ${builtins.toJSON port}
              '';

          attachMapForUnit =
            {
              inventory,
              unitName,
              file ? "flake.nix",
            }:
            let
              ports = portsForUnit {
                inherit inventory unitName file;
              };
            in
            builtins.listToAttrs (
              map
                (
                  portName:
                  {
                    name = portName;
                    value = attachForPort {
                      port = ports.${portName};
                      inherit unitName portName file;
                    };
                  }
                )
                (sortedAttrNames ports)
            );

          attachMapForInventory =
            {
              inventory,
              file ? "flake.nix",
            }:
            let
              realizationNodes = realizationNodesFor inventory;
              unitNames = sortedAttrNames realizationNodes;
            in
            builtins.listToAttrs (
              map
                (
                  unitName:
                  {
                    name = unitName;
                    value = attachMapForUnit {
                      inherit inventory unitName file;
                    };
                  }
                )
                unitNames
            );
        };

      mkUnit = path: {
        inherit path;
        module = import path;
      };
    in
    {
      lib = {
        inherit queryBox realizationPorts;

        renderer = {
          loadIntent = path: queryBox.importMaybeFunction path;
          loadInventory = path: queryBox.importMaybeFunction path;

          validateInventory =
            {
              inventory,
              nodeName ? null,
              hostName ? null,
              cpm ? null,
            }:
            import ./s88/Unit/s-router-policy-only/lib/inventory/validate.nix {
              inherit lib inventory nodeName hostName cpm;
            };

          renderHostNetwork =
            {
              inventory,
              hostName,
              cpm ? null,
            }:
            import ./s88/Unit/s-router-policy-only/lib/renderer/render-host-network.nix {
              inherit lib inventory hostName cpm;
            };

          renderContainers =
            {
              inventory,
              nodeName,
              hostName,
              cpm ? null,
            }:
            import ./s88/Unit/s-router-policy-only/lib/renderer/render-containers.nix {
              inherit lib inventory nodeName hostName cpm;
            };
        };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          render-dry-config = pkgs.writeShellApplication {
            name = "render-dry-config";

            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnused
              pkgs.jq
              pkgs.nix
            ];

            text = ''
              set -euo pipefail

              if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
                echo "usage: render-dry-config /path/to/intent.nix [/path/to/inventory.nix]" >&2
                exit 1
              fi

              intent_path="$(realpath "$1")"

              if [ "$#" -eq 2 ]; then
                inventory_path="$(realpath "$2")"
              else
                inventory_path="$(realpath "$(dirname "$intent_path")/inventory.nix")"
              fi

              example_dir="$(dirname "$intent_path")"

              if [ ! -f "$intent_path" ]; then
                echo "render-dry-config: intent file not found: $intent_path" >&2
                exit 1
              fi

              if [ ! -f "$inventory_path" ]; then
                echo "render-dry-config: inventory file not found: $inventory_path" >&2
                exit 1
              fi

              export REPO_ROOT="${self.outPath}"
              export INTENT_PATH="$intent_path"
              export INVENTORY_PATH="$inventory_path"
              export EXAMPLE_DIR="$example_dir"

              rm -f \
                ./00-*.json \
                ./01-*.json \
                ./10-*.json \
                ./20-*.json \
                ./21-*.json \
                ./22-*.json \
                ./23-*.json \
                ./30-*.json \
                ./90-*.json

              nix_json() {
                local out="$1"
                local expr="$2"
                local tmp

                tmp="$(mktemp)"
                nix eval \
                  --impure \
                  --json \
                  --extra-experimental-features 'nix-command flakes' \
                  --expr "$expr" > "$tmp"
                mv "$tmp" "$out"
              }

              nix_json ./00-intent.json '
                let
                  flake = builtins.getFlake (toString (builtins.toPath (builtins.getEnv "REPO_ROOT")));
                  intentPath = builtins.toPath (builtins.getEnv "INTENT_PATH");
                in
                flake.lib.renderer.loadIntent intentPath
              '

              nix_json ./01-inventory.json '
                let
                  flake = builtins.getFlake (toString (builtins.toPath (builtins.getEnv "REPO_ROOT")));
                  inventoryPath = builtins.toPath (builtins.getEnv "INVENTORY_PATH");
                in
                flake.lib.renderer.loadInventory inventoryPath
              '

              nix_json ./10-paths.json '
                {
                  exampleDir = builtins.getEnv "EXAMPLE_DIR";
                  intentPath = builtins.getEnv "INTENT_PATH";
                  inventoryPath = builtins.getEnv "INVENTORY_PATH";
                  repoRoot = builtins.getEnv "REPO_ROOT";
                }
              '

              nix_json ./20-query-box.json '
                let
                  flake = builtins.getFlake (toString (builtins.toPath (builtins.getEnv "REPO_ROOT")));
                  inventoryPath = builtins.toPath (builtins.getEnv "INVENTORY_PATH");
                  inventory = flake.lib.renderer.loadInventory inventoryPath;

                  renderHostNames =
                    if inventory ? render
                      && builtins.isAttrs inventory.render
                      && inventory.render ? hosts
                      && builtins.isAttrs inventory.render.hosts
                    then
                      builtins.attrNames inventory.render.hosts
                    else
                      [ ];

                  deploymentHostNames =
                    if inventory ? deployment
                      && builtins.isAttrs inventory.deployment
                      && inventory.deployment ? hosts
                      && builtins.isAttrs inventory.deployment.hosts
                    then
                      builtins.attrNames inventory.deployment.hosts
                    else
                      [ ];

                  realizationNodeNames =
                    builtins.attrNames (flake.lib.realizationPorts.realizationNodesFor inventory);

                  allNames =
                    renderHostNames
                    ++ deploymentHostNames
                    ++ realizationNodeNames;

                  uniqueNames =
                    builtins.attrNames (
                      builtins.listToAttrs (
                        map
                          (
                            name:
                            {
                              inherit name;
                              value = true;
                            }
                          )
                          allNames
                      )
                    );

                  sortedNames = builtins.sort builtins.lessThan uniqueNames;

                  realizationNodes = flake.lib.realizationPorts.realizationNodesFor inventory;

                  deploymentHosts =
                    if inventory ? deployment
                      && builtins.isAttrs inventory.deployment
                      && inventory.deployment ? hosts
                      && builtins.isAttrs inventory.deployment.hosts
                    then
                      inventory.deployment.hosts
                    else
                      { };

                  renderHosts =
                    if inventory ? render
                      && builtins.isAttrs inventory.render
                      && inventory.render ? hosts
                      && builtins.isAttrs inventory.render.hosts
                    then
                      inventory.render.hosts
                    else
                      { };
                in
                builtins.listToAttrs (
                  map
                    (
                      hostname:
                      let
                        full = flake.lib.queryBox.boxForHost {
                          inherit inventory hostname;
                          file = "render-dry-config";
                        };
                      in
                      {
                        name = hostname;
                        value = {
                          hostname = full.hostname;
                          boxName = full.boxName;
                          deploymentHostName = full.deploymentHostName;
                          deploymentHostNames = full.deploymentHostNames;
                          realizationNode = full.realizationNode;
                          box = full.box;
                          renderHostConfig = full.renderHostConfig;
                          deploymentHosts = deploymentHosts;
                          renderHosts = renderHosts;
                          realizationNodes = realizationNodes;
                        };
                      }
                    )
                    sortedNames
                )
              '

              nix_json ./21-hardware.json '
                let
                  flake = builtins.getFlake (toString (builtins.toPath (builtins.getEnv "REPO_ROOT")));
                  inventoryPath = builtins.toPath (builtins.getEnv "INVENTORY_PATH");
                  inventory = flake.lib.renderer.loadInventory inventoryPath;
                in
                {
                  deploymentHosts =
                    if inventory ? deployment
                      && builtins.isAttrs inventory.deployment
                      && inventory.deployment ? hosts
                      && builtins.isAttrs inventory.deployment.hosts
                    then
                      inventory.deployment.hosts
                    else
                      { };

                  renderHosts =
                    if inventory ? render
                      && builtins.isAttrs inventory.render
                      && inventory.render ? hosts
                      && builtins.isAttrs inventory.render.hosts
                    then
                      inventory.render.hosts
                    else
                      { };
                }
              '

              nix_json ./22-realization.json '
                let
                  flake = builtins.getFlake (toString (builtins.toPath (builtins.getEnv "REPO_ROOT")));
                  inventoryPath = builtins.toPath (builtins.getEnv "INVENTORY_PATH");
                  inventory = flake.lib.renderer.loadInventory inventoryPath;
                in
                flake.lib.realizationPorts.realizationNodesFor inventory
              '

              nix_json ./23-port-attach-targets.json '
                let
                  flake = builtins.getFlake (toString (builtins.toPath (builtins.getEnv "REPO_ROOT")));
                  inventoryPath = builtins.toPath (builtins.getEnv "INVENTORY_PATH");
                  inventory = flake.lib.renderer.loadInventory inventoryPath;
                in
                flake.lib.realizationPorts.attachMapForInventory {
                  inherit inventory;
                  file = "render-dry-config";
                }
              '

              nix_json ./30-rendered-hardware.json '
                let
                  flake = builtins.getFlake (toString (builtins.toPath (builtins.getEnv "REPO_ROOT")));
                  inventoryPath = builtins.toPath (builtins.getEnv "INVENTORY_PATH");
                  inventory = flake.lib.renderer.loadInventory inventoryPath;

                  deploymentHostNames =
                    if inventory ? deployment
                      && builtins.isAttrs inventory.deployment
                      && inventory.deployment ? hosts
                      && builtins.isAttrs inventory.deployment.hosts
                    then
                      builtins.sort builtins.lessThan (builtins.attrNames inventory.deployment.hosts)
                    else
                      [ ];
                in
                builtins.listToAttrs (
                  map
                    (
                      hostName:
                      {
                        name = hostName;
                        value = flake.lib.renderer.renderHostNetwork {
                          inherit inventory hostName;
                        };
                      }
                    )
                    deploymentHostNames
                )
              '

              jq -s '{
                inputs: {
                  intent: .[0],
                  inventory: .[1]
                },
                vars: {
                  paths: .[2],
                  queryBox: .[3],
                  hardware: .[4],
                  realization: .[5],
                  portAttachTargets: .[6],
                  renderedHardware: .[7]
                }
              }' \
                ./00-intent.json \
                ./01-inventory.json \
                ./10-paths.json \
                ./20-query-box.json \
                ./21-hardware.json \
                ./22-realization.json \
                ./23-port-attach-targets.json \
                ./30-rendered-hardware.json \
                > ./90-dry-config.json

              jq . ./90-dry-config.json
            '';
          };
        }
      );

      apps = forAllSystems (
        system:
        let
          program = "${self.packages.${system}.render-dry-config}/bin/render-dry-config";
        in
        {
          render-dry-config = {
            type = "app";
            inherit program;
          };

          default = {
            type = "app";
            inherit program;
          };
        }
      );

      s88 = {
        Unit = {
          "s-router-access" = mkUnit ./s88/Unit/s-router-access;
          "s-router-core" = mkUnit ./s88/Unit/s-router-core;
          "s-router-policy-only" = mkUnit ./s88/Unit/s-router-policy-only;
          "s-router-upstream-selector" = mkUnit ./s88/Unit/s-router-upstream-selector;
        };
      };

      nixosModules = {
        "s-router-access" = import ./s88/Unit/s-router-access;
        "s-router-core" = import ./s88/Unit/s-router-core;
        "s-router-policy-only" = import ./s88/Unit/s-router-policy-only;
        "s-router-upstream-selector" = import ./s88/Unit/s-router-upstream-selector;
      };
    };
}
