let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  traceId = "FS-320-HDS-010-SDS-010-SMS-010";

  tenantInterface =
    tenantName:
    {
      sourceKind = "tenant";
      tenant = tenantName;
      renderedIfName = "tenant-${tenantName}";
      runtimeIfName = "tenant-${tenantName}";
      containerInterfaceName = "tenant-${tenantName}";
      hostInterfaceName = "tenant-${tenantName}";
      explicit = {
        explicitLocalAdapter = true;
        explicitWan = false;
        explicitTransit = false;
      };
      backingRef = {
        kind = "attachment";
        name = tenantName;
        lane = {
          kind = "tenant";
          access = "access-cohost";
        };
      };
    };

  uplinkInterface = {
    sourceKind = "wan";
    upstream = "testnet";
    assignedUplinkName = "testnet";
    renderedIfName = "uplink-testnet";
    runtimeIfName = "uplink-testnet";
    containerInterfaceName = "uplink-testnet";
    hostInterfaceName = "uplink-testnet";
    explicit = {
      explicitLocalAdapter = false;
      explicitWan = true;
      explicitTransit = false;
    };
    backingRef = {
      kind = "uplink";
      name = "testnet";
      lane = {
        kind = "egress";
        uplink = "testnet";
        uplinks = [ "testnet" ];
      };
    };
  };

  runtimeTarget = {
    role = "access";
    logicalNode = {
      enterprise = "mini";
      site = "layout";
      name = "access-cohost";
    };
    forwardingIntent = {
      mode = "explicit-access-forwarding";
      rules = [
        {
          relationId = "${traceId}__client-allow";
          action = "allow";
          fromInterface = [ "tenant-client" ];
          toInterface = [ "uplink-testnet" ];
          trafficType = "any";
        }
        {
          relationId = "${traceId}__mgmt-deny";
          action = "deny";
          fromInterface = [ "tenant-mgmt" ];
          toInterface = [ "uplink-testnet" ];
          trafficType = "any";
        }
      ];
    };
    effectiveRuntimeRealization.interfaces = {
      tenant-client = tenantInterface "client";
      tenant-mgmt = tenantInterface "mgmt";
      uplink-testnet = uplinkInterface;
    };
  };

  site = {
    communicationContract = {
      relations = [
        {
          id = "${traceId}__client-allow";
          action = "allow";
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "external";
            name = "testnet";
          };
          trafficType = "any";
        }
        {
          id = "${traceId}__mgmt-deny";
          action = "deny";
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "external";
            name = "testnet";
          };
          trafficType = "any";
        }
      ];
      trafficTypes = [
        {
          name = "any";
          match = [
            {
              family = "any";
              proto = "any";
            }
          ];
        }
      ];
    };
    ownership.prefixes = [
      {
        kind = "tenant";
        name = "client";
        ipv4 = "10.50.10.0/24";
      }
      {
        kind = "tenant";
        name = "mgmt";
        ipv4 = "10.50.20.0/24";
      }
    ];
    topology.nodes.access-cohost = {
      role = "access";
      attachments = [
        {
          kind = "tenant";
          name = "client";
        }
        {
          kind = "tenant";
          name = "mgmt";
        }
      ];
    };
    runtimeTargets.access-cohost = runtimeTarget;
  };

  cpm = {
    control_plane_model.data.mini.layout = site;
  };

  renderedModel = {
    deploymentHostName = "layout-host";
    unitName = "access-cohost";
    unitKey = "mini::layout::access-cohost";
    roleName = "access";
    logicalNode = runtimeTarget.logicalNode;
    inherit runtimeTarget site;
    interfaces = runtimeTarget.effectiveRuntimeRealization.interfaces;
    lanInterfaceNames = [
      "tenant-client"
      "tenant-mgmt"
    ];
    wanInterfaceNames = [ "uplink-testnet" ];
    firewallPolicyPath = repoRoot + "/s88/ControlModule/firewall/policy/access.nix";
    preferSiteNode = true;
    strictEndpointBindings = true;
  };

  rendered = import (repoRoot + "/s88/ControlModule/render/containers.nix") {
    inherit lib cpm;
    repoPath = repoRoot;
    models.layout-host.access-cohost = renderedModel;
  };

  container = rendered.layout-host.access-cohost;
  ruleset = container.specialArgs.s88Firewall.ruleset or "";

  clientLine =
    ''iifname "tenant-client" oifname "uplink-testnet" accept comment "${traceId}__client-allow"'';
  mgmtLine =
    ''iifname "tenant-mgmt" oifname "uplink-testnet" drop comment "${traceId}__mgmt-deny"'';
  mergedLine =
    ''iifname { "tenant-client", "tenant-mgmt" } oifname "uplink-testnet" accept comment "merged-layout"'';

  preservesLayout =
    candidate:
    lib.hasInfix clientLine candidate
    && lib.hasInfix mgmtLine candidate
    && !(lib.hasInfix mergedLine candidate)
    && !(lib.hasInfix '' allow comment "${traceId}__client-allow"'' candidate);

  seededMergedOutput = ''
    table inet router {
      chain forward {
        type filter hook forward priority filter; policy drop;
        ${mergedLine}
      }
    }
  '';

  checks = {
    rendered_firewall_enabled = (container.specialArgs.s88Firewall.enable or false) == true;
    compact_cohost_container_rendered = builtins.hasAttr "access-cohost" rendered.layout-host;
    colocated_tenant_interfaces_present =
      builtins.hasAttr "tenant-client" renderedModel.interfaces
      && builtins.hasAttr "tenant-mgmt" renderedModel.interfaces;
    client_allow_preserved = lib.hasInfix clientLine ruleset;
    mgmt_deny_preserved = lib.hasInfix mgmtLine ruleset;
    allow_action_normalized_to_accept =
      !(lib.hasInfix '' allow comment "${traceId}__client-allow"'' ruleset);
    merged_role_identity_absent = !(lib.hasInfix mergedLine ruleset);
    seeded_negative_detects_merged_role_identity = !(preservesLayout seededMergedOutput);
  };

  failed = lib.filter (name: checks.${name} != true) (builtins.attrNames checks);
in
{
  ok = failed == [ ];
  inherit checks failed;
  coverage = {
    hostCount = 1;
    containerCount = 1;
    coLocatedTenantInterfaces = 2;
    explicitForwardingRules = builtins.length runtimeTarget.forwardingIntent.rules;
    seededNegativeCount = 1;
  };
}
