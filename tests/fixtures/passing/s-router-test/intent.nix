{
  esp0xdeadbeef.site-a = {
    pools = {
      p2p = {
        ipv4 = "10.10.0.0/24";
        ipv6 = "fd42:dead:beef:1000::/118";
      };

      loopback = {
        ipv4 = "10.19.0.0/24";
        ipv6 = "fd42:dead:beef:1900::/118";
      };
    };

    ownership = {
      prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.20.10.0/24";
          ipv6 = "fd42:dead:beef:10::/64";
        }
        {
          kind = "tenant";
          name = "admin";
          ipv4 = "10.20.15.0/24";
          ipv6 = "fd42:dead:beef:15::/64";
        }
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.20.20.0/24";
          ipv6 = "fd42:dead:beef:20::/64";
        }
      ];

      endpoints = [
        {
          kind = "host";
          name = "s-sigma";
          tenant = "mgmt";
        }
        {
          kind = "host";
          name = "web01";
          tenant = "admin";
        }
      ];
    };

    communicationContract = {
      trafficTypes = [
        {
          name = "icmp";
          match = [
            {
              proto = "icmp";
              family = "any";
            }
          ];
        }

        {
          name = "dns";
          match = [
            {
              proto = "udp";
              dports = [ 53 ];
              family = "any";
            }
            {
              proto = "tcp";
              dports = [ 53 ];
              family = "any";
            }
          ];
        }

        {
          name = "ssh";
          match = [
            {
              proto = "tcp";
              dports = [ 22 ];
              family = "any";
            }
          ];
        }

        {
          name = "web";
          match = [
            {
              proto = "tcp";
              dports = [
                80
                443
              ];
              family = "any";
            }
          ];
        }

        {
          name = "wireguard";
          match = [
            {
              proto = "udp";
              dports = [ 51820 ];
              family = "any";
            }
          ];
        }
      ];

      services = [
        {
          name = "site-dns";
          trafficType = "dns";
          providers = [ "s-sigma" ];
        }

        {
          name = "jump-host";
          trafficType = "ssh";
          providers = [ "s-sigma" ];
        }

        {
          name = "admin-web";
          trafficType = "web";
          providers = [ "web01" ];
        }
      ];

      relations = [
        {
          id = "allow-mgmt-internal";
          priority = 10;
          from = {
            kind = "tenant-set";
            members = [ "mgmt" ];
          };
          to = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
            ];
          };
          trafficType = "any";
          action = "allow";
        }

        {
          id = "allow-icmp-anywhere";
          priority = 20;
          from = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
            ];
          };
          to = "any";
          trafficType = "icmp";
          action = "allow";
        }

        {
          id = "deny-web-to-wan";
          priority = 50;
          from = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
            ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "web";
          action = "deny";
        }

        {
          id = "allow-tenants-to-wan";
          priority = 100;
          from = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
            ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }

        {
          id = "allow-wan-to-jump-host";
          priority = 110;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "jump-host";
          };
          trafficType = "ssh";
          action = "allow";
        }

        {
          id = "allow-wan-to-mgmt-icmp";
          priority = 115;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "tenant";
            name = "mgmt";
          };
          trafficType = "icmp";
          action = "allow";
        }

        {
          id = "allow-wan-to-admin-web";
          priority = 120;
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "admin-web";
          };
          trafficType = "web";
          action = "allow";
        }
      ];

      interfaceTags = {
        tenant-mgmt = "mgmt";
        tenant-admin = "admin";
        tenant-client = "client";
        external-wan = "wan";
        service-site-dns = "site-dns";
        service-jump-host = "jump-host";
        service-admin-web = "admin-web";
      };
    };

    topology = {
      nodes = {
        s-router-core-wan = {
          role = "core";

          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
        };

        s-router-policy-only = {
          role = "policy";
        };

        s-router-downstream-selector = {
          role = "downstream-selector";
        };

        s-router-access-mgmt = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "mgmt";
            }
          ];
        };

        s-router-access-admin = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "admin";
            }
          ];
        };

        s-router-access-client = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "client";
            }
          ];
        };
      };

      links = [
        [
          "s-router-core-wan"
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
          "s-router-policy-only"
        ]
        [
          "s-router-policy-only"
          "s-router-downstream-selector"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-client"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-admin"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-mgmt"
        ]
      ];
    };
  };
}
