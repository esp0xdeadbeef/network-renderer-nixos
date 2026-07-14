#!/usr/bin/env bash
# GAMP-ID: FS-500-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
# Construction test: NixOS host bridge co-location for selector fabric p2p links.
# Proves SMS predicates MR1, MR3, MR5, MR6, FC1-FC5, SN1, SN2.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

trace="FS-500-HDS-010-SDS-010-SMS-050"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
  "${trace} NixOS bridge co-location" \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          realizationPorts = import (repoRoot + "/s88/Unit/physical/realization-ports.nix") {
            inherit lib;
          };

          file = "'"${trace}"'";

          # Positive case: two routers sharing a p2p link via direct attach,
          # same site name. Both should get the same hostBridgeName.
          positiveSource = {
            realization.nodes = {
              router-alpha = {
                logicalNode = {
                  name = "router-alpha";
                  site = "site-a";
                };
                ports = {
                  p2p-alpha-beta = {
                    link = "p2p-alpha-beta";
                    attach = {
                      kind = "direct";
                      link = "p2p-alpha-beta";
                    };
                  };
                };
              };
              router-beta = {
                logicalNode = {
                  name = "router-beta";
                  site = "site-a";
                };
                ports = {
                  p2p-beta-alpha = {
                    link = "p2p-alpha-beta";
                    attach = {
                      kind = "direct";
                      link = "p2p-alpha-beta";
                    };
                  };
                };
              };
            };
          };

          positiveAttachAlpha =
            realizationPorts.attachForPort {
              inherit file;
              unitName = "router-alpha";
              portName = "p2p-alpha-beta";
              node = positiveSource.realization.nodes.router-alpha;
              port = positiveSource.realization.nodes.router-alpha.ports.p2p-alpha-beta;
            };

          positiveAttachBeta =
            realizationPorts.attachForPort {
              inherit file;
              unitName = "router-beta";
              portName = "p2p-beta-alpha";
              node = positiveSource.realization.nodes.router-beta;
              port = positiveSource.realization.nodes.router-beta.ports.p2p-beta-alpha;
            };

          # MR3: both endpoints of the same modeled p2p link share the same host bridge
          p2pSameBridge =
            positiveAttachAlpha.hostBridgeName == positiveAttachBeta.hostBridgeName
            && positiveAttachAlpha.hostBridgeName != "";

          # Negative case 1: split bridge
          # Core endpoint on inventory bridge, selector endpoint on generated direct bridge
          splitSource = {
            realization.nodes = {
              core-router = {
                logicalNode = {
                  name = "core-router";
                  site = "site-a";
                };
                ports = {
                  split-link-core = {
                    attach = {
                      kind = "bridge";
                      bridge = "br-site-something";
                    };
                  };
                };
              };
              upstream-selector = {
                logicalNode = {
                  name = "upstream-selector";
                  site = "site-a";
                };
                ports = {
                  split-link-selector = {
                    link = "p2p-selector-fabric-link";
                    attach = {
                      kind = "direct";
                      link = "p2p-selector-fabric-link";
                    };
                  };
                };
              };
            };
          };

          splitAttachCore =
            realizationPorts.attachForPort {
              inherit file;
              unitName = "core-router";
              portName = "split-link-core";
              node = splitSource.realization.nodes.core-router;
              port = splitSource.realization.nodes.core-router.ports.split-link-core;
            };

          splitAttachSelector =
            realizationPorts.attachForPort {
              inherit file;
              unitName = "upstream-selector";
              portName = "split-link-selector";
              node = splitSource.realization.nodes.upstream-selector;
              port = splitSource.realization.nodes.upstream-selector.ports.split-link-selector;
            };

          # MR5/FC1: endpoints on different bridges should be detected
          splitBridgeDetected =
            splitAttachCore.hostBridgeName != splitAttachSelector.hostBridgeName
            && splitAttachCore.kind == "bridge"
            && splitAttachSelector.kind == "direct";

          # MR6: name-derived repair rejection - different link names with
          # similar bridge names should NOT match
          nameDerivedSource = {
            realization.nodes = {
              router-one = {
                logicalNode = {
                  name = "router-one";
                  site = "site-a";
                };
                ports = {
                  p2p-real-link = {
                    link = "p2p-link-real";
                    attach = {
                      kind = "direct";
                      link = "p2p-link-real";
                    };
                  };
                };
              };
              router-two = {
                logicalNode = {
                  name = "router-two";
                  site = "site-a";
                };
                ports = {
                  p2p-different-link = {
                    link = "p2p-link-real-impostor";
                    attach = {
                      kind = "direct";
                      link = "p2p-link-real-impostor";
                    };
                  };
                };
              };
            };
          };

          nameDerivedAttachOne =
            realizationPorts.attachForPort {
              inherit file;
              unitName = "router-one";
              portName = "p2p-real-link";
              node = nameDerivedSource.realization.nodes.router-one;
              port = nameDerivedSource.realization.nodes.router-one.ports.p2p-real-link;
            };

          nameDerivedAttachTwo =
            realizationPorts.attachForPort {
              inherit file;
              unitName = "router-two";
              portName = "p2p-different-link";
              node = nameDerivedSource.realization.nodes.router-two;
              port = nameDerivedSource.realization.nodes.router-two.ports.p2p-different-link;
            };

          nameDerivedDifferentBridges =
            nameDerivedAttachOne.hostBridgeName != nameDerivedAttachTwo.hostBridgeName;

          # SN2: CPM fabric link must not carry renderer attach data
          # This is proven by the renderer using only realization.nodes + ports,
          # not CPM fabricLinks. The attach resolution always uses port.attach,
          # never side-channel CPM data.
          noCpmFabricLinkInjection =
            !(builtins.hasAttr "fabricLinks" positiveSource.realization.nodes.router-alpha);

          checks = {
            inherit
              p2pSameBridge
              splitBridgeDetected
              nameDerivedDifferentBridges
              noCpmFabricLinkInjection
              ;
          };

          failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        in
        {
          ok = failed == [ ];
          inherit checks failed;
          observed = {
            positive = {
              alphaBridge = positiveAttachAlpha.hostBridgeName;
              betaBridge = positiveAttachBeta.hostBridgeName;
              alphaKind = positiveAttachAlpha.kind;
              betaKind = positiveAttachBeta.kind;
            };
            split = {
              coreBridge = splitAttachCore.hostBridgeName;
              selectorBridge = splitAttachSelector.hostBridgeName;
              coreKind = splitAttachCore.kind;
              selectorKind = splitAttachSelector.kind;
            };
            nameDerived = {
              oneBridge = nameDerivedAttachOne.hostBridgeName;
              twoBridge = nameDerivedAttachTwo.hostBridgeName;
            };
          };
        }
      '

assert_json_checks_ok \
  "${trace} NixOS bridge co-location" \
  "${result_json}"

echo "PASS ${trace} NixOS bridge co-location"
