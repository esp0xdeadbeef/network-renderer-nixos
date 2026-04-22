{
  endpoints = {
    web01 = {
      ipv4 = [ "10.20.15.10" ];
      ipv6 = [ "fd42:dead:beef:15::10" ];
    };

    s-sigma = {
      ipv4 = [ "10.20.10.10" ];
      ipv6 = [ "fd42:dead:beef:10::10" ];
    };
  };

  deployment = {
    hosts = {
      s-router-test = {
        wanUplink = "upstream-core";

        uplinks = {
          management = {
            parent = "eth0";
            mode = "vlan";
            vlan = 2;
            bridge = "vlan2";
          };

          upstream-core = {
            parent = "eth0";
            mode = "vlan";
            vlan = 5;
            bridge = "br-upstream";

            ipv6 = {
              method = "slaac";
              enable = true;
              acceptRA = true;
              dhcp = false;
              dhcpv6PD = false;
            };

            ipv4 = {
              method = "dhcp";
              enable = true;
              dhcp = true;
            };
          };

          trunk = {
            parent = "eth0";
            bridge = "br-fabric";
            mode = "trunk";
          };
        };

        transitBridges = {
          tr100 = {
            name = "tr100";
            vlan = 400;
            parentUplink = "trunk";
          };

          tr101 = {
            name = "tr101";
            vlan = 401;
            parentUplink = "trunk";
          };

          tr102 = {
            name = "tr102";
            vlan = 402;
            parentUplink = "trunk";
          };

          tr103 = {
            name = "tr103";
            vlan = 403;
            parentUplink = "trunk";
          };

          tr104 = {
            name = "tr104";
            vlan = 404;
            parentUplink = "trunk";
          };

          tr105 = {
            name = "tr105";
            vlan = 405;
            parentUplink = "trunk";
          };

          tr106 = {
            name = "tr106";
            vlan = 406;
            parentUplink = "trunk";
          };

          tr200 = {
            name = "tr200";
            vlan = 500;
            parentUplink = "trunk";
          };

          tr201 = {
            name = "tr201";
            vlan = 501;
            parentUplink = "trunk";
          };

          tr210 = {
            name = "tr210";
            vlan = 510;
            parentUplink = "trunk";
          };

          tr211 = {
            name = "tr211";
            vlan = 511;
            parentUplink = "trunk";
          };

          tr212 = {
            name = "tr212";
            vlan = 512;
            parentUplink = "trunk";
          };

          admin = {
            name = "admin";
            vlan = 310;
            parentUplink = "trunk";
          };

          client = {
            name = "client";
            vlan = 320;
            parentUplink = "trunk";
          };

          mgmt = {
            name = "mgmt";
            vlan = 330;
            parentUplink = "trunk";
          };
        };
      };
    };
  };

  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-core-wan = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-core-wan";
        };

        containers = {
          default = {
            runtimeName = "s-router-core-wan";
          };
        };

        ports = {
          upstream-selector = {
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
            adapterName = "core-upstream";
            attach = {
              kind = "bridge";
              bridge = "tr200";
            };
            interface = {
              name = "ens3";
            };
          };

          wan = {
            uplink = "wan";
            external = true;
            attach = {
              kind = "bridge";
              bridge = "br-upstream";
            };
            interface = {
              name = "wan";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-admin = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-admin";
        };

        containers = {
          default = {
            runtimeName = "s-router-access-admin";
          };
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            adapterName = "access-admin-downstream";
            attach = {
              kind = "bridge";
              bridge = "tr100";
            };
            interface = {
              name = "access-admin";
            };
          };

          tenant-admin = {
            logicalInterface = "tenant-admin";
            attach = {
              kind = "bridge";
              bridge = "admin";
            };
            interface = {
              name = "tenant-admin";
              addr4 = "10.20.15.1/24";
              addr6 = "fd42:dead:beef:15::1/64";
            };
          };
        };

        advertisements = {
          dhcp4 = {
            tenant-admin = {
              interface = "tenant-admin";
              id = "admin";
              subnet = "10.20.15.0/24";
              pool = {
                start = "10.20.15.100";
                end = "10.20.15.200";
              };
              router = "10.20.15.1";
              dnsServers = [ "10.20.15.1" ];
              domain = "lan.";
            };
          };

          ipv6Ra = {
            tenant-admin = {
              interface = "tenant-admin";
              prefixes = [ "fd42:dead:beef:15::/64" ];
              rdnss = [ "fd42:dead:beef:15::1" ];
              dnssl = [ "lan." ];
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-client = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-client";
        };

        containers = {
          default = {
            runtimeName = "s-router-access-client";
          };
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            adapterName = "access-client-downstream";
            attach = {
              kind = "bridge";
              bridge = "tr102";
            };
            interface = {
              name = "access-client";
            };
          };

          tenant-client = {
            logicalInterface = "tenant-client";
            attach = {
              kind = "bridge";
              bridge = "client";
            };
            interface = {
              name = "tenant-client";
              addr4 = "10.20.20.1/24";
              addr6 = "fd42:dead:beef:20::1/64";
            };
          };
        };

        advertisements = {
          dhcp4 = {
            tenant-client = {
              interface = "tenant-client";
              id = "client";
              subnet = "10.20.20.0/24";
              pool = {
                start = "10.20.20.100";
                end = "10.20.20.200";
              };
              router = "10.20.20.1";
              dnsServers = [ "10.20.20.1" ];
              domain = "lan.";
            };
          };

          ipv6Ra = {
            tenant-client = {
              interface = "tenant-client";
              prefixes = [ "fd42:dead:beef:20::/64" ];
              rdnss = [ "fd42:dead:beef:20::1" ];
              dnssl = [ "lan." ];
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-mgmt = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-mgmt";
        };

        containers = {
          default = {
            runtimeName = "s-router-access-mgmt";
          };
        };

        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            adapterName = "access-mgmt-downstream";
            attach = {
              kind = "bridge";
              bridge = "tr101";
            };
            interface = {
              name = "access-mgmt";
            };
          };

          tenant-mgmt = {
            logicalInterface = "tenant-mgmt";
            attach = {
              kind = "bridge";
              bridge = "mgmt";
            };
            interface = {
              name = "tenant-mgmt";
              addr4 = "10.20.10.1/24";
              addr6 = "fd42:dead:beef:10::1/64";
            };
          };
        };

        advertisements = {
          dhcp4 = {
            tenant-mgmt = {
              interface = "tenant-mgmt";
              id = "mgmt";
              subnet = "10.20.10.0/24";
              pool = {
                start = "10.20.10.100";
                end = "10.20.10.200";
              };
              router = "10.20.10.1";
              dnsServers = [ "10.20.10.1" ];
              domain = "lan.";
            };
          };

          ipv6Ra = {
            tenant-mgmt = {
              interface = "tenant-mgmt";
              prefixes = [ "fd42:dead:beef:10::/64" ];
              rdnss = [ "fd42:dead:beef:10::1" ];
              dnssl = [ "lan." ];
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-downstream-selector = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-downstream-selector";
        };

        containers = {
          default = {
            runtimeName = "s-router-downstream-selector";
          };
        };

        ports = {
          policy-access-admin = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin";
            adapterName = "dsel-policy-admin";
            attach.kind = "bridge";
            attach.bridge = "tr104";
            interface.name = "policy-admin";
          };

          policy-access-client = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
            adapterName = "dsel-policy-client";
            attach.kind = "bridge";
            attach.bridge = "tr105";
            interface.name = "policy-client";
          };

          policy-access-mgmt = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt";
            adapterName = "dsel-policy-mgmt";
            attach.kind = "bridge";
            attach.bridge = "tr106";
            interface.name = "policy-mgmt";
          };

          access-admin = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            adapterName = "dsel-access-admin";
            attach = {
              kind = "bridge";
              bridge = "tr100";
            };
            interface = {
              name = "access-admin";
            };
          };

          access-client = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            adapterName = "dsel-access-client";
            attach = {
              kind = "bridge";
              bridge = "tr102";
            };
            interface = {
              name = "access-client";
            };
          };

          access-mgmt = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            adapterName = "dsel-access-mgmt";
            attach = {
              kind = "bridge";
              bridge = "tr101";
            };
            interface = {
              name = "access-mgmt";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-policy = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-policy-only";
        };

        containers = {
          default = {
            runtimeName = "s-router-policy";
          };
        };

        ports = {
          upstream-access-admin-wan = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-wan";
            adapterName = "policy-upstream-admin";
            attach.kind = "bridge";
            attach.bridge = "tr210";
            interface.name = "upstream-admin";
          };

          upstream-access-client-wan = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-wan";
            adapterName = "policy-upstream-client";
            attach.kind = "bridge";
            attach.bridge = "tr211";
            interface.name = "upstream-client";
          };

          upstream-access-mgmt-wan = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-wan";
            adapterName = "policy-upstream-mgmt";
            attach.kind = "bridge";
            attach.bridge = "tr212";
            interface.name = "upstream-mgmt";
          };

          downstream-access-admin = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin";
            adapterName = "policy-downstream-admin";
            attach.kind = "bridge";
            attach.bridge = "tr104";
            interface.name = "downstream-admin";
          };

          downstream-access-client = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
            adapterName = "policy-downstream-client";
            attach.kind = "bridge";
            attach.bridge = "tr105";
            interface.name = "downstream-client";
          };

          downstream-access-mgmt = {
            link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt";
            adapterName = "policy-downstream-mgmt";
            attach.kind = "bridge";
            attach.bridge = "tr106";
            interface.name = "downstream-mgmt";
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-upstream-selector = {
        host = "s-router-test";
        platform = "nixos-container";

        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-upstream-selector";
        };

        containers = {
          default = {
            runtimeName = "s-router-upstream-selector";
          };
        };

        ports = {
          core = {
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
            adapterName = "upstream-core";
            attach = {
              kind = "bridge";
              bridge = "tr200";
            };
            interface = {
              name = "core";
            };
          };

          policy-access-admin-wan = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-wan";
            adapterName = "upstream-policy-admin";
            attach.kind = "bridge";
            attach.bridge = "tr210";
            interface.name = "policy-admin";
          };

          policy-access-client-wan = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-wan";
            adapterName = "upstream-policy-client";
            attach.kind = "bridge";
            attach.bridge = "tr211";
            interface.name = "policy-client";
          };

          policy-access-mgmt-wan = {
            link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-wan";
            adapterName = "upstream-policy-mgmt";
            attach.kind = "bridge";
            attach.bridge = "tr212";
            interface.name = "policy-mgmt";
          };
        };
      };
    };
  };
}
