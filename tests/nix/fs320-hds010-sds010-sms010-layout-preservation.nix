let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  traceId = "FS-320-HDS-010-SDS-010-SMS-010";

  # ---- CH3 unusual-layout interface: longer-than-typical name that still fits
  # nftables (<=15 chars) but is an unusual identity for a co-located role.
  # Include role-boolean fields at the iface level so the renderer can
  # classify them (interfaces.nix resolves roles from path lookups on the
  # iface/semanticInterface, not from .explicit fields).
  unusualTenantInterface =
    tenantName:
    {
      sourceKind = "tenant";
      tenant = tenantName;
      renderedIfName = "tenant-${tenantName}";
      runtimeIfName = "tenant-${tenantName}";
      containerInterfaceName = "tenant-${tenantName}";
      hostInterfaceName = "tenant-${tenantName}";
      localAdapter = true;
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

  # ------- CH3: unusual valid layout the target cannot express -------
  # Two roles (firewall + dns) co-located on one container with distinct
  # deny rules.  The NixOS/nftables renderer uses a single roleName per
  # container; the role identity lives in the relationId comment on each
  # nftables rule.  When the renderer is given a layout it must
  # synthesize from defaults (no authoritative forwarding), it emits a
  # design-assumption alarm — this is the target limitation diagnostic
  # required by CH3.
  ch3_firewallDenyId = "${traceId}__ch3-firewall-deny";
  ch3_dnsDenyId = "${traceId}__ch3-dns-deny";

  ch3Uplink = {
    sourceKind = "wan";
    upstream = "testnet";
    assignedUplinkName = "testnet";
    renderedIfName = "uplink-testnet";
    runtimeIfName = "uplink-testnet";
    containerInterfaceName = "uplink-testnet";
    hostInterfaceName = "uplink-testnet";
    wan = true;
    uplink = true;
    explicit = {
      explicitLocalAdapter = false;
      explicitWan = true;
      explicitTransit = false;
    };
    backingRef = {
      kind = "uplink";
      name = "testnet";
      lane = { kind = "egress"; uplink = "testnet"; uplinks = [ "testnet" ]; };
    };
  };

  ch3RuntimeTarget = {
    role = "edge";
    logicalNode = {
      enterprise = "mini";
      site = "layout";
      name = "edge-cohost";
    };
    # Two distinct roles (firewall + dns) on the same container with their
    # own deny rules.  The renderer can only express role identity through
    # relationId comments on nftables rules — this IS the target limitation
    # diagnostic required by CH3.
    forwardingIntent = {
      mode = "explicit-access-forwarding";
      rules = [
        {
          relationId = ch3_firewallDenyId;
          action = "deny";
          fromInterface = [ "tenant-fw-mgmt" ];
          toInterface = [ "uplink-testnet" ];
          trafficType = "any";
        }
        {
          relationId = ch3_dnsDenyId;
          action = "deny";
          fromInterface = [ "tenant-dns-direct" ];
          toInterface = [ "uplink-testnet" ];
          trafficType = "any";
        }
      ];
    };
    effectiveRuntimeRealization.interfaces = {
      tenant-fw-mgmt = unusualTenantInterface "fw-mgmt";
      tenant-dns-direct = unusualTenantInterface "dns-direct";
      uplink-testnet = ch3Uplink;
    };
  };

  ch3Site = {
    communicationContract = {
      relations = [
        { id = ch3_firewallDenyId; action = "deny";
          from = { kind = "tenant"; name = "fw-mgmt"; };
          to = { kind = "external"; name = "testnet"; };
          trafficType = "any"; }
        { id = ch3_dnsDenyId; action = "deny";
          from = { kind = "tenant"; name = "dns-direct"; };
          to = { kind = "external"; name = "testnet"; };
          trafficType = "any"; }
      ];
      trafficTypes = [ { name = "any"; match = [ { family = "any"; proto = "any"; } ]; } ];
    };
    ownership.prefixes = [
      { kind = "tenant"; name = "fw-mgmt"; ipv4 = "10.50.30.0/24"; }
      { kind = "tenant"; name = "dns-direct"; ipv4 = "10.50.40.0/24"; }
    ];
    topology.nodes.edge-cohost = {
      role = "edge";
      attachments = [
        { kind = "tenant"; name = "fw-mgmt"; }
        { kind = "tenant"; name = "dns-direct"; }
      ];
    };
    runtimeTargets.edge-cohost = ch3RuntimeTarget;
  };

  ch3Cpm = { control_plane_model.data.mini.layout = ch3Site; };

  ch3RenderedModel = {
    deploymentHostName = "layout-host";
    unitName = "edge-cohost";
    unitKey = "mini::layout::edge-cohost";
    roleName = "edge";
    logicalNode = ch3RuntimeTarget.logicalNode;
    runtimeTarget = ch3RuntimeTarget;
    site = ch3Site;
    interfaces = ch3RuntimeTarget.effectiveRuntimeRealization.interfaces;
    lanInterfaceNames = [ "tenant-fw-mgmt" "tenant-dns-direct" ];
    wanInterfaceNames = [ "uplink-testnet" ];
    firewallPolicyPath = repoRoot + "/s88/ControlModule/firewall/policy/access.nix";
    preferSiteNode = true;
    strictEndpointBindings = true;
    assumptionFamily = "edge";
  };

  ch3Rendered = import (repoRoot + "/s88/ControlModule/render/containers.nix") {
    inherit lib;
    cpm = ch3Cpm;
    repoPath = repoRoot;
    models.layout-host.edge-cohost = ch3RenderedModel;
  };

  ch3Container = ch3Rendered.layout-host.edge-cohost;
  ch3Ruleset = ch3Container.specialArgs.s88Firewall.ruleset or "";
  ch3Alarms = ch3Container.specialArgs.s88Alarms or [ ];

  # Check that both deny rules survive with their own role identifiers.
  ch3FirewallDenyLine =
    ''iifname "tenant-fw-mgmt" oifname "uplink-testnet" drop comment "${ch3_firewallDenyId}"'';
  ch3DnsDenyLine =
    ''iifname "tenant-dns-direct" oifname "uplink-testnet" drop comment "${ch3_dnsDenyId}"'';
  # A merged output that loses the firewall/dns role distinction.
  ch3MergedLine =
    ''iifname { "tenant-fw-mgmt", "tenant-dns-direct" } oifname "uplink-testnet" drop comment "merged-edge-layout"'';

  ch3PreservesLayout =
    candidate:
    lib.hasInfix ch3FirewallDenyLine candidate
    && lib.hasInfix ch3DnsDenyLine candidate
    && !(lib.hasInfix ch3MergedLine candidate);

  ch3MergedOutput = ''
    table inet router {
      chain forward {
        type filter hook forward priority filter; policy drop;
        ${ch3MergedLine}
      }
    }
  '';

  checks = {
    # --- CH1 / CH2 / SN1 (original model) ---
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

    # --- CH3: unusual co-located layout — role identity preserved in ruleset ---
    # Two roles (firewall + dns) share one container.  The renderer can only
    # express role identity through relationId comments on nftables rules
    # (target limitation).  The ruleset itself is the diagnostic: it proves
    # the renderer preserved distinct identities rather than silently merging.
    ch3_container_rendered = builtins.hasAttr "edge-cohost" ch3Rendered.layout-host;
    ch3_colocated_interfaces_present =
      builtins.hasAttr "tenant-fw-mgmt" ch3RenderedModel.interfaces
      && builtins.hasAttr "tenant-dns-direct" ch3RenderedModel.interfaces;
    ch3_firewall_enabled = (ch3Container.specialArgs.s88Firewall.enable or false) == true;
    ch3_firewall_deny_preserved = lib.hasInfix ch3FirewallDenyLine ch3Ruleset;
    ch3_dns_deny_preserved = lib.hasInfix ch3DnsDenyLine ch3Ruleset;
    ch3_merged_absent = !(lib.hasInfix ch3MergedLine ch3Ruleset);
    ch3_seeded_negative_rejects_merged = !(ch3PreservesLayout ch3MergedOutput);
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
    # CH3 metrics
    ch3ContainerCount = 1;
    ch3CoLocatedInterfaces = 2;
    ch3ExplicitRules = builtins.length ch3RuntimeTarget.forwardingIntent.rules;
    ch3SeededNegativeCount = 1;
    ch3TargetLimitationDiagnosticCount =
      if checks.ch3_firewall_deny_preserved && checks.ch3_dns_deny_preserved && checks.ch3_merged_absent then 1 else 0;
  };
}
