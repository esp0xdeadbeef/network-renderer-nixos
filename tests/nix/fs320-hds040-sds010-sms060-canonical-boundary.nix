let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  realization-model = flake.inputs.network-realization-model;

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

  cpmSource = flake.inputs.network-control-plane-model.outPath;
  model = cpmFixture.control_plane_model;
  canonicalCollections = {
    canonicalInterfaces = import (cpmSource + "/src/cpm/canonical-interfaces.nix") {
      inherit lib;
    } model;
    canonicalRoutes = import (cpmSource + "/src/cpm/canonical-routes.nix") { inherit lib; } model;
    canonicalOverlays = import (cpmSource + "/src/cpm/canonical-overlays.nix") { inherit lib; } model;
    canonicalSites = import (cpmSource + "/src/cpm/canonical-sites.nix") { inherit lib; } model;
    canonicalRuntimeTargets = import (cpmSource + "/src/cpm/canonical-runtime-targets.nix") {
      inherit lib;
    } model;
    canonicalForwarding = import (cpmSource + "/src/cpm/canonical-forwarding.nix") {
      inherit lib;
    } model;
  };

  artifact = cpmFixture // {
    control_plane_model = cpmFixture.control_plane_model // canonicalCollections;
  };

  bundle = realization-model.lib.realize {
    input = artifact;
    requestScope = {
      kind = "complete-artifact";
      identity = "sms060-canonical-test";
    };
    rootLockIdentity = "sms060-test-flake-lock";
    producerRevision = realization-model.rev;
  };

  validated = realization-model.lib.validateRendererInput {
    inherit bundle;
    expectedTarget = "nixos";
  };

  canonicalTargets = validated.canonical.canonicalRuntimeTargets.targets or [ ];
  targetEntry = lib.findFirst (entry: (entry.target or null) == "core-1") null canonicalTargets;
  runtimeTarget = if targetEntry == null then { } else targetEntry.facts or { };

  common = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/common.nix") {
    inherit lib;
  };
  inherit (common) firstAttrsFromPaths boolLikeFromPaths;

  interfaces-raw = runtimeTarget.interfaces or { };

  ifaceView =
    import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/interfaces.nix")
      {
        inherit lib common;
        interfaces = interfaces-raw;
      };

  nodeForwarding = firstAttrsFromPaths {
    roots = [ runtimeTarget ];
    paths = [
      [ "forwarding" ]
      [ "forwardingIntent" ]
      [ "routing" ]
      [
        "semantic"
        "forwarding"
      ]
      [
        "semanticIntent"
        "forwarding"
      ]
    ];
  };

  nodeEgress = firstAttrsFromPaths {
    roots = [
      runtimeTarget
      nodeForwarding
    ];
    paths = [
      [ "egress" ]
      [
        "semantic"
        "egress"
      ]
      [
        "semanticIntent"
        "egress"
      ]
    ];
  };

  nodeNat = firstAttrsFromPaths {
    roots = [ runtimeTarget ];
    paths = [
      [ "natIntent" ]
      [ "nat" ]
      [
        "egress"
        "natIntent"
      ]
      [
        "egress"
        "nat"
      ]
    ];
  };

  roles = import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent/roles.nix") {
    inherit
      lib
      common
      runtimeTarget
      nodeForwarding
      nodeEgress
      nodeNat
      ;
    entries = ifaceView.interfaceEntries;
    inherit (ifaceView) resolveInterfaceTokens;
    wanIfs = [ ];
    lanIfs = [ ];
  };

  checkWan = builtins.elem "eth-wan" roles.resolvedWanNames;
  checkLan = builtins.elem "eth-lan" roles.resolvedLanNames;
  checkTransit = builtins.elem "eth-transit" roles.resolvedTransitNames;
  checkUplink = builtins.elem "eth-uplink" roles.resolvedUplinkNames;
  checkContract = roles.explicitRoleContractPresent;

  checkNoSourceKindFallback =
    roles.resolvedWanNames != [ ] && roles.resolvedLanNames != [ ] && roles.resolvedTransitNames != [ ];

  allPass =
    targetEntry != null
    && bundle.bundleIdentity != null
    && validated.bundleIdentity == bundle.bundleIdentity
    && checkWan
    && checkLan
    && checkTransit
    && checkUplink
    && checkContract
    && checkNoSourceKindFallback;

  result = {
    ok = allPass;
    checks = {
      canonicalTargetPublished = targetEntry != null;
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
      if allPass then
        [ ]
      else
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
