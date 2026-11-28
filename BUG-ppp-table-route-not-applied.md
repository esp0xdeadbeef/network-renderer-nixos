# BUG: a `[Route]` with a non-main table is never applied on the PPPoE WAN

The tenant's egress default for the core's policy table is rendered into
`10-ppp0.network`, networkd reports the link as `routable (configured)`, and the table it
belongs to stays empty. Every tenant packet that reaches the core is then dropped, while the
core's own traffic works (its main-table default is present).

## Measured (neon HAT, renderer bcb418d4, CPM 2d5c0ec)

```
core # grep -A3 'Destination=0.0.0.0/0' /etc/systemd/network/10-ppp0.network
[Route]
Destination=0.0.0.0/0
Scope=link
Table=1003

core # networkctl status ppp0 --no-pager | grep State
State: routable (configured)

core # ip route show table 1003 | grep -c '^default'
0

core # ip route show table all | grep 'default dev ppp0'
default dev ppp0 scope link                 <- main only
```

No error is logged for it. After the link is up, the same route installs by hand:

```
core # systemctl restart systemd-networkd; sleep 3
core # ip route show table 1003 | grep -c '^default'
1
```

and the tenant's `ping 1.1.1.1` goes from 100% loss to `0% loss` (measured earlier in this
session, same command, same guest).

## Why it is a race, not a wrong route

ppp0 has no address until IPCP completes. systemd-networkd applies the `.network` file's
routes when it configures the link; a route that needs a source/device decision at that moment
is dropped, and networkd does not retry it when the peer address arrives -- the link is
already "configured". A restart re-runs the whole configuration, so the route lands.

The same file's main-table default is not affected in practice because pppd/networkd installs
the link-scope default for the peer independently.

## What a fix looks like

Emit gateway-less policy-table routes on a dynamically-addressed interface as a oneshot unit
that runs after the link has an address (`ip route replace ... table <t>`), which is the
pattern `s88/ControlModule/render/containers/module/static-provider-routes.nix` and
`.../delegated-routes.nix` already use for routes that cannot be expressed as a static
`[Route]`. Doing it in the `.network` file cannot be made reliable without an ordering hook.

## Consequence today

Both HAT sites are affected whenever the WAN is PPPoE (neon): the tenant sees 100% loss on
every probe, and the failure is invisible in the config -- the file is right, the link is up,
and the table is empty.
