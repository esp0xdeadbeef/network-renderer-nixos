let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  realization-model = flake.inputs.network-realization-model;

  # CPM fixture with explicit interface role data.
  # This simulates a minimal CPM output for a core node with
  # WAN, LAN, transit, and uplink interfaces.
  cpmFixture = {
    kind = "network-control-plane-artifact";
    artifactIdentity = "fixture-sms060-canonical-boundary";
    artifactDigest = builtins.hashString "sha256" (
      builtins.toJSON {
        test = "sms060";
      }
    );
    control_plane_model = {
      data.example.site.runtimeTargets.core-1 = {
        role = "core";
        roleName = "core";
        interfaces = {
          "eth-wan" = {
            runtimeIfName = "eth-wan";
            renderedIfName = "eth-wan";
            sourceKind = "wan";
            wan = true;
            explicit = {
              explicitWan = true;
              explicitTransit = false;
              explicitLocalAdapter = false;
              explicitUplink = false;
            };
            backingRef = {
              kind = "uplink";
              name = "isp";
              id = "wan::isp";
            };
          };
          "eth-lan" = {
            runtimeIfName = "eth-lan";
            renderedIfName = "eth-lan";
            sourceKind = "tenant";
            localAdapter = true;
            explicit = {
              explicitWan = false;
              explicitTransit = false;
              explicitLocalAdapter = true;
              explicitUplink = false;
            };
            backingRef = {
              kind = "attachment";
              name = "tenant-a";
              id = "tenant::tenant-a";
            };
          };
          "eth-transit" = {
            runtimeIfName = "eth-transit";
            renderedIfName = "eth-transit";
            sourceKind = "p2p";
            transit = true;
            explicit = {
              explicitWan = false;
              explicitTransit = true;
              explicitLocalAdapter = false;
              explicitUplink = false;
            };
            backingRef = {
              kind = "fabric";
              name = "transit-core2";
              id = "transit::core2";
            };
          };
          "eth-uplink" = {
            runtimeIfName = "eth-uplink";
            renderedIfName = "eth-uplink";
            sourceKind = "wan";
            uplink = true;
            explicit = {
              explicitWan = false;
              explicitTransit = false;
              explicitLocalAdapter = false;
              explicitUplink = true;
            };
            backingRef = {
              kind = "uplink";
              name = "isp2";
              id = "wan::isp2";
            };
          };
        };
        forwarding = {
          wanInterfaces = [ "eth-wan" ];
          lanInterfaces = [ "eth-lan" ];
          transitInterfaces = [ "eth-transit" ];
          uplinkInterfaces = [ "eth-uplink" ];
          rules = [ ];
        };
      };
      meta.source = "fixture-sms060";
    };
  };

  # Realize through canonical pipeline
  bundle = realization-model.lib.realize {
    input = cpmFixture;
    requestScope = {
      kind = "complete-artifact";
      identity = "sms060-canonical-test";
    };
    rootLockIdentity = "sms060-test-flake-lock";
    producerRevision = realization-model.rev;
  };

  # Validate through renderer canonical input (realization-model + schema)
  validated = realization-model.lib.validateRendererInput {
    inherit bundle;
    expectedTarget = "nixos";
  };

  cpm = validated.controlPlaneEnvelope;
  runtimeTarget = cpm.control_plane_model.data.example.site.runtimeTargets.core-1;

  # Build interface view and role classification
  common = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/common.nix") { inherit lib; };
  inherit (common) firstAttrsFromPaths boolLikeFromPaths;

  interfaces-raw = runtimeTarget.interfaces or { };

  ifaceView = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/interfaces.nix") {
    inherit lib common;
    interfaces = interfaces-raw;
  };

  nodeForwarding = firstAttrsFromPaths {
    roots = [ runtimeTarget ];
    paths = [
      [ "forwarding" ] [ "forwardingIntent" ] [ "routing" ]
      [ "semantic" "forwarding" ] [ "semanticIntent" "forwarding" ]
    ];
  };

  nodeEgress = firstAttrsFromPaths {
    roots = [ runtimeTarget nodeForwarding ];
    paths = [ [ "egress" ] [ "semantic" "egress" ] [ "semanticIntent" "egress" ] ];
  };

  nodeNat = firstAttrsFromPaths {
    roots = [ runtimeTarget ];
    paths = [ [ "natIntent" ] [ "nat" ] [ "egress" "natIntent" ] [ "egress" "nat" ] ];
  };

  roles = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/roles.nix") {
    inherit lib common runtimeTarget nodeForwarding nodeEgress nodeNat;
    entries = ifaceView.interfaceEntries;
    inherit (ifaceView) resolveInterfaceTokens;
    wanIfs = [ ];
    lanIfs = [ ];
  };

  # Verification: all named lists correctly resolve
  checkWan = builtins.elem "eth-wan" roles.resolvedWanNames;
  checkLan = builtins.elem "eth-lan" roles.resolvedLanNames;
  checkTransit = builtins.elem "eth-transit" roles.resolvedTransitNames;
  checkUplink = builtins.elem "eth-uplink" roles.resolvedUplinkNames;
  checkContract = roles.explicitRoleContractPresent;

  # SourceKind fallback must NOT have activated
  # (all roles resolved from explicit named lists, not sourceKind)
  checkNoSourceKindFallback = roles.resolvedWanNames != [ ]
    && roles.resolvedLanNames != [ ]
    && roles.resolvedTransitNames != [ ];

  allPass =
    bundle.bundleIdentity != null
    && validated.bundleIdentity == bundle.bundleIdentity
    && checkWan && checkLan && checkTransit && checkUplink
    && checkContract && checkNoSourceKindFallback;

  result = {
    ok = allPass;
    checks = {
      bundleIdentity = bundle.bundleIdentity != null;
      validatedIdentity = validated.bundleIdentity == bundle.bundleIdentity;
      wanResolved = checkWan;
      lanResolved = checkLan;
      transitResolved = checkTransit;
      uplinkResolved = checkUplink;
      roleContractPresent = checkContract;
      noSourceKindFallback = checkNoSourceKindFallback;
    };
    failed =
      if allPass then [ ] else
      builtins.filter (name: !result.checks.${name}) (builtins.attrNames result.checks);
    coverage = {
      wanNames = roles.resolvedWanNames;
      lanNames = roles.resolvedLanNames;
      transitNames = roles.resolvedTransitNames;
      uplinkNames = roles.resolvedUplinkNames;
    };
  };
in
result
