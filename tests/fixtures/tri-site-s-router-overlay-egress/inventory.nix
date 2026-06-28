# FS-320-HDS-010-SDS-010-SMS-030 and FS-460-HDS-010-SDS-010-SMS-050:
# fixture uses platform eth0 names as explicit inventory/runtime interface facts
# for delegated public-egress renderer tests.
let
  publicResolverCidrs = [
    "1.1.1.1/32"
    "1.0.0.1/32"
    "2606:4700:4700::1111/128"
    "2606:4700:4700::1001/128"
  ];
  withDeniedResolverCidrs =
    node:
    node
    // {
      services = (node.services or { }) // {
        dns = (node.services.dns or { }) // {
          deniedResolverCidrs = publicResolverCidrs;
        };
      };
    };
  clabAccessTenants = {
    admin = { };
    client = { };
    dmz = { };
    hostile = { };
    mgmt = { };
    streaming = { };
  };

  clabAccessNode =
    tenant: spec:
    {
      advertisements = {
        dhcp4."tenant-${tenant}" = {
          dnsServers = [ "router-self" ];
          domain = "lan.";
        };
        ipv6Ra."tenant-${tenant}" = {
          dnssl = [ "lan." ];
          rdnss = [ "router-self" ];
        };
      };
      host = "s-router-lab";
      logicalNode = {
        enterprise = "esp";
        name = "lab-example-router-access-${tenant}";
        site = "lab";
      };
      platform = "home-container";
      ports = {
        "tenant-${tenant}" = {
          attach = {
            bridge = tenant;
            kind = "bridge";
          };
          interface = {
            name = clabAccessIfName tenant;
          };
          logicalInterface = "tenant-${tenant}";
        };
        transit-downstream = {
          adapterName = "p2p-lab-example-router-access-${tenant}-lab-example-router-downstream-transit-downstream";
          attach = {
            bridge = "br-lab-downstream-${tenant}";
            kind = "bridge";
          };
          interface = {
            name = "transit";
          };
          link = "p2p-lab-example-router-access-${tenant}-lab-example-router-downstream";
        };
      };
      services = {
        dns = {
          advertised = {
            dnsServers = [ "router-self" ];
            rdnss = [ "router-self" ];
          };
          forwarders = [
            "10.20.10.1"
            "fd42:dead:beef:10::1"
          ];
          deniedResolverCidrs = publicResolverCidrs;
        };
      };
    };

  clabAccessNodes = builtins.listToAttrs (
    map
      (tenant: {
        name = "esp-lab-example-router-access-${tenant}";
        value = clabAccessNode tenant clabAccessTenants.${tenant};
      })
      (builtins.attrNames clabAccessTenants)
  );

  clabAccessTenantNames = builtins.attrNames clabAccessTenants;
  clabRuntimeTenantName = tenant: if tenant == "streaming" then "stream" else tenant;
  clabAccessIfName = tenant: "tenant-${clabRuntimeTenantName tenant}";
  clabDownstreamAccessIfName = tenant: "access-${clabRuntimeTenantName tenant}";
  clabDownstreamPolicyIfName = tenant: "policy-${clabRuntimeTenantName tenant}";
  clabPolicyDownstreamIfName = tenant: "down-${clabRuntimeTenantName tenant}";
  clabPolicyWanIfName = tenant: "up-${clabRuntimeTenantName tenant}";
  clabUpstreamWanIfName = tenant: "pol-${clabRuntimeTenantName tenant}";
  clabWanTenants = [ "admin" "client" "dmz" "streaming" ];
  clabEastWestTenants = [ "hostile" ];

  clabDownstreamAccessPorts = builtins.listToAttrs (
    map
      (tenant: {
        name = "access-${tenant}";
        value = {
          adapterName = "p2p-lab-example-router-access-${tenant}-lab-example-router-downstream-access-${tenant}";
          attach = {
            bridge = "br-lab-downstream-${tenant}";
            kind = "bridge";
          };
          interface = {
            name = clabDownstreamAccessIfName tenant;
          };
          link = "p2p-lab-example-router-access-${tenant}-lab-example-router-downstream";
        };
      })
      clabAccessTenantNames
  );

  clabDownstreamPolicyPorts = builtins.listToAttrs (
    map
      (tenant: {
        name = "policy-${tenant}";
        value = {
          adapterName = "p2p-lab-example-router-downstream-lab-example-router-policy--access-lab-example-router-access-${tenant}-policy-${tenant}";
          attach = {
            bridge = "br-lab-downstream-policy-access-${tenant}";
            kind = "bridge";
          };
          interface = {
            name = clabDownstreamPolicyIfName tenant;
          };
          link = "p2p-lab-example-router-downstream-lab-example-router-policy--access-lab-example-router-access-${tenant}";
        };
      })
      clabAccessTenantNames
  );

  clabPolicyDownstreamPorts = builtins.listToAttrs (
    map
      (tenant: {
        name = "downstream-${tenant}";
        value = {
          adapterName = "p2p-lab-example-router-downstream-lab-example-router-policy--access-lab-example-router-access-${tenant}-downstream-${tenant}";
          attach = {
            bridge = "br-lab-downstream-policy-access-${tenant}";
            kind = "bridge";
          };
          interface = {
            name = clabPolicyDownstreamIfName tenant;
          };
          link = "p2p-lab-example-router-downstream-lab-example-router-policy--access-lab-example-router-access-${tenant}";
        };
      })
      clabAccessTenantNames
  );

  clabPolicyWanPorts = builtins.listToAttrs (
    map
      (tenant: {
        name = "upstream-${tenant}";
        value = {
          adapterName = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-wan-upstream-${tenant}";
          attach = {
            bridge = "br-lab-policy-upstream-access-${tenant}";
            kind = "bridge";
          };
          interface = {
            name = clabPolicyWanIfName tenant;
          };
          link = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-wan";
        };
      })
      clabWanTenants
  );

  clabPolicyEastWestPorts = builtins.listToAttrs (
    map
      (tenant: {
        name = "upstream-${tenant}-east-west";
        value = {
          adapterName = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-east-west-upstream-${tenant}-east-west";
          attach = {
            bridge = "br-lab-policy-upstream-access-${tenant}-east-west";
            kind = "bridge";
          };
          interface = {
            name = "up-${tenant}-ew";
          };
          link = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-east-west";
        };
      })
      clabEastWestTenants
  );

  clabUpstreamWanPorts = builtins.listToAttrs (
    map
      (tenant: {
        name = "policy-${tenant}";
        value = {
          adapterName = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-wan-policy-${tenant}";
          attach = {
            bridge = "br-lab-policy-upstream-access-${tenant}";
            kind = "bridge";
          };
          interface = {
            name = clabUpstreamWanIfName tenant;
          };
          link = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-wan";
        };
      })
      clabWanTenants
  );

  clabUpstreamEastWestPorts = builtins.listToAttrs (
    map
      (tenant: {
        name = "policy-${tenant}-east-west";
        value = {
          adapterName = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-east-west-policy-${tenant}-east-west";
          attach = {
            bridge = "br-lab-policy-upstream-access-${tenant}-east-west";
            kind = "bridge";
          };
          interface = {
            name = "pol-${tenant}-ew";
          };
          link = "p2p-lab-example-router-policy-lab-example-router-upstream--access-lab-example-router-access-${tenant}--uplink-east-west";
        };
      })
      clabEastWestTenants
  );
in
{
  containerlab = {
    roles = {
      core = {
        forwarding = {
          disable_eth0 = false;
        };
      };
      downstream = {
        forwarding = {
          disable_eth0 = true;
        };
      };
      isp = {
        forwarding = {
          disable_eth0 = false;
        };
      };
      policy = {
        forwarding = {
          disable_eth0 = true;
        };
      };
      upstream = {
        forwarding = {
          disable_eth0 = true;
        };
      };
      wan-peer = {
        forwarding = {
          disable_eth0 = false;
        };
      };
    };
  };
  controlPlane = {
    sites = {
      esp = {
        home = {
          overlays = {
            east-west = {
              nodes = {
                edge-example-router-lighthouse = {
                  addr4 = "100.96.10.254/32";
                  addr6 = "fd42:dead:beef:ee::254/128";
                };
                home-example-router-core-nebula = {
                  addr4 = "100.96.10.1/32";
                  addr6 = "fd42:dead:beef:ee::1/128";
                };
              };
              nebula = {
                lighthouse = {
                  endpoint = "198.51.100.10";
                  endpointSourceFile = "/run/secrets/hetzner-lighthouse-public-ipv4";
                  endpoint6 = "2001:db8:51::10";
                  endpoint6SourceFile = "/run/secrets/hetzner-public-ipv6";
                  node = "edge-example-router-lighthouse";
                  port = 4242;
                };
                role = "core-client";
                runtimeNodes = {
                  home-example-router-core-nebula = {
                    unsafeRoutes = [
                      { route = "10.60.10.0/24"; via4 = "100.96.10.2"; install = true; }
                      { route = "10.70.10.0/24"; via4 = "100.96.10.2"; install = true; }
                      { route = "10.90.10.0/24"; via4 = "100.96.10.3"; install = true; }
                      { route = "10.90.20.0/24"; via4 = "100.96.10.3"; install = true; }
                      { route = "fd42:dead:cafe:10::/64"; via6 = "fd42:dead:beef:ee::3"; install = true; }
                      { route = "fd42:dead:cafe:20::/64"; via6 = "fd42:dead:beef:ee::3"; install = true; }
                      { route = "fd42:dead:feed:10::/64"; via6 = "fd42:dead:beef:ee::2"; install = true; }
                      { route = "fd42:dead:feed:70::/64"; via6 = "fd42:dead:beef:ee::2"; install = true; }
                    ];
                  };
                };
              };
              provider = "nebula";
              underlayEndpointSourceFiles = {
                ipv4 = [ "/run/secrets/hetzner-lighthouse-public-ipv4" "/run/secrets/hetzner-public-ipv4" ];
                ipv6 = [ "/run/secrets/hetzner-public-ipv6" ];
              };
              runtimeNodes = {
                home-example-router-core-nebula = {
                  container = {
                    profile = "core-router-nebula";
                    targetContainer = "home-example-router-core-nebula";
                  };
                  groups = [
                    "lab"
                    "core"
                  ];
                  service = {
                    interface = "nebula1";
                    name = "nebula-runtime";
                  };
                  relay = {
                    relays = [ "edge-example-router-nebula-core" ];
                  };
                };
              };
            };
          };
          routing = {
            bgp = {
              asn = 65000;
              topology = "policy-rr";
            };
            mode = "bgp";
          };
          tenants = {
            hostile = {
              ipv6 = {
                mode = "slaac";
              };
            };
          };
        };
        edge = {
          overlays = {
            east-west = {
              nodes = {
                edge-example-router-lighthouse = {
                  addr4 = "100.96.10.254/32";
                  addr6 = "fd42:dead:beef:ee::254/128";
                };
                edge-example-router-nebula-core = {
                  addr4 = "100.96.10.3/32";
                  addr6 = "fd42:dead:beef:ee::3/128";
                };
              };
              nebula = {
                lighthouse = {
                  endpoint = "198.51.100.10";
                  endpointSourceFile = "/run/secrets/hetzner-lighthouse-public-ipv4";
                  endpoint6 = "2001:db8:51::10";
                  endpoint6SourceFile = "/run/secrets/hetzner-public-ipv6";
                  node = "edge-example-router-lighthouse";
                  port = 4242;
                };
                role = "core-client";
                runtimeNodes = {
                  edge-example-router-lighthouse = {
                    unsafeRoutes = [ ];
                  };
                  edge-example-router-nebula-core = {
                    unsafeRoutes = [
                      { route = "10.20.10.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.15.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.20.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.30.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.40.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.50.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.60.10.0/24"; via4 = "100.96.10.2"; install = true; }
                      { route = "10.70.10.0/24"; via4 = "100.96.10.2"; install = true; }
                      { route = "fd42:dead:beef:10::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:15::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:20::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:30::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:40::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:50::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:feed:10::/64"; via6 = "fd42:dead:beef:ee::2"; install = true; }
                      { route = "fd42:dead:feed:70::/64"; via6 = "fd42:dead:beef:ee::2"; install = true; }
                      {
                        route = "fd42:dead:feed:70::/64";
                        via6 = "fd42:dead:beef:ee::2";
                        install = true;
                        routeSourceFile = "/run/secrets/access-node-ipv6-prefix-esp-lab-example-router-access-hostile";
                      }
                    ];
                  };
                };
              };
              provider = "nebula";
              underlayEndpointSourceFiles = {
                ipv4 = [ "/run/secrets/hetzner-lighthouse-public-ipv4" "/run/secrets/hetzner-public-ipv4" ];
                ipv6 = [ "/run/secrets/hetzner-public-ipv6" ];
              };
              runtimeNodes = {
                edge-example-router-lighthouse = {
                  container = {
                    host = "s-router-hetzner-anywhere";
                    hostBridge = "dmz";
                    profile = "core-client";
                  };
                  groups = [
                    "lab"
                    "edge"
                    "lighthouse"
                  ];
                  service = {
                    interface = "nebula1";
                    name = "nebula-runtime";
                  };
                };
                edge-example-router-nebula-core = {
                  container = {
                    host = "s-router-hetzner-anywhere";
                    profile = "core-router-nebula";
                    targetContainer = "edge-example-router-nebula-core";
                  };
                  groups = [
                    "lab"
                    "edge"
                    "core"
                  ];
                  service = {
                    interface = "nebula1";
                    listenHost = "172.31.254.4";
                    name = "nebula-runtime";
                    port = 4243;
                    publicEndpoints = [
                      {
                        endpointSourceFile = "/run/secrets/hetzner-public-ipv4";
                        port = 4243;
                      }
                    ];
                  };
                  relay = {
                    amRelay = true;
                  };
                };
              };
            };
          };
          routing = {
            bgp = {
              asn = 65020;
              topology = "policy-rr";
            };
            mode = "bgp";
          };
          tenants = {
            client = { };
          };
        };
        lab = {
          overlays = {
            east-west = {
              nodes = {
                lab-example-router-core-nebula = {
                  addr4 = "100.96.10.2/32";
                  addr6 = "fd42:dead:beef:ee::2/128";
                };
                branch-node01 = {
                  addr4 = "100.96.10.20/32";
                  addr6 = "fd42:dead:beef:ee::20/128";
                };
                edge-example-router-lighthouse = {
                  addr4 = "100.96.10.254/32";
                  addr6 = "fd42:dead:beef:ee::254/128";
                };
                hostile-node01 = {
                  addr4 = "100.96.10.30/32";
                  addr6 = "fd42:dead:beef:ee::30/128";
                };
              };
              nebula = {
                lighthouse = {
                  endpoint = "198.51.100.10";
                  endpointSourceFile = "/run/secrets/hetzner-lighthouse-public-ipv4";
                  endpoint6 = "2001:db8:51::10";
                  endpoint6SourceFile = "/run/secrets/hetzner-public-ipv6";
                  node = "edge-example-router-lighthouse";
                  port = 4242;
                };
                role = "core-client";
                runtimeNodes = {
                  lab-example-router-core-nebula = {
                    unsafeRoutes = [
                      { route = "0.0.0.0/1"; via4 = "100.96.10.3"; install = true; }
                      { route = "128.0.0.0/1"; via4 = "100.96.10.3"; install = true; }
                      { route = "10.20.10.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.15.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.20.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.30.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.40.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.20.50.0/24"; via4 = "100.96.10.1"; install = true; }
                      { route = "10.90.10.0/24"; via4 = "100.96.10.3"; install = true; }
                      { route = "10.90.20.0/24"; via4 = "100.96.10.3"; install = true; }
                      { route = "::/1"; via6 = "fd42:dead:beef:ee::3"; install = true; }
                      { route = "8000::/1"; via6 = "fd42:dead:beef:ee::3"; install = true; }
                      { route = "fd42:dead:beef:10::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:15::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:20::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:30::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:40::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:beef:50::/64"; via6 = "fd42:dead:beef:ee::1"; install = true; }
                      { route = "fd42:dead:cafe:10::/64"; via6 = "fd42:dead:beef:ee::3"; install = true; }
                      { route = "fd42:dead:cafe:20::/64"; via6 = "fd42:dead:beef:ee::3"; install = true; }
                    ];
                  };
                };
              };
              provider = "nebula";
              underlayEndpointSourceFiles = {
                ipv4 = [ "/run/secrets/hetzner-lighthouse-public-ipv4" "/run/secrets/hetzner-public-ipv4" ];
                ipv6 = [ "/run/secrets/hetzner-public-ipv6" ];
              };
              runtimeNodes = {
                lab-example-router-core-nebula = {
                  container = {
                    profile = "core-router-nebula";
                    targetContainer = "lab-example-router-core-nebula";
                  };
                  groups = [
                    "lab"
                    "branch"
                    "core"
                  ];
                  service = {
                    interface = "nebula1";
                    name = "nebula-runtime";
                  };
                  relay = {
                    relays = [ "edge-example-router-nebula-core" ];
                  };
                };
              };
            };
          };
          routing = {
            bgp = {
              asn = 65100;
              topology = "policy-rr";
            };
            mode = "bgp";
          };
          tenants = {
            admin = {
              ipv6 = {
                mode = "slaac";
              };
            };
            client = {
              ipv6 = {
                mode = "slaac";
              };
            };
            dmz = {
              ipv6 = {
                mode = "slaac";
              };
            };
            hostile = {
              ipv6 = {
                mode = "slaac";
              };
            };
            mgmt = {
              ipv6 = {
                mode = "slaac";
              };
            };
            streaming = {
              ipv6 = {
                mode = "slaac";
              };
            };
          };
        };
      };
    };
  };
  deployment = {
    hosts = {
      s-router-hetzner-anywhere = {
        bridgeNetworks = {
          br-edge-core-upstream = { };
          br-edge-downstream-client = { };
          br-edge-downstream-dmz = { };
          br-edge-downstream-policy-access-client = { };
          br-edge-downstream-policy-access-dmz = { };
          br-edge-nebula-core-upstream = { };
          br-edge-policy-upstream-access-client-east-west = { };
          br-edge-policy-upstream-access-client-wan = { };
          br-edge-policy-upstream-access-dmz-east-west = { };
          br-edge-policy-upstream-access-dmz-wan = { };
          client = { };
          dmz = { };
        };
        uplinks = {
          wan = {
            bridge = "br-wan";
            hostAddresses = [
              "172.31.254.1/24"
              "fd42:dead:cafe:ffff::1/64"
            ];
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
              enable = true;
              method = "slaac";
            };
            mode = "native";
            parent = "eth0";
          };
        };
        wanUplink = "wan";
      };
      s-router-test = {
        bridgeNetworks = {
          admin = {
            mode = "vlan";
            parent = "eth0";
            vlan = 301;
          };
          br-home-core-isp-a-upstream = { };
          br-home-core-isp-b-upstream = { };
          br-home-core-nebula-upstream = { };
          br-home-downstream-admin = { };
          br-home-downstream-client = { };
          br-home-downstream-dmz = { };
          br-home-downstream-hostile = { };
          br-home-downstream-mgmt = { };
          br-home-downstream-policy-access-admin = { };
          br-home-downstream-policy-access-client = { };
          br-home-downstream-policy-access-dmz = { };
          br-home-downstream-policy-access-hostile = { };
          br-home-downstream-policy-access-mgmt = { };
          br-home-downstream-policy-access-streaming = { };
          br-home-downstream-streaming = { };
          br-home-policy-upstream-access-admin-isp-a = { };
          br-home-policy-upstream-access-admin-isp-b = { };
          br-home-policy-upstream-access-client-isp-a = { };
          br-home-policy-upstream-access-client-isp-b = { };
          br-home-policy-upstream-access-dmz-isp-a = { };
          br-home-policy-upstream-access-dmz-isp-b = { };
          br-home-policy-upstream-access-hostile-east-west = { };
          br-home-policy-upstream-access-mgmt-isp-a = { };
          br-home-policy-upstream-access-mgmt-isp-b = { };
          br-home-policy-upstream-access-streaming-isp-a = { };
          br-home-policy-upstream-access-streaming-isp-b = { };
          br-edge-core-upstream = { };
          br-edge-downstream-mgmt = { };
          br-edge-downstream-policy-access-mgmt = { };
          br-edge-nebula-core-upstream = { };
          br-edge-policy-upstream-access-mgmt-wan = { };
          branch = {
            mode = "vlan";
            parent = "eth0";
            vlan = 305;
          };
          client = {
            mode = "vlan";
            parent = "eth0";
            vlan = 302;
          };
          dmz = {
            mode = "vlan";
            parent = "eth0";
            vlan = 304;
          };
          hostile = {
            mode = "vlan";
            parent = "eth0";
            vlan = 306;
          };
          mgmt = {
            mode = "vlan";
            parent = "eth0";
            vlan = 300;
          };
          streaming = {
            mode = "vlan";
            parent = "eth0";
            vlan = 311;
          };
        };
        uplinks = {
          management = {
            bridge = "vlan2";
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = false;
              dhcp = false;
              dhcpv6PD = false;
              enable = false;
              method = "none";
            };
            mode = "vlan";
            parent = "eth0";
            vlan = 2;
          };
          uplink-isp-a = {
            bridge = "br-uplink0";
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
              enable = true;
              method = "slaac";
            };
            mode = "vlan";
            parent = "eth0";
            upstream = "isp-a";
            vlan = 4;
          };
          uplink-isp-b = {
            bridge = "br-uplink1";
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
              enable = true;
              method = "slaac";
            };
            mode = "vlan";
            parent = "eth0";
            upstream = "isp-b";
            vlan = 5;
          };
        };
        wanUplink = "uplink-isp-b";
      };
      s-router-lab = {
        bridgeNetworks = {
          admin = {
            mode = "vlan";
            parent = "eth0";
            vlan = 301;
          };
          br-lab-core-simulated-isp-upstream = { };
          br-lab-core-nebula-upstream = { };
          br-lab-downstream-admin = { };
          br-lab-downstream-client = { };
          br-lab-downstream-dmz = { };
          br-lab-downstream-hostile = { };
          br-lab-downstream-mgmt = { };
          br-lab-downstream-streaming = { };
          br-lab-downstream-policy-access-admin = { };
          br-lab-downstream-policy-access-client = { };
          br-lab-downstream-policy-access-dmz = { };
          br-lab-downstream-policy-access-hostile = { };
          br-lab-downstream-policy-access-mgmt = { };
          br-lab-downstream-policy-access-streaming = { };
          br-lab-policy-upstream-access-admin = { };
          br-lab-policy-upstream-access-admin-east-west = { };
          br-lab-policy-upstream-access-client = { };
          br-lab-policy-upstream-access-client-east-west = { };
          br-lab-policy-upstream-access-dmz = { };
          br-lab-policy-upstream-access-dmz-east-west = { };
          br-lab-policy-upstream-access-hostile = { };
          br-lab-policy-upstream-access-hostile-east-west = { };
          br-lab-policy-upstream-access-mgmt = { };
          br-lab-policy-upstream-access-mgmt-east-west = { };
          br-lab-policy-upstream-access-streaming = { };
          br-lab-policy-upstream-access-streaming-east-west = { };
          branch = {
            mode = "vlan";
            parent = "eth0";
            vlan = 305;
          };
          client = {
            mode = "vlan";
            parent = "eth0";
            vlan = 302;
          };
          dmz = {
            mode = "vlan";
            parent = "eth0";
            vlan = 304;
          };
          hostile = {
            mode = "vlan";
            parent = "eth0";
            vlan = 306;
          };
          mgmt = {
            mode = "vlan";
            parent = "eth0";
            vlan = 300;
          };
          streaming = {
            mode = "vlan";
            parent = "eth0";
            vlan = 311;
          };
        };
        uplinks = {
          management = {
            bridge = "vlan2";
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = false;
              dhcp = false;
              dhcpv6PD = false;
              enable = false;
              method = "none";
            };
            mode = "vlan";
            parent = "eth0";
            vlan = 2;
          };
          uplink-isp-a = {
            bridge = "br-uplink0";
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
              enable = true;
              method = "slaac";
            };
            mode = "vlan";
            parent = "eth0";
            upstream = "isp-a";
            vlan = 4;
          };
          uplink-isp-b = {
            bridge = "br-uplink1";
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
              enable = true;
              method = "slaac";
            };
            mode = "vlan";
            parent = "eth0";
            upstream = "isp-b";
            vlan = 5;
          };
        };
        wanUplink = "uplink-isp-b";
      };
      s-router-test-clients = {
        bridgeNetworks = {
          admin = {
            mode = "vlan";
            parent = "eth0";
            vlan = 301;
          };
          branch = {
            mode = "vlan";
            parent = "eth0";
            vlan = 305;
          };
          client = {
            mode = "vlan";
            parent = "eth0";
            vlan = 302;
          };
          dmz = {
            mode = "vlan";
            parent = "eth0";
            vlan = 304;
          };
          hostile = {
            mode = "vlan";
            parent = "eth0";
            vlan = 306;
          };
          mgmt = {
            mode = "vlan";
            parent = "eth0";
            vlan = 300;
          };
          streaming = {
            mode = "vlan";
            parent = "eth0";
            vlan = 311;
          };
        };
        uplinks = {
          management = {
            bridge = "vlan2";
            ipv4 = {
              dhcp = true;
              enable = true;
              method = "dhcp";
            };
            ipv6 = {
              acceptRA = false;
              dhcp = false;
              dhcpv6PD = false;
              enable = false;
              method = "none";
            };
            mode = "vlan";
            parent = "eth0";
            vlan = 2;
          };
        };
      };
    };
  };
  endpoints = {
    lab-client01 = {
      ipv4 = [ "10.50.20.10" ];
      ipv6 = [ "fd42:dead:feed:20::10" ];
    };
    lab-client02 = {
      ipv4 = [ "10.50.20.11" ];
      ipv6 = [ "fd42:dead:feed:20::11" ];
    };
    lab-site-dns = {
      ipv4 = [ "10.50.10.1" ];
      ipv6 = [ "fd42:dead:feed:10::1" ];
    };
    lab-streaming01 = {
      ipv4 = [ "10.50.50.10" ];
      ipv6 = [ "fd42:dead:feed:50::10" ];
    };
    edge-example-router-lighthouse = {
      ipv4 = [ "10.90.10.100" ];
      ipv6 = [ "fd42:dead:cafe:10::100" ];
    };
    hostile-node01 = {
      ipv4 = [ "10.70.10.10" ];
      ipv6 = [ "fd42:dead:feed:70::10" ];
    };
    home-hostile01 = {
      ipv4 = [ "10.20.70.10" ];
      ipv6 = [ "fd42:dead:beef:70::10" ];
    };
    nebula01 = {
      ipv4 = [ "10.20.30.10" ];
      ipv6 = [ "fd42:dead:beef:30::10" ];
    };
    site-dns-mgmt = {
      ipv4 = [ "10.20.10.1" ];
      ipv6 = [ "fd42:dead:beef:10::1" ];
    };
    edge-dns-dmz = {
      ipv4 = [ "10.90.10.1" ];
      ipv6 = [ "fd42:dead:cafe:10::1" ];
    };
    edge-client01 = {
      ipv4 = [ "10.90.20.10" ];
      ipv6 = [ "fd42:dead:cafe:20::10" ];
    };
  };
  realization = {
    nodes = {
      esp-home-example-router-access-admin = {
        advertisements = {
          dhcp4 = {
            tenant-admin = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-admin = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-access-admin";
          site = "home";
        };
        platform = "home-container";
        ports = {
          tenant-admin = {
            attach = {
              bridge = "admin";
              kind = "bridge";
            };
            interface = {
              name = "tenant-admin";
            };
            logicalInterface = "tenant-admin";
          };
          transit-downstream = {
            adapterName = "p2p-home-example-router-access-admin-home-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-home-downstream-admin";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-home-example-router-access-admin-home-example-router-downstream";
          };
        };
        services = {
          dns = {
            forwarders = [
              "10.20.10.1"
              "fd42:dead:beef:10::1"
            ];
            deniedResolverCidrs = publicResolverCidrs;
          };
        };
      };
      esp-home-example-router-access-client = {
        advertisements = {
          dhcp4 = {
            tenant-client = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-client = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-access-client";
          site = "home";
        };
        platform = "home-container";
        ports = {
          tenant-client = {
            attach = {
              bridge = "client";
              kind = "bridge";
            };
            interface = {
              name = "tenant-client";
            };
            logicalInterface = "tenant-client";
          };
          transit-downstream = {
            adapterName = "p2p-home-example-router-access-client-home-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-home-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-home-example-router-access-client-home-example-router-downstream";
          };
        };
        services = {
          dns = {
            forwarders = [
              "10.20.10.1"
              "fd42:dead:beef:10::1"
            ];
            deniedResolverCidrs = publicResolverCidrs;
          };
        };
      };
      esp-home-example-router-access-dmz = {
        advertisements = {
          dhcp4 = {
            tenant-dmz = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-dmz = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-access-dmz";
          site = "home";
        };
        platform = "home-container";
        ports = {
          tenant-dmz = {
            attach = {
              bridge = "dmz";
              kind = "bridge";
            };
            interface = {
              name = "tenant-dmz";
            };
            logicalInterface = "tenant-dmz";
          };
          transit-downstream = {
            adapterName = "p2p-home-example-router-access-dmz-home-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-home-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-home-example-router-access-dmz-home-example-router-downstream";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
            forwarders = [
              "10.20.10.1"
              "fd42:dead:beef:10::1"
            ];
            deniedResolverCidrs = publicResolverCidrs;
          };
        };
      };
      esp-home-example-router-access-hostile = {
        advertisements = {
          dhcp4 = {
            tenant-hostile = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-hostile = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-access-hostile";
          site = "home";
        };
        platform = "home-container";
        ports = {
          tenant-hostile = {
            attach = {
              bridge = "hostile";
              kind = "bridge";
            };
            interface = {
              name = "tenant-hostile";
            };
            logicalInterface = "tenant-hostile";
          };
          transit-downstream = {
            adapterName = "p2p-home-example-router-access-hostile-home-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-home-downstream-hostile";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-home-example-router-access-hostile-home-example-router-downstream";
          };
        };
        services = {
          dns = {
            forwarders = [
              "1.1.1.1"
              "1.0.0.1"
              "2606:4700:4700::1111"
              "2606:4700:4700::1001"
            ];
            deniedResolverCidrs = publicResolverCidrs;
          };
        };
      };
      esp-home-example-router-access-mgmt = {
        advertisements = {
          dhcp4 = {
            tenant-mgmt = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-mgmt = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-access-mgmt";
          site = "home";
        };
        platform = "home-container";
        ports = {
          tenant-mgmt = {
            attach = {
              bridge = "mgmt";
              kind = "bridge";
            };
            interface = {
              name = "tenant-mgmt";
            };
            logicalInterface = "tenant-mgmt";
          };
          transit-downstream = {
            adapterName = "p2p-home-example-router-access-mgmt-home-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-home-downstream-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-home-example-router-access-mgmt-home-example-router-downstream";
          };
        };
        services = {
          dns = {
            forwarders = [
              "1.1.1.1"
              "1.0.0.1"
              "2606:4700:4700::1111"
              "2606:4700:4700::1001"
            ];
            deniedResolverCidrs = publicResolverCidrs;
          };
        };
      };
      esp-home-example-router-access-streaming = {
        advertisements = {
          dhcp4 = {
            tenant-streaming = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-streaming = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-access-streaming";
          site = "home";
        };
        platform = "home-container";
        ports = {
          tenant-streaming = {
            attach = {
              bridge = "streaming";
              kind = "bridge";
            };
            interface = {
              name = "tenant-stream";
            };
            logicalInterface = "tenant-streaming";
          };
          transit-downstream = {
            adapterName = "p2p-home-example-router-access-streaming-home-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-home-downstream-streaming";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-home-example-router-access-streaming-home-example-router-downstream";
          };
        };
        services = {
          dns = {
            forwarders = [
              "10.20.10.1"
              "fd42:dead:beef:10::1"
            ];
            deniedResolverCidrs = publicResolverCidrs;
          };
        };
      };
      esp-home-example-router-core-isp-a = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-core-isp-a";
          site = "home";
        };
        platform = "home-container";
        ports = {
          isp-a = {
            attach = {
              bridge = "br-uplink0";
              kind = "bridge";
            };
            external = true;
            interface = {
              name = "isp-a";
            };
            uplink = "isp-a";
          };
          upstream = {
            adapterName = "p2p-home-example-router-core-isp-a-home-example-router-upstream-upstream";
            attach = {
              bridge = "br-home-core-isp-a-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-home-example-router-core-isp-a-home-example-router-upstream";
          };
        };
      };
      esp-home-example-router-core-isp-b = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-core-isp-b";
          site = "home";
        };
        platform = "home-container";
        ports = {
          isp-b = {
            attach = {
              bridge = "br-uplink1";
              kind = "bridge";
            };
            external = true;
            interface = {
              name = "isp-b";
            };
            uplink = "isp-b";
          };
          upstream = {
            adapterName = "p2p-home-example-router-core-isp-b-home-example-router-upstream-upstream";
            attach = {
              bridge = "br-home-core-isp-b-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-home-example-router-core-isp-b-home-example-router-upstream";
          };
        };
      };
      esp-home-example-router-core-nebula = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-core-nebula";
          site = "home";
        };
        platform = "home-container";
        ports = {
          tenant-client = {
            attach = {
              bridge = "client";
              kind = "bridge";
            };
            interface = {
              name = "client";
            };
            logicalInterface = "tenant-client";
          };
          upstream = {
            adapterName = "p2p-home-example-router-core-nebula-home-example-router-upstream-upstream";
            attach = {
              bridge = "br-home-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-home-example-router-core-nebula-home-example-router-upstream";
          };
        };
      };
      esp-home-example-router-downstream = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-downstream";
          site = "home";
        };
        platform = "home-container";
        ports = {
          access-admin = {
            adapterName = "p2p-home-example-router-access-admin-home-example-router-downstream-access-admin";
            attach = {
              bridge = "br-home-downstream-admin";
              kind = "bridge";
            };
            interface = {
              name = "access-admin";
            };
            link = "p2p-home-example-router-access-admin-home-example-router-downstream";
          };
          access-client = {
            adapterName = "p2p-home-example-router-access-client-home-example-router-downstream-access-client";
            attach = {
              bridge = "br-home-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "access-client";
            };
            link = "p2p-home-example-router-access-client-home-example-router-downstream";
          };
          access-dmz = {
            adapterName = "p2p-home-example-router-access-dmz-home-example-router-downstream-access-dmz";
            attach = {
              bridge = "br-home-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "access-dmz";
            };
            link = "p2p-home-example-router-access-dmz-home-example-router-downstream";
          };
          access-hostile = {
            adapterName = "p2p-home-example-router-access-hostile-home-example-router-downstream-access-hostile";
            attach = {
              bridge = "br-home-downstream-hostile";
              kind = "bridge";
            };
            interface = {
              name = "access-hostile";
            };
            link = "p2p-home-example-router-access-hostile-home-example-router-downstream";
          };
          access-mgmt = {
            adapterName = "p2p-home-example-router-access-mgmt-home-example-router-downstream-access-mgmt";
            attach = {
              bridge = "br-home-downstream-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "access-mgmt";
            };
            link = "p2p-home-example-router-access-mgmt-home-example-router-downstream";
          };
          access-streaming = {
            adapterName = "p2p-home-example-router-access-streaming-home-example-router-downstream-access-streaming";
            attach = {
              bridge = "br-home-downstream-streaming";
              kind = "bridge";
            };
            interface = {
              name = "access-stream";
            };
            link = "p2p-home-example-router-access-streaming-home-example-router-downstream";
          };
          policy-admin = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-admin-policy-admin";
            attach = {
              bridge = "br-home-downstream-policy-access-admin";
              kind = "bridge";
            };
            interface = {
              name = "policy-admin";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-admin";
          };
          policy-client = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-client-policy-client";
            attach = {
              bridge = "br-home-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "policy-client";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-client";
          };
          policy-dmz = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-dmz-policy-dmz";
            attach = {
              bridge = "br-home-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "policy-dmz";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-dmz";
          };
          policy-hostile = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-hostile-policy-hostile";
            attach = {
              bridge = "br-home-downstream-policy-access-hostile";
              kind = "bridge";
            };
            interface = {
              name = "policy-hostile";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-hostile";
          };
          policy-mgmt = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-mgmt-policy-mgmt";
            attach = {
              bridge = "br-home-downstream-policy-access-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "policy-mgmt";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-mgmt";
          };
          policy-streaming = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-streaming-policy-streaming";
            attach = {
              bridge = "br-home-downstream-policy-access-streaming";
              kind = "bridge";
            };
            interface = {
              name = "policy-stream";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-streaming";
          };
        };
      };
      esp-home-example-router-policy = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-policy";
          site = "home";
        };
        platform = "home-container";
        ports = {
          downstream-admin = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-admin-downstream-admin";
            attach = {
              bridge = "br-home-downstream-policy-access-admin";
              kind = "bridge";
            };
            interface = {
              name = "down-admin";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-admin";
          };
          downstream-client = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-client-downstream-client";
            attach = {
              bridge = "br-home-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "down-client";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-client";
          };
          downstream-dmz = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-dmz-downstream-dmz";
            attach = {
              bridge = "br-home-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "downstream-dmz";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-dmz";
          };
          downstream-hostile = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-hostile-downstream-hostile";
            attach = {
              bridge = "br-home-downstream-policy-access-hostile";
              kind = "bridge";
            };
            interface = {
              name = "down-hostile";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-hostile";
          };
          downstream-mgmt = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-mgmt-downstream-mgmt";
            attach = {
              bridge = "br-home-downstream-policy-access-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "downstream-mgmt";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-mgmt";
          };
          downstream-streaming = {
            adapterName = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-streaming-downstream-streaming";
            attach = {
              bridge = "br-home-downstream-policy-access-streaming";
              kind = "bridge";
            };
            interface = {
              name = "downstr-stream";
            };
            link = "p2p-home-example-router-downstream-home-example-router-policy--access-home-example-router-access-streaming";
          };
          upstream-admin-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-a-upstream-admin-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-admin-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-admin-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-a";
          };
          upstream-admin-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-b-upstream-admin-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-admin-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-admin-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-b";
          };
          upstream-client-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-a-upstream-client-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-client-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-client-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-a";
          };
          upstream-client-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-b-upstream-client-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-client-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-client-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-b";
          };
          upstream-dmz-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-a-upstream-dmz-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-dmz-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-dmz-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-a";
          };
          upstream-dmz-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-b-upstream-dmz-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-dmz-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-dmz-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-b";
          };
          upstream-hostile-east-west = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-hostile--uplink-east-west-upstream-hostile-east-west";
            attach = {
              bridge = "br-home-policy-upstream-access-hostile-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-hostile-ew";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-hostile--uplink-east-west";
          };
          upstream-mgmt-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-a-upstream-mgmt-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-mgmt-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-mgmt-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-a";
          };
          upstream-mgmt-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-b-upstream-mgmt-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-mgmt-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-mgmt-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-b";
          };
          upstream-streaming-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-a-upstream-streaming-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-streaming-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-stream-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-a";
          };
          upstream-streaming-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-b-upstream-streaming-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-streaming-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-stream-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-b";
          };
        };
      };
      esp-home-example-router-upstream = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp";
          name = "home-example-router-upstream";
          site = "home";
        };
        platform = "home-container";
        ports = {
          core-isp-a = {
            adapterName = "p2p-home-example-router-core-isp-a-home-example-router-upstream-core-isp-a";
            attach = {
              bridge = "br-home-core-isp-a-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-a";
            };
            link = "p2p-home-example-router-core-isp-a-home-example-router-upstream";
          };
          core-isp-b = {
            adapterName = "p2p-home-example-router-core-isp-b-home-example-router-upstream-core-isp-b";
            attach = {
              bridge = "br-home-core-isp-b-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-b";
            };
            link = "p2p-home-example-router-core-isp-b-home-example-router-upstream";
          };
          core-nebula = {
            adapterName = "p2p-home-example-router-core-nebula-home-example-router-upstream-core-nebula";
            attach = {
              bridge = "br-home-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-nebula";
            };
            link = "p2p-home-example-router-core-nebula-home-example-router-upstream";
          };
          policy-admin-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-a-policy-admin-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-admin-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-admin-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-a";
          };
          policy-admin-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-b-policy-admin-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-admin-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-admin-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-admin--uplink-isp-b";
          };
          policy-client-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-a-policy-client-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-client-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-client-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-a";
          };
          policy-client-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-b-policy-client-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-client-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-client-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-client--uplink-isp-b";
          };
          policy-dmz-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-a-policy-dmz-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-dmz-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-dmz-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-a";
          };
          policy-dmz-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-b-policy-dmz-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-dmz-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-dmz-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-dmz--uplink-isp-b";
          };
          policy-hostile-east-west = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-hostile--uplink-east-west-policy-hostile-east-west";
            attach = {
              bridge = "br-home-policy-upstream-access-hostile-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-hostile-ew";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-hostile--uplink-east-west";
          };
          policy-mgmt-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-a-policy-mgmt-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-mgmt-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-mgmt-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-a";
          };
          policy-mgmt-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-b-policy-mgmt-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-mgmt-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-mgmt-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-mgmt--uplink-isp-b";
          };
          policy-streaming-isp-a = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-a-policy-streaming-isp-a";
            attach = {
              bridge = "br-home-policy-upstream-access-streaming-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-stream-a";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-a";
          };
          policy-streaming-isp-b = {
            adapterName = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-b-policy-streaming-isp-b";
            attach = {
              bridge = "br-home-policy-upstream-access-streaming-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-stream-b";
            };
            link = "p2p-home-example-router-policy-home-example-router-upstream--access-home-example-router-access-streaming--uplink-isp-b";
          };
        };
      };
      esp-edge-example-router-access-client = withDeniedResolverCidrs {
        advertisements = {
          dhcp4 = {
            tenant-client = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-client = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp";
          name = "edge-example-router-access-client";
          site = "edge";
        };
        platform = "home-container";
        ports = {
          tenant-client = {
            attach = {
              bridge = "client";
              kind = "bridge";
            };
            interface = {
              name = "tenant-client";
            };
            logicalInterface = "tenant-client";
          };
          transit-downstream = {
            adapterName = "p2p-edge-example-router-access-client-edge-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-edge-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-edge-example-router-access-client-edge-example-router-downstream";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
          };
        };
      };
      esp-edge-example-router-access-dmz = {
        advertisements = {
          dhcp4 = {
            tenant-dmz = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-dmz = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp";
          name = "edge-example-router-access-dmz";
          site = "edge";
        };
        platform = "home-container";
        ports = {
          tenant-dmz = {
            attach = {
              bridge = "dmz";
              kind = "bridge";
            };
            interface = {
              name = "tenant-dmz";
            };
            logicalInterface = "tenant-dmz";
          };
          transit-downstream = {
            adapterName = "p2p-edge-example-router-access-dmz-edge-example-router-downstream-transit-downstream";
            attach = {
              bridge = "br-edge-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-edge-example-router-access-dmz-edge-example-router-downstream";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
            forwarders = [
              "1.1.1.1"
              "1.0.0.1"
              "2606:4700:4700::1111"
              "2606:4700:4700::1001"
            ];
            deniedResolverCidrs = publicResolverCidrs;
          };
        };
      };
      esp-edge-example-router-core = withDeniedResolverCidrs {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp";
          name = "edge-example-router-core";
          site = "edge";
        };
        platform = "home-container";
        ports = {
          upstream = {
            adapterName = "p2p-edge-example-router-core-edge-example-router-upstream-upstream";
            attach = {
              bridge = "br-edge-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-edge-example-router-core-edge-example-router-upstream";
          };
          wan = {
            attach = {
              bridge = "br-wan";
              kind = "bridge";
            };
            external = true;
            interface = {
              addr4 = "172.31.254.3/24";
              addr6 = "fd42:dead:cafe:ffff::3/64";
              name = "wan";
              routes = {
                ipv4 = [
                  {
                    prefix = "0.0.0.0/0";
                    via = "172.31.254.1";
                  }
                ];
                ipv6 = [
                  {
                    prefix = "::/0";
                    via = "fd42:dead:cafe:ffff::1";
                  }
                ];
              };
            };
            uplink = "wan";
          };
        };
      };
      esp-edge-example-router-downstream = {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp";
          name = "edge-example-router-downstream";
          site = "edge";
        };
        platform = "home-container";
        ports = {
          access-client = {
            adapterName = "p2p-edge-example-router-access-client-edge-example-router-downstream-access-client";
            attach = {
              bridge = "br-edge-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "access-client";
            };
            link = "p2p-edge-example-router-access-client-edge-example-router-downstream";
          };
          access-dmz = {
            adapterName = "p2p-edge-example-router-access-dmz-edge-example-router-downstream-access-dmz";
            attach = {
              bridge = "br-edge-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "access-dmz";
            };
            link = "p2p-edge-example-router-access-dmz-edge-example-router-downstream";
          };
          policy-client = {
            adapterName = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-client-policy-client";
            attach = {
              bridge = "br-edge-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "policy-client";
            };
            link = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-client";
          };
          policy-dmz = {
            adapterName = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-dmz-policy-dmz";
            attach = {
              bridge = "br-edge-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "policy-dmz";
            };
            link = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-dmz";
          };
        };
      };
      esp-edge-example-router-nebula-core = withDeniedResolverCidrs {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp";
          name = "edge-example-router-nebula-core";
          site = "edge";
        };
        platform = "home-container";
        ports = {
          east-west = {
            attach = {
              bridge = "br-wan";
              kind = "bridge";
            };
            external = true;
            interface = {
              addr4 = "172.31.254.2/24";
              name = "east-west";
              routes = {
                ipv4 = [
                  {
                    metric = 5000;
                    prefix = "0.0.0.0/0";
                    via = "172.31.254.1";
                  }
                ];
              };
            };
            uplink = "east-west";
          };
          upstream = {
            adapterName = "p2p-edge-example-router-nebula-core-edge-example-router-upstream-upstream";
            attach = {
              bridge = "br-edge-nebula-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-edge-example-router-nebula-core-edge-example-router-upstream";
          };
        };
      };
      esp-edge-example-router-policy = {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp";
          name = "edge-example-router-policy";
          site = "edge";
        };
        platform = "home-container";
        ports = {
          downstream-client = {
            adapterName = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-client-downstream-client";
            attach = {
              bridge = "br-edge-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "down-client";
            };
            link = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-client";
          };
          downstream-dmz = {
            adapterName = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-dmz-downstream-dmz";
            attach = {
              bridge = "br-edge-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "downstream-dmz";
            };
            link = "p2p-edge-example-router-downstream-edge-example-router-policy--access-edge-example-router-access-dmz";
          };
          upstream-client-wan = {
            adapterName = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-client--uplink-wan-upstream-client-wan";
            attach = {
              bridge = "br-edge-policy-upstream-access-client-wan";
              kind = "bridge";
            };
            interface = {
              name = "up-client-wan";
            };
            link = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-client--uplink-wan";
          };
          upstream-dmz-wan = {
            adapterName = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-wan-upstream-dmz-wan";
            attach = {
              bridge = "br-edge-policy-upstream-access-dmz-wan";
              kind = "bridge";
            };
            interface = {
              name = "up-dmz-wan";
            };
            link = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-wan";
          };
          upstream-dmz-east-west = {
            adapterName = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-east-west-upstream-dmz-east-west";
            attach = {
              bridge = "br-edge-policy-upstream-access-dmz-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-dmz-ew";
            };
            link = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-east-west";
          };
        };
      };
      esp-edge-example-router-upstream = {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp";
          name = "edge-example-router-upstream";
          site = "edge";
        };
        platform = "home-container";
        ports = {
          core = {
            adapterName = "p2p-edge-example-router-core-edge-example-router-upstream-core";
            attach = {
              bridge = "br-edge-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core";
            };
            link = "p2p-edge-example-router-core-edge-example-router-upstream";
          };
          core-nebula = {
            adapterName = "p2p-edge-example-router-nebula-core-edge-example-router-upstream-core-nebula";
            attach = {
              bridge = "br-edge-nebula-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-nebula";
            };
            link = "p2p-edge-example-router-nebula-core-edge-example-router-upstream";
          };
          policy-client-wan = {
            adapterName = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-client--uplink-wan-policy-client-wan";
            attach = {
              bridge = "br-edge-policy-upstream-access-client-wan";
              kind = "bridge";
            };
            interface = {
              name = "pol-client-wan";
            };
            link = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-client--uplink-wan";
          };
          policy-dmz-wan = {
            adapterName = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-wan-policy-dmz-wan";
            attach = {
              bridge = "br-edge-policy-upstream-access-dmz-wan";
              kind = "bridge";
            };
            interface = {
              name = "policy-dmz-wan";
            };
            link = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-wan";
          };
          policy-dmz-east-west = {
            adapterName = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-east-west-policy-dmz-east-west";
            attach = {
              bridge = "br-edge-policy-upstream-access-dmz-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-dmz-ew";
            };
            link = "p2p-edge-example-router-policy-edge-example-router-upstream--access-edge-example-router-access-dmz--uplink-east-west";
          };
        };
      };
    } // clabAccessNodes // {
      esp-lab-example-router-core-nebula = withDeniedResolverCidrs {
        host = "s-router-lab";
        logicalNode = {
          enterprise = "esp";
          name = "lab-example-router-core-nebula";
          site = "lab";
        };
        platform = "home-container";
        ports = {
          tenant-client = {
            attach = {
              bridge = "client";
              kind = "bridge";
            };
            interface = {
              name = "client";
            };
            logicalInterface = "tenant-client";
          };
          upstream = {
            adapterName = "p2p-lab-example-router-core-nebula-lab-example-router-upstream-upstream";
            attach = {
              bridge = "br-lab-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-lab-example-router-core-nebula-lab-example-router-upstream";
          };
        };
      };
      esp-lab-example-router-core-simulated-isp = withDeniedResolverCidrs {
        host = "s-router-lab";
        logicalNode = {
          enterprise = "esp";
          name = "lab-example-router-core-simulated-isp";
          site = "lab";
        };
        platform = "home-container";
        ports = {
          upstream = {
            adapterName = "p2p-lab-example-router-core-simulated-isp-lab-example-router-upstream-upstream";
            attach = {
              bridge = "br-lab-core-simulated-isp-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-lab-example-router-core-simulated-isp-lab-example-router-upstream";
          };
          wan = {
            attach = {
              bridge = "br-uplink1";
              kind = "bridge";
            };
            external = true;
            interface = {
              name = "wan";
            };
            uplink = "wan";
          };
        };
      };
      esp-lab-example-router-downstream = {
        host = "s-router-lab";
        logicalNode = {
          enterprise = "esp";
          name = "lab-example-router-downstream";
          site = "lab";
        };
        platform = "home-container";
        ports = clabDownstreamAccessPorts // clabDownstreamPolicyPorts;
      };
      esp-lab-example-router-policy = {
        host = "s-router-lab";
        logicalNode = {
          enterprise = "esp";
          name = "lab-example-router-policy";
          site = "lab";
        };
        platform = "home-container";
        ports = clabPolicyDownstreamPorts // clabPolicyWanPorts // clabPolicyEastWestPorts;
      };
      esp-lab-example-router-upstream = {
        host = "s-router-lab";
        logicalNode = {
          enterprise = "esp";
          name = "lab-example-router-upstream";
          site = "lab";
        };
        platform = "home-container";
        ports = {
          core-simulated-isp = {
            adapterName = "p2p-lab-example-router-core-simulated-isp-lab-example-router-upstream-core-simulated-isp";
            attach = {
              bridge = "br-lab-core-simulated-isp-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-isp";
            };
            link = "p2p-lab-example-router-core-simulated-isp-lab-example-router-upstream";
          };
          core-nebula = {
            adapterName = "p2p-lab-example-router-core-nebula-lab-example-router-upstream-core-nebula";
            attach = {
              bridge = "br-lab-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-nebula";
            };
            link = "p2p-lab-example-router-core-nebula-lab-example-router-upstream";
          };
        } // clabUpstreamWanPorts // clabUpstreamEastWestPorts;
      };
    };
  };
}
