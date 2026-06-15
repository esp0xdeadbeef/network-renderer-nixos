let
  publicResolverCidrs = [
    "1.1.1.1/32"
    "9.9.9.9/32"
    "2606:4700:4700::1111/128"
    "2620:fe::fe/128"
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
in
{
  controlPlane = {
    sites = {
      esp0xdeadbeef = {
        site-a = {
          overlays = {
            east-west = {
              nodes = {
                c-router-lighthouse = {
                  addr4 = "100.96.10.254/32";
                  addr6 = "fd42:dead:beef:ee::254/128";
                };
                s-router-core-nebula = {
                  addr4 = "100.96.10.1/32";
                  addr6 = "fd42:dead:beef:ee::1/128";
                };
              };
              nebula = {
                lighthouse = {
                  endpoint = "198.51.100.10";
                  endpointSourceFile = "/run/secrets/site-c-lighthouse-public-ipv4";
                  endpoint6 = "2001:db8:51::10";
                  endpoint6SourceFile = "/run/secrets/site-c-lighthouse-public-ipv6";
                  node = "c-router-lighthouse";
                  port = 4242;
                };
                role = "core-client";
                runtimeNodes = {
                  s-router-core-nebula = {
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
                ipv4 = [ "/run/secrets/site-c-lighthouse-public-ipv4" "/run/secrets/hetzner-public-ipv4" ];
                ipv6 = [ "/run/secrets/site-c-lighthouse-public-ipv6" ];
              };
              runtimeNodes = {
                s-router-core-nebula = {
                  container = {
                    profile = "core-router-nebula";
                    targetContainer = "s-router-core-nebula";
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
                    relays = [ "c-router-nebula-core" ];
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
        };
        site-c = {
          overlays = {
            east-west = {
              nodes = {
                c-router-lighthouse = {
                  addr4 = "100.96.10.254/32";
                  addr6 = "fd42:dead:beef:ee::254/128";
                };
                c-router-nebula-core = {
                  addr4 = "100.96.10.3/32";
                  addr6 = "fd42:dead:beef:ee::3/128";
                };
              };
              nebula = {
                lighthouse = {
                  endpoint = "198.51.100.10";
                  endpointSourceFile = "/run/secrets/site-c-lighthouse-public-ipv4";
                  endpoint6 = "2001:db8:51::10";
                  endpoint6SourceFile = "/run/secrets/site-c-lighthouse-public-ipv6";
                  node = "c-router-lighthouse";
                  port = 4242;
                };
                role = "core-client";
                runtimeNodes = {
                  c-router-lighthouse = {
                    unsafeRoutes = [ ];
                  };
                  c-router-nebula-core = {
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
                        routeSourceFile = "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile";
                      }
                    ];
                  };
                };
              };
              provider = "nebula";
              underlayEndpointSourceFiles = {
                ipv4 = [ "/run/secrets/site-c-lighthouse-public-ipv4" "/run/secrets/hetzner-public-ipv4" ];
                ipv6 = [ "/run/secrets/site-c-lighthouse-public-ipv6" ];
              };
              runtimeNodes = {
                c-router-lighthouse = {
                  container = {
                    hostBridge = "dmz";
                    profile = "core-client";
                  };
                  groups = [
                    "lab"
                    "site-c"
                    "lighthouse"
                  ];
                  service = {
                    interface = "nebula1";
                    name = "nebula-runtime";
                  };
                };
                c-router-nebula-core = {
                  container = {
                    profile = "core-router-nebula";
                    targetContainer = "c-router-nebula-core";
                  };
                  groups = [
                    "lab"
                    "site-c"
                    "core"
                  ];
                  service = {
                    interface = "nebula1";
                    name = "nebula-runtime";
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
      };
      espbranch = {
        site-b = {
          overlays = {
            east-west = {
              nodes = {
                b-router-core-nebula = {
                  addr4 = "100.96.10.2/32";
                  addr6 = "fd42:dead:beef:ee::2/128";
                };
                branch-node01 = {
                  addr4 = "100.96.10.20/32";
                  addr6 = "fd42:dead:beef:ee::20/128";
                };
                c-router-lighthouse = {
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
                  endpointSourceFile = "/run/secrets/site-c-lighthouse-public-ipv4";
                  endpoint6 = "2001:db8:51::10";
                  endpoint6SourceFile = "/run/secrets/site-c-lighthouse-public-ipv6";
                  node = "c-router-lighthouse";
                  port = 4242;
                };
                role = "core-client";
                runtimeNodes = {
                  b-router-core-nebula = {
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
                ipv4 = [ "/run/secrets/site-c-lighthouse-public-ipv4" "/run/secrets/hetzner-public-ipv4" ];
                ipv6 = [ "/run/secrets/site-c-lighthouse-public-ipv6" ];
              };
              runtimeNodes = {
                b-router-core-nebula = {
                  container = {
                    profile = "core-router-nebula";
                    targetContainer = "b-router-core-nebula";
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
                    relays = [ "c-router-nebula-core" ];
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
            branch = {
              ipv6 = {
                mode = "static";
                prefixes = [ "fd42:dead:feed:10::/64" ];
              };
            };
            hostile = {
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
          br-site-c-core-upstream = { };
          br-site-c-downstream-client = { };
          br-site-c-downstream-dmz = { };
          br-site-c-downstream-policy-access-client = { };
          br-site-c-downstream-policy-access-dmz = { };
          br-site-c-nebula-core-upstream = { };
          br-site-c-policy-upstream-access-client-east-west = { };
          br-site-c-policy-upstream-access-client-wan = { };
          br-site-c-policy-upstream-access-dmz-east-west = { };
          br-site-c-policy-upstream-access-dmz-wan = { };
          client = { };
          dmz = { };
        };
        uplinks = {
          wan = {
            bridge = "br-wan";
            hostAddresses = [ "172.31.254.1/24" ];
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
          br-site-a-core-isp-a-upstream = { };
          br-site-a-core-isp-b-upstream = { };
          br-site-a-core-nebula-upstream = { };
          br-site-a-downstream-admin = { };
          br-site-a-downstream-client = { };
          br-site-a-downstream-client2 = { };
          br-site-a-downstream-dmz = { };
          br-site-a-downstream-mgmt = { };
          br-site-a-downstream-policy-access-admin = { };
          br-site-a-downstream-policy-access-client = { };
          br-site-a-downstream-policy-access-client2 = { };
          br-site-a-downstream-policy-access-dmz = { };
          br-site-a-downstream-policy-access-mgmt = { };
          br-site-a-downstream-policy-access-streaming = { };
          br-site-a-downstream-streaming = { };
          br-site-a-policy-upstream-access-admin-east-west = { };
          br-site-a-policy-upstream-access-admin-isp-a = { };
          br-site-a-policy-upstream-access-admin-isp-b = { };
          br-site-a-policy-upstream-access-client-east-west = { };
          br-site-a-policy-upstream-access-client-isp-a = { };
          br-site-a-policy-upstream-access-client-isp-b = { };
          br-site-a-policy-upstream-access-client2-east-west = { };
          br-site-a-policy-upstream-access-client2-isp-a = { };
          br-site-a-policy-upstream-access-client2-isp-b = { };
          br-site-a-policy-upstream-access-mgmt-east-west = { };
          br-site-a-policy-upstream-access-mgmt-isp-a = { };
          br-site-a-policy-upstream-access-mgmt-isp-b = { };
          br-site-a-policy-upstream-access-streaming-isp-a = { };
          br-site-a-policy-upstream-access-streaming-isp-b = { };
          br-site-b-core-nebula-upstream = { };
          br-site-b-core-simulated-isp-upstream = { };
          br-site-b-downstream-branch = { };
          br-site-b-downstream-hostile = { };
          br-site-b-downstream-policy-access-branch = { };
          br-site-b-downstream-policy-access-hostile = { };
          br-site-b-policy-upstream-access-branch = { };
          br-site-b-policy-upstream-access-branch-east-west = { };
          br-site-b-policy-upstream-access-hostile = { };
          br-site-b-policy-upstream-access-hostile-east-west = { };
          br-site-c-core-upstream = { };
          br-site-c-downstream-mgmt = { };
          br-site-c-downstream-policy-access-mgmt = { };
          br-site-c-nebula-core-upstream = { };
          br-site-c-policy-upstream-access-mgmt-wan = { };
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
          client2 = {
            mode = "vlan";
            parent = "eth0";
            vlan = 303;
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
          client2 = {
            mode = "vlan";
            parent = "eth0";
            vlan = 303;
          };
          dmz = {
            mode = "vlan";
            parent = "eth0";
            vlan = 304;
          };
          home-users = {
            mode = "vlan";
            parent = "eth0";
            vlan = 359;
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
          nas = {
            mode = "vlan";
            parent = "eth0";
            vlan = 361;
          };
          printer = {
            mode = "vlan";
            parent = "eth0";
            vlan = 360;
          };
          site-c-mgmt = {
            mode = "vlan";
            parent = "eth0";
            vlan = 358;
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
    c-router-lighthouse = {
      ipv4 = [ "10.90.10.100" ];
      ipv6 = [ "fd42:dead:cafe:10::100" ];
    };
    nebula01 = {
      ipv4 = [ "10.20.30.10" ];
      ipv6 = [ "fd42:dead:beef:30::10" ];
    };
    site-dns-mgmt = {
      ipv4 = [ "10.20.10.1" ];
      ipv6 = [ "fd42:dead:beef:10::1" ];
    };
    sitec-dns-dmz = {
      ipv4 = [ "10.90.10.1" ];
      ipv6 = [ "fd42:dead:cafe:10::1" ];
    };
  };
  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-access-admin = {
        advertisements = {
          dhcp4 = {
            tenant-admin = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "admin";
              interface = "tenant-admin";
              router = "10.20.15.1";
              subnet = "10.20.15.0/24";
            };
          };
          ipv6Ra = {
            tenant-admin = {
              dnssl = [ "lan." ];
              interface = "tenant-admin";
              prefixes = [ "fd42:dead:beef:15::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-admin";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          tenant-admin = {
            attach = {
              bridge = "admin";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.20.15.1/24";
              addr6 = "fd42:dead:beef:15::1/64";
              name = "tenant-admin";
            };
            logicalInterface = "tenant-admin";
          };
          transit-downstream-selector = {
            adapterName = "p2p-s-router-access-admin-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-admin";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
          };
        };
        services = {
          dns = {
            allowFrom = [
              "10.20.15.0/24"
              "fd42:dead:beef:15::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.20.15.1"
              "fd42:dead:beef:15::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-client = {
        advertisements = {
          dhcp4 = {
            tenant-client = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "client";
              interface = "tenant-client";
              router = "10.20.20.1";
              subnet = "10.20.20.0/24";
            };
          };
          ipv6Ra = {
            tenant-client = {
              dnssl = [ "lan." ];
              interface = "tenant-client";
              prefixes = [ "fd42:dead:beef:20::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-client";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          tenant-client = {
            attach = {
              bridge = "client";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.20.20.1/24";
              addr6 = "fd42:dead:beef:20::1/64";
              name = "tenant-client";
            };
            logicalInterface = "tenant-client";
          };
          transit-downstream-selector = {
            adapterName = "p2p-s-router-access-client-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-s-router-access-client-s-router-downstream-selector";
          };
        };
        services = {
          dns = {
            allowFrom = [
              "10.20.20.0/24"
              "fd42:dead:beef:20::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.20.20.1"
              "fd42:dead:beef:20::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-client2 = {
        advertisements = {
          dhcp4 = {
            tenant-client2 = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "client2";
              interface = "tenant-client2";
              router = "10.20.40.1";
              subnet = "10.20.40.0/24";
            };
          };
          ipv6Ra = {
            tenant-client2 = {
              dnssl = [ "lan." ];
              interface = "tenant-client2";
              prefixes = [ "fd42:dead:beef:40::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-client2";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          tenant-client2 = {
            attach = {
              bridge = "client2";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.20.40.1/24";
              addr6 = "fd42:dead:beef:40::1/64";
              name = "tenant-client2";
            };
            logicalInterface = "tenant-client2";
          };
          transit-downstream-selector = {
            adapterName = "p2p-s-router-access-client2-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-client2";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-s-router-access-client2-s-router-downstream-selector";
          };
        };
        services = {
          dns = {
            allowFrom = [
              "10.20.40.0/24"
              "fd42:dead:beef:40::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.20.40.1"
              "fd42:dead:beef:40::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-dmz = {
        advertisements = {
          dhcp4 = {
            tenant-dmz = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "dmz";
              interface = "tenant-dmz";
              router = "10.20.30.1";
              subnet = "10.20.30.0/24";
            };
          };
          ipv6Ra = {
            tenant-dmz = {
              dnssl = [ "lan." ];
              interface = "tenant-dmz";
              prefixes = [ "fd42:dead:beef:30::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-dmz";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          tenant-dmz = {
            attach = {
              bridge = "dmz";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.20.30.1/24";
              addr6 = "fd42:dead:beef:30::1/64";
              name = "tenant-dmz";
            };
            logicalInterface = "tenant-dmz";
          };
          transit-downstream-selector = {
            adapterName = "p2p-s-router-access-dmz-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-s-router-access-dmz-s-router-downstream-selector";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
            allowFrom = [
              "10.20.30.0/24"
              "fd42:dead:beef:30::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.20.30.1"
              "fd42:dead:beef:30::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-mgmt = {
        advertisements = {
          dhcp4 = {
            tenant-mgmt = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "mgmt";
              interface = "tenant-mgmt";
              router = "10.20.10.1";
              subnet = "10.20.10.0/24";
            };
          };
          ipv6Ra = {
            tenant-mgmt = {
              dnssl = [ "lan." ];
              interface = "tenant-mgmt";
              prefixes = [ "fd42:dead:beef:10::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-mgmt";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          tenant-mgmt = {
            attach = {
              bridge = "mgmt";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.20.10.1/24";
              addr6 = "fd42:dead:beef:10::1/64";
              name = "tenant-mgmt";
            };
            logicalInterface = "tenant-mgmt";
          };
          transit-downstream-selector = {
            adapterName = "p2p-s-router-access-mgmt-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
          };
        };
        services = {
          dns = {
            allowFrom = [
              "10.20.10.0/24"
              "fd42:dead:beef:10::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.20.10.1"
              "fd42:dead:beef:10::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-streaming = {
        advertisements = {
          dhcp4 = {
            tenant-streaming = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "streaming";
              interface = "tenant-stream";
              router = "10.20.50.1";
              subnet = "10.20.50.0/24";
            };
          };
          ipv6Ra = {
            tenant-streaming = {
              dnssl = [ "lan." ];
              interface = "tenant-stream";
              prefixes = [ "fd42:dead:beef:50::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-streaming";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          tenant-streaming = {
            attach = {
              bridge = "streaming";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.20.50.1/24";
              addr6 = "fd42:dead:beef:50::1/64";
              name = "tenant-stream";
            };
            logicalInterface = "tenant-streaming";
          };
          transit-downstream-selector = {
            adapterName = "p2p-s-router-access-streaming-s-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-streaming";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-s-router-access-streaming-s-router-downstream-selector";
          };
        };
        services = {
          dns = {
            allowFrom = [
              "10.20.50.0/24"
              "fd42:dead:beef:50::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.20.50.1"
              "fd42:dead:beef:50::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-core-isp-a = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-core-isp-a";
          site = "site-a";
        };
        platform = "nixos-container";
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
          upstream-selector = {
            adapterName = "p2p-s-router-core-isp-a-s-router-upstream-selector-upstream-selector";
            attach = {
              bridge = "br-site-a-core-isp-a-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-s-router-core-isp-a-s-router-upstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-core-isp-b = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-core-isp-b";
          site = "site-a";
        };
        platform = "nixos-container";
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
          upstream-selector = {
            adapterName = "p2p-s-router-core-isp-b-s-router-upstream-selector-upstream-selector";
            attach = {
              bridge = "br-site-a-core-isp-b-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-s-router-core-isp-b-s-router-upstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-core-nebula = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-core-nebula";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          upstream-selector = {
            adapterName = "p2p-s-router-core-nebula-s-router-upstream-selector-upstream-selector";
            attach = {
              bridge = "br-site-a-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-s-router-core-nebula-s-router-upstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-downstream-selector = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-downstream-selector";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          access-admin = {
            adapterName = "p2p-s-router-access-admin-s-router-downstream-selector-access-admin";
            attach = {
              bridge = "br-site-a-downstream-admin";
              kind = "bridge";
            };
            interface = {
              name = "access-admin";
            };
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
          };
          access-client = {
            adapterName = "p2p-s-router-access-client-s-router-downstream-selector-access-client";
            attach = {
              bridge = "br-site-a-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "access-client";
            };
            link = "p2p-s-router-access-client-s-router-downstream-selector";
          };
          access-client2 = {
            adapterName = "p2p-s-router-access-client2-s-router-downstream-selector-access-client2";
            attach = {
              bridge = "br-site-a-downstream-client2";
              kind = "bridge";
            };
            interface = {
              name = "access-client2";
            };
            link = "p2p-s-router-access-client2-s-router-downstream-selector";
          };
          access-dmz = {
            adapterName = "p2p-s-router-access-dmz-s-router-downstream-selector-access-dmz";
            attach = {
              bridge = "br-site-a-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "access-dmz";
            };
            link = "p2p-s-router-access-dmz-s-router-downstream-selector";
          };
          access-mgmt = {
            adapterName = "p2p-s-router-access-mgmt-s-router-downstream-selector-access-mgmt";
            attach = {
              bridge = "br-site-a-downstream-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "access-mgmt";
            };
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
          };
          access-streaming = {
            adapterName = "p2p-s-router-access-streaming-s-router-downstream-selector-access-streaming";
            attach = {
              bridge = "br-site-a-downstream-streaming";
              kind = "bridge";
            };
            interface = {
              name = "access-stream";
            };
            link = "p2p-s-router-access-streaming-s-router-downstream-selector";
          };
          policy-admin = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin-policy-admin";
            attach = {
              bridge = "br-site-a-downstream-policy-access-admin";
              kind = "bridge";
            };
            interface = {
              name = "policy-admin";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin";
          };
          policy-client = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client-policy-client";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "policy-client";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
          };
          policy-client2 = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2-policy-client2";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client2";
              kind = "bridge";
            };
            interface = {
              name = "policy-client2";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2";
          };
          policy-dmz = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz-policy-dmz";
            attach = {
              bridge = "br-site-a-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "policy-dmz";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz";
          };
          policy-mgmt = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt-policy-mgmt";
            attach = {
              bridge = "br-site-a-downstream-policy-access-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "policy-mgmt";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt";
          };
          policy-streaming = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-streaming-policy-streaming";
            attach = {
              bridge = "br-site-a-downstream-policy-access-streaming";
              kind = "bridge";
            };
            interface = {
              name = "policy-stream";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-streaming";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-policy = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-policy-only";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          downstream-admin = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin-downstream-admin";
            attach = {
              bridge = "br-site-a-downstream-policy-access-admin";
              kind = "bridge";
            };
            interface = {
              name = "down-admin";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin";
          };
          downstream-client = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client-downstream-client";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "down-client";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
          };
          downstream-client2 = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2-downstream-client2";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client2";
              kind = "bridge";
            };
            interface = {
              name = "down-client2";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2";
          };
          downstream-dmz = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz-downstream-dmz";
            attach = {
              bridge = "br-site-a-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "downstream-dmz";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz";
          };
          downstream-mgmt = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt-downstream-mgmt";
            attach = {
              bridge = "br-site-a-downstream-policy-access-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "downstream-mgmt";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt";
          };
          downstream-streaming = {
            adapterName = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-streaming-downstream-streaming";
            attach = {
              bridge = "br-site-a-downstream-policy-access-streaming";
              kind = "bridge";
            };
            interface = {
              name = "downstr-stream";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-streaming";
          };
          upstream-admin-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west-upstream-admin-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-adm-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west";
          };
          upstream-admin-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a-upstream-admin-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-admin-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a";
          };
          upstream-admin-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b-upstream-admin-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-admin-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b";
          };
          upstream-client-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west-upstream-client-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-cli-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
          };
          upstream-client-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a-upstream-client-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-client-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a";
          };
          upstream-client-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b-upstream-client-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-client-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b";
          };
          upstream-client2-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west-upstream-client2-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client2-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-cl2-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west";
          };
          upstream-client2-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a-upstream-client2-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client2-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-cl2-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a";
          };
          upstream-client2-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b-upstream-client2-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client2-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-cl2-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b";
          };
          upstream-mgmt-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west-upstream-mgmt-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-mgt-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west";
          };
          upstream-mgmt-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a-upstream-mgmt-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-mgmt-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a";
          };
          upstream-mgmt-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b-upstream-mgmt-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-mgmt-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b";
          };
          upstream-streaming-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-a-upstream-streaming-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-streaming-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "up-stream-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-a";
          };
          upstream-streaming-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-b-upstream-streaming-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-streaming-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "up-stream-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-b";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-upstream-selector = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-upstream-selector";
          site = "site-a";
        };
        platform = "nixos-container";
        ports = {
          core-isp-a = {
            adapterName = "p2p-s-router-core-isp-a-s-router-upstream-selector-core-isp-a";
            attach = {
              bridge = "br-site-a-core-isp-a-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-a";
            };
            link = "p2p-s-router-core-isp-a-s-router-upstream-selector";
          };
          core-isp-b = {
            adapterName = "p2p-s-router-core-isp-b-s-router-upstream-selector-core-isp-b";
            attach = {
              bridge = "br-site-a-core-isp-b-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-b";
            };
            link = "p2p-s-router-core-isp-b-s-router-upstream-selector";
          };
          core-nebula = {
            adapterName = "p2p-s-router-core-nebula-s-router-upstream-selector-core-nebula";
            attach = {
              bridge = "br-site-a-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-nebula";
            };
            link = "p2p-s-router-core-nebula-s-router-upstream-selector";
          };
          policy-admin-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west-policy-admin-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-adm-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west";
          };
          policy-admin-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a-policy-admin-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-admin-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-a";
          };
          policy-admin-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b-policy-admin-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-admin-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-isp-b";
          };
          policy-client-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west-policy-client-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-cli-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
          };
          policy-client-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a-policy-client-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-client-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a";
          };
          policy-client-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b-policy-client-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-client-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b";
          };
          policy-client2-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west-policy-client2-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client2-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-cl2-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west";
          };
          policy-client2-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a-policy-client2-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client2-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-cl2-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a";
          };
          policy-client2-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b-policy-client2-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client2-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-cl2-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b";
          };
          policy-mgmt-east-west = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west-policy-mgmt-east-west";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-mgt-ew";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west";
          };
          policy-mgmt-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a-policy-mgmt-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-mgmt-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-a";
          };
          policy-mgmt-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b-policy-mgmt-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-mgmt-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-isp-b";
          };
          policy-streaming-isp-a = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-a-policy-streaming-isp-a";
            attach = {
              bridge = "br-site-a-policy-upstream-access-streaming-isp-a";
              kind = "bridge";
            };
            interface = {
              name = "pol-stream-a";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-a";
          };
          policy-streaming-isp-b = {
            adapterName = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-b-policy-streaming-isp-b";
            attach = {
              bridge = "br-site-a-policy-upstream-access-streaming-isp-b";
              kind = "bridge";
            };
            interface = {
              name = "pol-stream-b";
            };
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-streaming--uplink-isp-b";
          };
        };
      };
      esp0xdeadbeef-site-c-c-router-access-client = {
        advertisements = {
          dhcp4 = {
            tenant-client = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "client";
              interface = "tenant-client";
              router = "10.90.20.1";
              subnet = "10.90.20.0/24";
            };
          };
          ipv6Ra = {
            tenant-client = {
              dnssl = [ "lan." ];
              interface = "tenant-client";
              prefixes = [ "fd42:dead:cafe:20::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "c-router-access-client";
          site = "site-c";
        };
        platform = "nixos-container";
        ports = {
          tenant-client = {
            attach = {
              bridge = "client";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.90.20.1/24";
              addr6 = "fd42:dead:cafe:20::1/64";
              name = "tenant-client";
            };
            logicalInterface = "tenant-client";
          };
          transit-downstream-selector = {
            adapterName = "p2p-c-router-access-client-c-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-c-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-c-router-access-client-c-router-downstream-selector";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
            allowFrom = [
              "10.90.20.0/24"
              "fd42:dead:cafe:20::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.90.20.1"
              "fd42:dead:cafe:20::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-c-c-router-access-dmz = {
        advertisements = {
          dhcp4 = {
            tenant-dmz = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "dmz";
              interface = "tenant-dmz";
              router = "10.90.10.1";
              subnet = "10.90.10.0/24";
            };
          };
          ipv6Ra = {
            tenant-dmz = {
              dnssl = [ "lan." ];
              interface = "tenant-dmz";
              prefixes = [ "fd42:dead:cafe:10::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "c-router-access-dmz";
          site = "site-c";
        };
        platform = "nixos-container";
        ports = {
          tenant-dmz = {
            attach = {
              bridge = "dmz";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.90.10.1/24";
              addr6 = "fd42:dead:cafe:10::1/64";
              name = "tenant-dmz";
            };
            logicalInterface = "tenant-dmz";
          };
          transit-downstream-selector = {
            adapterName = "p2p-c-router-access-dmz-c-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-c-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-c-router-access-dmz-c-router-downstream-selector";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
            allowFrom = [
              "10.90.10.0/24"
              "fd42:dead:cafe:10::/64"
            ];
            forwarders = [
              "1.1.1.1"
              "9.9.9.9"
              "2606:4700:4700::1111"
              "2620:fe::fe"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.90.10.1"
              "fd42:dead:cafe:10::1"
            ];
          };
        };
      };
      esp0xdeadbeef-site-c-c-router-core = withDeniedResolverCidrs {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "c-router-core";
          site = "site-c";
        };
        platform = "nixos-container";
        ports = {
          upstream-selector = {
            adapterName = "p2p-c-router-core-c-router-upstream-selector-upstream-selector";
            attach = {
              bridge = "br-site-c-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-c-router-core-c-router-upstream-selector";
          };
          wan = {
            attach = {
              bridge = "br-wan";
              kind = "bridge";
            };
            external = true;
            interface = {
              addr4 = "172.31.254.3/24";
              name = "wan";
              routes = {
                ipv4 = [
                  {
                    prefix = "0.0.0.0/0";
                    via = "172.31.254.1";
                  }
                ];
              };
            };
            uplink = "wan";
          };
        };
      };
      esp0xdeadbeef-site-c-c-router-downstream-selector = {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "c-router-downstream-selector";
          site = "site-c";
        };
        platform = "nixos-container";
        ports = {
          access-client = {
            adapterName = "p2p-c-router-access-client-c-router-downstream-selector-access-client";
            attach = {
              bridge = "br-site-c-downstream-client";
              kind = "bridge";
            };
            interface = {
              name = "access-client";
            };
            link = "p2p-c-router-access-client-c-router-downstream-selector";
          };
          access-dmz = {
            adapterName = "p2p-c-router-access-dmz-c-router-downstream-selector-access-dmz";
            attach = {
              bridge = "br-site-c-downstream-dmz";
              kind = "bridge";
            };
            interface = {
              name = "access-dmz";
            };
            link = "p2p-c-router-access-dmz-c-router-downstream-selector";
          };
          policy-client = {
            adapterName = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-client-policy-client";
            attach = {
              bridge = "br-site-c-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "policy-client";
            };
            link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-client";
          };
          policy-dmz = {
            adapterName = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-dmz-policy-dmz";
            attach = {
              bridge = "br-site-c-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "policy-dmz";
            };
            link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-dmz";
          };
        };
      };
      esp0xdeadbeef-site-c-c-router-nebula-core = withDeniedResolverCidrs {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "c-router-nebula-core";
          site = "site-c";
        };
        platform = "nixos-container";
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
          upstream-selector = {
            adapterName = "p2p-c-router-nebula-core-c-router-upstream-selector-upstream-selector";
            attach = {
              bridge = "br-site-c-nebula-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-c-router-nebula-core-c-router-upstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-c-c-router-policy = {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "c-router-policy";
          site = "site-c";
        };
        platform = "nixos-container";
        ports = {
          downstream-client = {
            adapterName = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-client-downstream-client";
            attach = {
              bridge = "br-site-c-downstream-policy-access-client";
              kind = "bridge";
            };
            interface = {
              name = "down-client";
            };
            link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-client";
          };
          downstream-dmz = {
            adapterName = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-dmz-downstream-dmz";
            attach = {
              bridge = "br-site-c-downstream-policy-access-dmz";
              kind = "bridge";
            };
            interface = {
              name = "downstream-dmz";
            };
            link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-dmz";
          };
          upstream-client-east-west = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-east-west-upstream-client-east-west";
            attach = {
              bridge = "br-site-c-policy-upstream-access-client-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-client-ew";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-east-west";
          };
          upstream-client-wan = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-wan-upstream-client-wan";
            attach = {
              bridge = "br-site-c-policy-upstream-access-client-wan";
              kind = "bridge";
            };
            interface = {
              name = "up-client-wan";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-wan";
          };
          upstream-dmz-east-west = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-east-west-upstream-dmz-east-west";
            attach = {
              bridge = "br-site-c-policy-upstream-access-dmz-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-dmz-ew";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-east-west";
          };
          upstream-dmz-wan = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-wan-upstream-dmz-wan";
            attach = {
              bridge = "br-site-c-policy-upstream-access-dmz-wan";
              kind = "bridge";
            };
            interface = {
              name = "up-dmz-wan";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-wan";
          };
        };
      };
      esp0xdeadbeef-site-c-c-router-upstream-selector = {
        host = "s-router-hetzner-anywhere";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "c-router-upstream-selector";
          site = "site-c";
        };
        platform = "nixos-container";
        ports = {
          core = {
            adapterName = "p2p-c-router-core-c-router-upstream-selector-core";
            attach = {
              bridge = "br-site-c-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core";
            };
            link = "p2p-c-router-core-c-router-upstream-selector";
          };
          core-nebula = {
            adapterName = "p2p-c-router-nebula-core-c-router-upstream-selector-core-nebula";
            attach = {
              bridge = "br-site-c-nebula-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-nebula";
            };
            link = "p2p-c-router-nebula-core-c-router-upstream-selector";
          };
          policy-client-east-west = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-east-west-policy-client-east-west";
            attach = {
              bridge = "br-site-c-policy-upstream-access-client-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-client-ew";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-east-west";
          };
          policy-client-wan = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-wan-policy-client-wan";
            attach = {
              bridge = "br-site-c-policy-upstream-access-client-wan";
              kind = "bridge";
            };
            interface = {
              name = "pol-client-wan";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-wan";
          };
          policy-dmz-east-west = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-east-west-policy-dmz-east-west";
            attach = {
              bridge = "br-site-c-policy-upstream-access-dmz-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-dmz-ew";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-east-west";
          };
          policy-dmz-wan = {
            adapterName = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-wan-policy-dmz-wan";
            attach = {
              bridge = "br-site-c-policy-upstream-access-dmz-wan";
              kind = "bridge";
            };
            interface = {
              name = "policy-dmz-wan";
            };
            link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-wan";
          };
        };
      };
      espbranch-site-b-b-router-access-branch = {
        advertisements = {
          dhcp4 = {
            tenant-branch = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "branch";
              interface = "tenant-branch";
              router = "10.60.10.1";
              subnet = "10.60.10.0/24";
            };
          };
          ipv6Ra = {
            tenant-branch = {
              dnssl = [ "lan." ];
              interface = "tenant-branch";
              prefixes = [ "fd42:dead:feed:10::/64" ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "espbranch";
          name = "b-router-access-branch";
          site = "site-b";
        };
        platform = "nixos-container";
        ports = {
          tenant-branch = {
            attach = {
              bridge = "branch";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.60.10.1/24";
              addr6 = "fd42:dead:feed:10::1/64";
              name = "tenant-branch";
            };
            logicalInterface = "tenant-branch";
          };
          transit-downstream-selector = {
            adapterName = "p2p-b-router-access-branch-b-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-b-downstream-branch";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-b-router-access-branch-b-router-downstream-selector";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
            allowFrom = [
              "10.60.10.0/24"
              "fd42:dead:feed:10::/64"
            ];
            forwarders = [
              "10.20.10.1"
              "fd42:dead:beef:10::1"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.60.10.1"
              "fd42:dead:feed:10::1"
            ];
          };
        };
      };
      espbranch-site-b-b-router-access-hostile = {
        advertisements = {
          dhcp4 = {
            tenant-hostile = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
              id = "hostile";
              interface = "tenant-hostile";
              router = "10.70.10.1";
              subnet = "10.70.10.0/24";
            };
          };
          ipv6Ra = {
            tenant-hostile = {
              dnssl = [ "lan." ];
              interface = "tenant-hostile";
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "s-router-test";
        logicalNode = {
          enterprise = "espbranch";
          name = "b-router-access-hostile";
          site = "site-b";
        };
        platform = "nixos-container";
        ports = {
          tenant-hostile = {
            attach = {
              bridge = "hostile";
              kind = "bridge";
            };
            interface = {
              addr4 = "10.70.10.1/24";
              addr6 = "fd42:dead:feed:70::1/64";
              name = "tenant-hostile";
            };
            logicalInterface = "tenant-hostile";
          };
          transit-downstream-selector = {
            adapterName = "p2p-b-router-access-hostile-b-router-downstream-selector-transit-downstream-selector";
            attach = {
              bridge = "br-site-b-downstream-hostile";
              kind = "bridge";
            };
            interface = {
              name = "transit";
            };
            link = "p2p-b-router-access-hostile-b-router-downstream-selector";
          };
        };
        services = {
          dns = {
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
            allowFrom = [
              "10.70.10.0/24"
              "fd42:dead:feed:70::/64"
            ];
            forwarders = [
              "10.20.10.1"
              "fd42:dead:beef:10::1"
            ];
            deniedResolverCidrs = publicResolverCidrs;
            listen = [
              "10.70.10.1"
              "fd42:dead:feed:70::1"
            ];
          };
        };
      };
      espbranch-site-b-b-router-core-nebula = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "espbranch";
          name = "b-router-core-nebula";
          site = "site-b";
        };
        platform = "nixos-container";
        ports = {
          upstream-selector = {
            adapterName = "p2p-b-router-core-nebula-b-router-upstream-selector-upstream-selector";
            attach = {
              bridge = "br-site-b-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-b-router-core-nebula-b-router-upstream-selector";
          };
        };
      };
      espbranch-site-b-b-router-core-simulated-isp = withDeniedResolverCidrs {
        host = "s-router-test";
        logicalNode = {
          enterprise = "espbranch";
          name = "b-router-core-simulated-isp";
          site = "site-b";
        };
        platform = "nixos-container";
        ports = {
          upstream-selector = {
            adapterName = "p2p-b-router-core-simulated-isp-b-router-upstream-selector-upstream-selector";
            attach = {
              bridge = "br-site-b-core-simulated-isp-upstream";
              kind = "bridge";
            };
            interface = {
              name = "upstream";
            };
            link = "p2p-b-router-core-simulated-isp-b-router-upstream-selector";
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
      espbranch-site-b-b-router-downstream-selector = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "espbranch";
          name = "b-router-downstream-selector";
          site = "site-b";
        };
        platform = "nixos-container";
        ports = {
          access-branch = {
            adapterName = "p2p-b-router-access-branch-b-router-downstream-selector-access-branch";
            attach = {
              bridge = "br-site-b-downstream-branch";
              kind = "bridge";
            };
            interface = {
              name = "access-branch";
            };
            link = "p2p-b-router-access-branch-b-router-downstream-selector";
          };
          access-hostile = {
            adapterName = "p2p-b-router-access-hostile-b-router-downstream-selector-access-hostile";
            attach = {
              bridge = "br-site-b-downstream-hostile";
              kind = "bridge";
            };
            interface = {
              name = "access-hostile";
            };
            link = "p2p-b-router-access-hostile-b-router-downstream-selector";
          };
          policy-branch = {
            adapterName = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch-policy-branch";
            attach = {
              bridge = "br-site-b-downstream-policy-access-branch";
              kind = "bridge";
            };
            interface = {
              name = "policy-branch";
            };
            link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch";
          };
          policy-hostile = {
            adapterName = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile-policy-hostile";
            attach = {
              bridge = "br-site-b-downstream-policy-access-hostile";
              kind = "bridge";
            };
            interface = {
              name = "policy-hostile";
            };
            link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile";
          };
        };
      };
      espbranch-site-b-b-router-policy = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "espbranch";
          name = "b-router-policy";
          site = "site-b";
        };
        platform = "nixos-container";
        ports = {
          downstream-branch = {
            adapterName = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch-downstream-branch";
            attach = {
              bridge = "br-site-b-downstream-policy-access-branch";
              kind = "bridge";
            };
            interface = {
              name = "down-branch";
            };
            link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch";
          };
          downstream-hostile = {
            adapterName = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile-downstream-hostile";
            attach = {
              bridge = "br-site-b-downstream-policy-access-hostile";
              kind = "bridge";
            };
            interface = {
              name = "down-hostile";
            };
            link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile";
          };
          upstream-branch = {
            adapterName = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan-upstream-branch";
            attach = {
              bridge = "br-site-b-policy-upstream-access-branch";
              kind = "bridge";
            };
            interface = {
              name = "upstream-branch";
            };
            link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan";
          };
          upstream-branch-east-west = {
            adapterName = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west-upstream-branch-east-west";
            attach = {
              bridge = "br-site-b-policy-upstream-access-branch-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-branch-ew";
            };
            link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west";
          };
          upstream-hostile-east-west = {
            adapterName = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west-upstream-hostile-east-west";
            attach = {
              bridge = "br-site-b-policy-upstream-access-hostile-east-west";
              kind = "bridge";
            };
            interface = {
              name = "up-hostile-ew";
            };
            link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west";
          };
        };
      };
      espbranch-site-b-b-router-upstream-selector = {
        host = "s-router-test";
        logicalNode = {
          enterprise = "espbranch";
          name = "b-router-upstream-selector";
          site = "site-b";
        };
        platform = "nixos-container";
        ports = {
          core-nebula = {
            adapterName = "p2p-b-router-core-nebula-b-router-upstream-selector-core-nebula";
            attach = {
              bridge = "br-site-b-core-nebula-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-nebula";
            };
            link = "p2p-b-router-core-nebula-b-router-upstream-selector";
          };
          core-simulated-isp = {
            adapterName = "p2p-b-router-core-simulated-isp-b-router-upstream-selector-core-simulated-isp";
            attach = {
              bridge = "br-site-b-core-simulated-isp-upstream";
              kind = "bridge";
            };
            interface = {
              name = "core-isp";
            };
            link = "p2p-b-router-core-simulated-isp-b-router-upstream-selector";
          };
          policy-branch = {
            adapterName = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan-policy-branch";
            attach = {
              bridge = "br-site-b-policy-upstream-access-branch";
              kind = "bridge";
            };
            interface = {
              name = "policy-branch";
            };
            link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan";
          };
          policy-branch-east-west = {
            adapterName = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west-policy-branch-east-west";
            attach = {
              bridge = "br-site-b-policy-upstream-access-branch-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-branch-ew";
            };
            link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west";
          };
          policy-hostile-east-west = {
            adapterName = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west-policy-hostile-east-west";
            attach = {
              bridge = "br-site-b-policy-upstream-access-hostile-east-west";
              kind = "bridge";
            };
            interface = {
              name = "pol-hostile-ew";
            };
            link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west";
          };
        };
      };
    };
  };
}
