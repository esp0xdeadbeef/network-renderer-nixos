# BUG: a service prefix is installed on a tenant interface the model does not name there

Status: OPEN, filed 2026-11-25. Found by `tests/FS-310-HDS-020-SDS-010-SMS-060.sh`
once the renderer actually consumed the canonical bundle (392dfbea). The raw-CPM
fallback this repository used to have made the comparison vacuous, so the defect
was not observable before.

## Reproduction

```
NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/FS-310-HDS-020-SDS-010-SMS-060.sh
...
FAIL FS-310-HDS-020-SDS-010-SMS-060: one route authority became two target primitives
  s-router-access-admin|4|1002|10.19.0.1/32|50   claimed by ens3, tenant-admin
  s-router-access-admin|4|1002|10.19.0.2/32|50   claimed by ens3, tenant-admin
  s-router-access-admin|4|1002|10.19.0.5/32|50   claimed by ens3, tenant-admin
  s-router-access-admin|4|1002|10.20.10.0/24|50  claimed by ens3, tenant-admin
  s-router-access-admin|4|1002|10.20.20.0/24|50  claimed by ens3, tenant-admin
  s-router-access-admin|6|1002|fd42:dead:beef:0010::/64|50  claimed by ens3, tenant-admin
```

## What is established

- The canonical bundle DOES name `10.20.10.0/24` (and the others) on `ens3` --
  measured, realising network-labs/examples/wireguard-provider-overlay through
  network-realization-model: the prefix appears on ens3 (several times), ens4,
  ens5, ens7, ens8, ens10 and `tenant-mgmt`.
- It does NOT name it on `tenant-admin`.
- So the `ens3` occurrence is faithful and the `tenant-admin` one is not: the
  renderer is installing a route on an interface whose canonical records do not
  include it. That is the FS-310-HDS-020-SDS-010-SMS-060 failure condition verbatim -- "Exact duplicates
  become repeated target routes instead of one primitive".
- `dropDerivedCopies` (fixed in d1d7aca2 to collect canonical keys across the
  whole TARGET, not just the current interface) is not the whole story: the
  surviving copy is being emitted for an interface the model never named.

## Why it is filed rather than fixed here

Two candidate repairs, and they are a routing-semantics decision:

1. the renderer must install a canonical route ONLY on the interface its record
   names, and the derived path must not re-create it elsewhere on the target
   (a renderer repair, and the likely correct one); or
2. the model should name the prefix on the tenant interface too (a model repair,
   which would make the current render correct).

(1) changes which routes every access container installs, so it wants the row
owner's read of FS-310-HDS-020-SDS-010-SMS-060, not a guess made while clearing a red test.

## Not the same as

network-control-plane-model BUG-390-return-path-MINI-SMT.md, which is a
pre-existing compile failure in a different mini-SMT row.
