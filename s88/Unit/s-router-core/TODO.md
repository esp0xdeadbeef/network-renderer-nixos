fix the routes, these are now in the box:
[root@s-router-core-wan:~]# ip route
default via 10.13.0.1 dev wan-wan proto dhcp src 10.13.0.50 metric 1024
10.10.0.6/31 dev wan-lan proto kernel scope link src 10.10.0.6
10.13.0.0/24 dev wan-wan proto kernel scope link src 10.13.0.50 metric 1024
10.13.0.1 dev wan-wan proto dhcp scope link src 10.13.0.50 metric 1024
10.128.0.1 via 10.13.0.1 dev wan-wan proto dhcp src 10.13.0.50 metric 1024
