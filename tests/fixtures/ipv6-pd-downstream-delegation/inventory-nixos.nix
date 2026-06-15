{
  controlPlane = {
    sites = {
      esp0xdeadbeef = {
        site-a = {
          tenants = {
            admin = {
              ipv6 = {
                mode = "slaac";
              };
            };
            client-a = {
              ipv6 = {
                mode = "dhcpv6";
              };
            };
            client-b = {
              ipv6 = {
                mode = "slaac";
              };
            };
            mgmt = {
              ipv6 = {
                mode = "static";
                prefixes = [ "2001:db8:10::/64" ];
              };
            };
          };
        };
      };
    };
  };
  deployment = {
    hosts = {
      lab-host = {
        bridgeNetworks = {
          br-site-a-core-upstream = { };
          br-site-a-downstream-admin = { };
          br-site-a-downstream-client-a = { };
          br-site-a-downstream-client-b = { };
          br-site-a-downstream-mgmt = { };
          br-site-a-downstream-policy-access-admin = { };
          br-site-a-downstream-policy-access-client-a = { };
          br-site-a-downstream-policy-access-client-b = { };
          br-site-a-downstream-policy-access-mgmt = { };
          br-site-a-policy-upstream-access-admin-wan = { };
          br-site-a-policy-upstream-access-client-a-wan = { };
          br-site-a-policy-upstream-access-client-b-wan = { };
          br-site-a-policy-upstream-access-mgmt-wan = { };
        };
        uplinks = {
          uplink0 = {
            bridge = "br-uplink0";
            ipv4 = {
              method = "dhcp";
            };
            ipv6 = {
              method = "slaac";
            };
            parent = "eno1";
          };
        };
      };
    };
  };
  endpoints = {
    s-sigma = {
      ipv4 = [ "10.20.10.10" ];
      ipv6 = [ "fd42:dead:beef:10::10" ];
    };
    web01 = {
      ipv4 = [ "10.20.15.10" ];
      ipv6 = [ "fd42:dead:beef:15::10" ];
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
            };
          };
          ipv6Ra = {
            tenant-admin = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-admin";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          transit-downstream-selector = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-access-admin-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-admin";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-client-a = {
        advertisements = {
          dhcp4 = {
            tenant-client-a = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-client-a = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-client-a";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          transit-downstream-selector = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-access-client-a-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-client-a";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-access-client-a-s-router-downstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-client-b = {
        advertisements = {
          dhcp4 = {
            tenant-client-b = {
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };
          };
          ipv6Ra = {
            tenant-client-b = {
              dnssl = [ "lan." ];
              rdnss = [ "router-self" ];
            };
          };
        };
        services.dns = { };
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-client-b";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          transit-downstream-selector = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-access-client-b-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-client-b";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-access-client-b-s-router-downstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-access-mgmt = {
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
        services.dns = { };
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-access-mgmt";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          transit-downstream-selector = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-access-mgmt-transit-downstream-selector";
            attach = {
              bridge = "br-site-a-downstream-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-core-wan = {
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-core-wan";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          upstream-selector = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-core-wan-upstream-selector";
            attach = {
              bridge = "br-site-a-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
          };
          wan = {
            attach = {
              bridge = "br-uplink0";
              kind = "bridge";
            };
            external = true;
            interface = {
              name = "ens4";
            };
            uplink = "wan";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-downstream-selector = {
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-downstream-selector";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          access-admin = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-access-admin";
            attach = {
              bridge = "br-site-a-downstream-admin";
              kind = "bridge";
            };
            interface = {
              name = "ens7";
            };
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
          };
          access-client-a = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-access-client-a";
            attach = {
              bridge = "br-site-a-downstream-client-a";
              kind = "bridge";
            };
            interface = {
              name = "ens6";
            };
            link = "p2p-s-router-access-client-a-s-router-downstream-selector";
          };
          access-client-b = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-access-client-b";
            attach = {
              bridge = "br-site-a-downstream-client-b";
              kind = "bridge";
            };
            interface = {
              name = "ens9";
            };
            link = "p2p-s-router-access-client-b-s-router-downstream-selector";
          };
          access-mgmt = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-access-mgmt";
            attach = {
              bridge = "br-site-a-downstream-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "ens8";
            };
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
          };
          policy-access-admin = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-policy-access-admin";
            attach = {
              bridge = "br-site-a-downstream-policy-access-admin";
              kind = "bridge";
            };
            interface = {
              name = "ens4";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-admin";
          };
          policy-access-client-a = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-policy-access-client-a";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client-a";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-client-a";
          };
          policy-access-client-b = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-policy-access-client-b";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client-b";
              kind = "bridge";
            };
            interface = {
              name = "ens10";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-client-b";
          };
          policy-access-mgmt = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-downstream-selector-policy-access-mgmt";
            attach = {
              bridge = "br-site-a-downstream-policy-access-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "ens5";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-mgmt";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-policy = {
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-policy";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          downstream-access-admin = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-downstream-access-admin";
            attach = {
              bridge = "br-site-a-downstream-policy-access-admin";
              kind = "bridge";
            };
            interface = {
              name = "ens7";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-admin";
          };
          downstream-access-client-a = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-downstream-access-client-a";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client-a";
              kind = "bridge";
            };
            interface = {
              name = "ens6";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-client-a";
          };
          downstream-access-client-b = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-downstream-access-client-b";
            attach = {
              bridge = "br-site-a-downstream-policy-access-client-b";
              kind = "bridge";
            };
            interface = {
              name = "ens9";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-client-b";
          };
          downstream-access-mgmt = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-downstream-access-mgmt";
            attach = {
              bridge = "br-site-a-downstream-policy-access-mgmt";
              kind = "bridge";
            };
            interface = {
              name = "ens8";
            };
            link = "p2p-s-router-downstream-selector-s-router-policy--access-s-router-access-mgmt";
          };
          upstream-access-admin-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-upstream-access-admin-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens4";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-admin--uplink-wan";
          };
          upstream-access-client-a-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-upstream-access-client-a-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-a-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-client-a--uplink-wan";
          };
          upstream-access-client-b-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-upstream-access-client-b-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-b-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens10";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-client-b--uplink-wan";
          };
          upstream-access-mgmt-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-policy-upstream-access-mgmt-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens5";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-mgmt--uplink-wan";
          };
        };
      };
      esp0xdeadbeef-site-a-s-router-upstream-selector = {
        host = "lab-host";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          name = "s-router-upstream-selector";
          site = "site-a";
        };
        platform = "linux";
        ports = {
          core = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-upstream-selector-core";
            attach = {
              bridge = "br-site-a-core-upstream";
              kind = "bridge";
            };
            interface = {
              name = "ens3";
            };
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
          };
          policy-access-admin-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-upstream-selector-policy-access-admin-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-admin-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens5";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-admin--uplink-wan";
          };
          policy-access-client-a-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-upstream-selector-policy-access-client-a-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-a-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens4";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-client-a--uplink-wan";
          };
          policy-access-client-b-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-upstream-selector-policy-access-client-b-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-client-b-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens7";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-client-b--uplink-wan";
          };
          policy-access-mgmt-wan = {
            adapterName = "adp-esp0xdeadbeef-site-a-s-router-upstream-selector-policy-access-mgmt-wan";
            attach = {
              bridge = "br-site-a-policy-upstream-access-mgmt-wan";
              kind = "bridge";
            };
            interface = {
              name = "ens6";
            };
            link = "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-mgmt--uplink-wan";
          };
        };
      };
    };
  };
}
