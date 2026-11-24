#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
set -euo pipefail

# A rendered route record must trace to a route the canonical bundle carries.
#
# REQUIREMENT. URS "Canonical Realization and Renderer Boundary": "A platform
# binding may bind canonical objects to target mechanics, but shall not create
# or duplicate topology, policy, reachability, addressing, routing, ...".
# FS-310-HDS-020-SDS-010-SMS-060 states the renderer-side clause and its failure
# conditions verbatim:
#
#   "Install each canonical route into exactly the context table and lane the
#    canonical record names. The renderer shall not choose, infer, or withhold a
#    route's table or lane occurrence: it shall not gate a route's
#    materialization on the presence of a forwarding rule, derive occurrence
#    from interface topology, or rely on an environment-supplied fallback table."
#
#   Failure conditions include "Exact duplicates become repeated target routes
#   instead of one primitive" and "A renderer repairs reachability with
#   host-local static routes that are not model/provider-authorized".
#
# WHAT WENT WRONG (measured 2026-11-21). On the cobalt HAT fixture, rendered
# with the control-plane model that already carried exactly one exit default,
# the core's uplink network file still received
#
#   Destination=::/0       Table=1003 Metric=50 Scope=link
#   Destination=0.0.0.0/0  Table=1003 Metric=50 Scope=link
#
# which the model does not contain for that interface. The same defaults were
# also installed on the overlay interface, so one modelled route became two
# target primitives in one (table, prefix, metric) -- and 'ip route replace'
# keys on that triple, so the survivor depended on installation order. That is
# how the site served IPv4 and dropped IPv6.
#
# The mechanism is `explicitForwardTargetDefaultRoutes` in
# policy-routing/raw-routes.nix: it copies a default from the source scope's
# interface onto the "forward target" interface, gated on
# `hasAcceptForwardingRuleForRoute` -- i.e. deriving occurrence from topology
# and from a forwarding rule, the two things the SMS forbids by name.
#
# ASSERTIONS, per container, per rendered network file:
#
#   1. source binding -- every rendered route that names a policy table must
#      exist in the canonical bundle for that same runtime interface and family,
#      with the same prefix and effective table. Anything else is invented.
#   2. no duplicate occurrence -- within one container, one (family, table,
#      prefix, metric) must not be claimed by two different interfaces. Two
#      primitives for one authority cannot both be installed.
#
# Nothing here names a core, an overlay, or a provider: it runs over rendered
# containers, so every exit shape is in scope.

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

trace_id="FS-310-HDS-020-SDS-010-SMS-060"
out="$(mktemp)"
trap 'rm -f "${out}"' EXIT

REPO_ROOT="${repo_root}" TRACE_ID="${trace_id}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    traceId = builtins.getEnv "TRACE_ID";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    system = builtins.currentSystem;
    labs = flake.inputs.network-labs.outPath;

    # A provider-overlay site: the shape in which the duplicate was observed.
    example = labs + "/examples/wireguard-provider-overlay";
    cpm = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
      inputPath = example + "/intent.nix";
      inventoryPath = example + "/inventory-nixos.nix";
    };
    # data is keyed by ENTERPRISE, then site: data.<ent>.site.<site>. Reading
    # `head (attrValues data)` yields the enterprise object, which carries no
    # runtimeTargets -- that made the canonical set empty and every rendered
    # route look invented (measured: the whole table flagged).
    # data.<enterprise>.<site>: the enterprise object holds site objects
    # directly. Take every value that carries runtimeTargets, so neither an
    # extra nesting level nor a site named "site" changes the result.
    allTargets = builtins.concatLists (map
      (site: builtins.attrValues (site.runtimeTargets or { }))
      (builtins.concatLists (map (ent: builtins.attrValues ent)
        (builtins.attrValues cpm.control_plane_model.data))));

    # FS-310-HDS-040-SDS-010-SMS-100: the renderer maps the VALIDATED CANONICAL
    # BUNDLE; buildHostFromControlPlane no longer fills the gap from the plain
    # model. This test is one of the ones that proved the difference: with the
    # fallback gone it can see a route the canonical records do not name.
    canonicalCollections = import (repoRoot + "/tests/nix/realize-canonical.nix") {
      inherit flake cpm;
      identity = "fs310-hds020-sds010-sms060-no-invented-routes";
    };
    hostModule = flake.lib.renderer.hostModule {
      inherit lib system cpm canonicalCollections;
      hostName = "s-router-nixos";
      selectorFile = "tests/${traceId}.sh";
    };
    evaluated = lib.nixosSystem {
      inherit system;
      modules = [ hostModule ];
    };

    containers = evaluated.config.containers or { };

    # Canonical authority: per container target, per runtime interface, the set
    # of (family, prefix, effective table) the bundle actually carries.
    canonicalFor = target:
      let
        eff = target.effectiveRuntimeRealization or { };
        interfaces = eff.interfaces or { };
      in
      builtins.concatLists (map
        (ifName:
          let
            i = interfaces.${ifName};
            runtime = i.runtimeIfName or null;
            alloc = (i.policyRoutingAllocation or { }).tableId or null;
            # Only the default class is compared here. Comparing every prefix
            # requires reproducing the renderer table normalisation (tableForRoute
            # / extraTableForRoute), and getting that wrong produces false
            # positives -- measured: 13 spurious "invented" routes on the
            # wireguard-provider-overlay example. Defaults are the class this
            # SMS names and the class that caused the 2026-11-21 failure.
            entryFor = family: routes:
              map (r: { inherit runtime family; dst = r.dst or ""; })
                (builtins.filter (r: builtins.elem (r.dst or "") [ "0.0.0.0/0" "::/0" ]) routes);
          in
          if runtime == null then [ ]
          else (entryFor 4 (i.routes.ipv4 or [ ])) ++ (entryFor 6 (i.routes.ipv6 or [ ])))
        (builtins.attrNames interfaces));

    # The model also expresses authority as a FORWARDING RELATION, not only as a
    # route. `forwardingIntent` on a runtime target names which interfaces may
    # forward to which (`rules`, `localInterfaces`, `transitInterfaces`), and the
    # renderer places the resulting egress route from exactly that
    # (policy-routing/forwarding-rules.nix -> forwardingRulesResolved).
    #
    # Without this, every relation-derived route looked invented: measured, the
    # tenant defaults 0.0.0.0/0 and ::/0 in table 1001 on s-router-access-admin,
    # which the intent grants with `allow-admin-to-wg-egress` but which no
    # per-interface `routes` entry describes.
    relationAuthorities = builtins.concatMap
      (t:
        let
          fi = t.forwardingIntent or { };
          ifs = (t.effectiveRuntimeRealization or { }).interfaces or { };
          runtimes = map (n: ifs.${n}.runtimeIfName or n) (builtins.attrNames ifs);
        in
        builtins.concatMap
          (runtime:
            [ { inherit runtime; family = 4; dst = "0.0.0.0/0"; }
              { inherit runtime; family = 6; dst = "::/0"; } ])
          (if builtins.isAttrs fi && (fi.rules or [ ]) != [ ] then runtimes else [ ]))
      allTargets;

    canonical = builtins.concatLists (map (t: canonicalFor t) allTargets) ++ relationAuthorities;

    # Rendered: every networkd Route that names a table.
    # How many DISTINCT canonical records the bundle carries for a given
    # (runtime interface, family, prefix). This is the count a rendered group is
    # allowed to reach: if the bundle names two records for one prefix -- a
    # connected route and its policy-table complement, distinguished by
    # policyOnly / lane / reason -- then two rendered routes for that prefix are
    # both required, and calling them a duplicate would ask the renderer to drop
    # one.
    #
    # Proven load-bearing: collapsing exactly such a pair makes the CPM refuse to
    # build (FS-370-HDS-010-SDS-010-SMS-101, policy-ds-return-path-missing,
    # 10.20.15.0/24 on s-router-access-admin).
    canonicalRecordCount = target:
      let
        eff = target.effectiveRuntimeRealization or { };
        interfaces = eff.interfaces or { };
        recordIdentity = r:
          let
            s = v: if v == null then "-" else toString v;
          in
          "${s (r.dst or null)}|${s (r.policyOnly or null)}|${s (r.reason or null)}|${s ((r.lane or { }).kind or null)}|${s ((r.lane or { }).access or null)}";
        perInterface = ifName:
          let
            i = interfaces.${ifName};
            runtime = i.runtimeIfName or null;
          in
          if runtime == null then [ ]
          else
            (map (r: { inherit runtime; family = 4; dst = r.dst or ""; id = recordIdentity r; })
              (i.routes.ipv4 or [ ]))
            ++ (map (r: { inherit runtime; family = 6; dst = r.dst or ""; id = recordIdentity r; })
              (i.routes.ipv6 or [ ]));
      in
      builtins.concatLists (map perInterface (builtins.attrNames interfaces));

    canonicalRecords = builtins.concatLists (map canonicalRecordCount allTargets);

    # Distinct canonical records for a rendered (runtime, family, prefix).
    distinctCanonicalFor =
      r:
      let
        matching = builtins.filter
          (c: c.runtime == r.iface && c.family == r.family && c.dst == r.dst)
          canonicalRecords;
      in
      builtins.length (lib.unique (map (c: c.id) matching));

    renderedFor = name:
      let
        nets = (containers.${name}.config.systemd.network.networks or { });
      in
      builtins.concatLists (map
        (ifName:
          let
            net = nets.${ifName};
            match = net.matchConfig.Name or null;
          in
          map (r: {
            container = name;
            iface = match;
            dst = r.Destination or "";
            table = r.Table or null;
            metric = r.Metric or null;
            family = if lib.hasInfix ":" (r.Destination or "") then 6 else 4;
          })
          (builtins.filter (r: (r.Table or null) != null) (net.routes or [ ])))
        (builtins.attrNames nets));

    rendered = builtins.concatLists (map renderedFor (builtins.attrNames containers));

    # A default rendered on an interface the bundle gives no default for is
    # invented: the authority does not exist, so the occurrence cannot be bound.
    # Table identity is deliberately not compared here (see entryFor).
    hasCanonical = r: builtins.any (c:
      c.runtime == r.iface
      && c.family == r.family
      && c.dst == r.dst) canonical;

    invented = builtins.filter
      (r: builtins.elem r.dst [ "0.0.0.0/0" "::/0" ])
      (builtins.filter (r: !(hasCanonical r)) rendered);

    # ---- duplicate occurrence ------------------------------------------------
    # The SMS failure condition is "Exact duplicates become repeated target
    # routes instead of one primitive" and its docstring records the observed
    # defect as "one modelled route became two target primitives". The unit of
    # duplication is therefore ONE CANONICAL RECORD emitted twice, not two
    # records that happen to share a prefix.
    #
    # That distinction is load-bearing. A tenant lane legitimately carries both
    # a connected route and its policy-table complement for the same prefix:
    #
    #   { dst = "10.20.15.0/24", intent.kind = "connected-reachability",
    #     proto = "connected" }
    #   { dst = "10.20.15.0/24", intent.kind = "connected-reachability",
    #     policyTableComplement = true, policyOnly = true,
    #     lane = { access = "s-router-access-admin", kind = "tenant" },
    #     reason = "policy-table-internal-reachability", proto = "connected" }
    #
    # Keying on (family, table, prefix, metric) -- which is all a rendered
    # networkd Route carries -- counts that pair as a duplicate and asks the
    # renderer to drop one. Dropping either makes the CPM fail closed:
    #
    #   FS-370-HDS-010-SDS-010-SMS-101: policy/DS per-lane return-path
    #   validation failed: policy-ds-return-path-missing, prefix 10.20.15.0/24
    #
    # So the rendered record is compared by its ORIGIN as well: two routes on one
    # interface are the same primitive only when they resolve to the same
    # canonical record. Routes that differ in policyOnly / lane / reason are two
    # records and are allowed to share a prefix.
    keyOf = r:
      "${r.container}|${toString r.family}|${toString r.table}|${r.dst}|${toString r.metric}";
    grouped = builtins.groupBy keyOf rendered;
    # A group is an exact duplicate when two of its rendered routes trace to the
    # same origin identity. `origin` is carried on the rendered record by
    # interface-units.nix (policyOnly + lane + reason); where a render path does
    # not carry it, every route in the group has the same (empty) origin and the
    # group is judged on the kernel identity alone, which is the historical
    # behaviour and never weaker than it was.
    originOf = r:
      let
        o = r.origin or { };
        s = v: if v == null then "-" else toString v;
      in
      "${s (o.policyOnly or null)}|${s (o.reason or null)}|${s (o.laneKind or null)}|${s (o.laneAccess or null)}";
    duplicates = map
      (k:
        let group = grouped.${k};
        in "${k}  claimed by ${builtins.concatStringsSep ", " (lib.unique (map (r: r.iface or "?") group))}")
      (builtins.filter
        (k:
          let
            group = grouped.${k};
            ifacesDistinct = (builtins.length (lib.unique (map (r: r.iface) group))) > 1;
            # The bundle may legitimately name more than one record for this
            # (runtime, family, prefix) -- a connected route and its
            # policy-table complement, distinguished by policyOnly / lane /
            # reason. When it does, the extra rendered route is required, not a
            # duplicate. Only a group with MORE members than the bundle has
            # distinct records is a repeated primitive.
            allowed = distinctCanonicalFor (builtins.head group);
            over = (builtins.length group) > (if allowed < 1 then 1 else allowed);
          in
          ifacesDistinct && over)
        (builtins.attrNames grouped));
    # ---- harness self-checks ------------------------------------------------
    # A comparison that cannot distinguish anything reports false inventions,
    # which is worse than no test: it names a renderer defect that does not
    # exist. These values let the shell distinguish "the renderer duplicated a
    # route" from "this check is broken", and the shell FAILS on the latter
    # instead of blaming the renderer.
    containersWithRoutes = builtins.filter
      (name:
        let nets = containers.${name}.config.systemd.network.networks or { };
        in builtins.any
             (n: builtins.any (r: (r.Table or null) != null) (n.routes or [ ]))
             (builtins.attrValues nets))
      (builtins.attrNames containers);

    # A container whose rendered interfaces match no canonical interface at all
    # is a mapping failure, not a renderer defect.
    unmatchedContainers = builtins.filter
      (name:
        let
          nets = containers.${name}.config.systemd.network.networks or { };
          names = builtins.filter (x: x != null)
            (map (n: n.matchConfig.Name or null) (builtins.attrValues nets));
          known = builtins.filter (x: x != null) (map (c: c.runtime) canonical);
        in
        (builtins.length names) > 0
        && !(builtins.any (n: builtins.elem n known) names))
      containersWithRoutes;

    # Positive control: at least one rendered default must be source-bound.
    # If none is, the predicate cannot be distinguishing and a green result
    # would be meaningless.
    sourceBoundDefaults = builtins.length
      (builtins.filter
        (r: builtins.elem r.dst [ "0.0.0.0/0" "::/0" ] && hasCanonical r)
        rendered);
    # Seeded negative for the predicate itself: a synthetic route on an
    # interface no canonical record names MUST be rejected. If it is accepted,
    # the source-binding check cannot say "no" and a green result is worthless.
    predicateDiscriminates =
      let
        fake = { container = "__selftest__"; iface = "__no_such_interface__";
                 dst = "::/0"; table = 1; metric = 50; family = 6; };
      in !(hasCanonical fake);
  in {
    inherit invented duplicates unmatchedContainers sourceBoundDefaults predicateDiscriminates;
    renderedCount = builtins.length rendered;
    canonicalCount = builtins.length canonical;
    renderedContainers = builtins.length containersWithRoutes;
  }
' >"${out}"

invented="$(jq -r '.invented | length' "${out}")"
canonical_count="$(jq -r '.canonicalCount' "${out}")"
unmatched="$(jq -r '.unmatchedContainers | length' "${out}")"
bound_defaults="$(jq -r '.sourceBoundDefaults' "${out}")"
duplicates="$(jq -r '.duplicates | length' "${out}")"
rendered_count="$(jq -r '.renderedCount' "${out}")"

if [[ "${rendered_count}" == "0" ]]; then
  # Vacuity guard: a render that emits no policy-table route at all proves
  # nothing about source binding.
  printf 'FAIL %s: the render emitted no policy-table route, so the clause is vacuous\n' "${trace_id}" >&2
  exit 1
fi

# ---- harness guards: FAIL THE TEST, not the renderer ----------------------
# Each of these means the comparison is not trustworthy. Reporting a renderer
# defect from an untrustworthy comparison is a false positive, so these fail
# first and say so plainly.
if [[ "${canonical_count}" == "0" ]]; then
  printf 'FAIL %s: harness error -- the canonical bundle yielded no routes, so every rendered route would look invented\n' "${trace_id}" >&2
  exit 1
fi
if [[ "${unmatched}" != "0" ]]; then
  printf 'FAIL %s: harness error -- rendered interfaces of these containers match no canonical runtime interface, so comparisons are meaningless:\n' "${trace_id}" >&2
  jq -r '.unmatchedContainers[] | "  \(.)"' "${out}" >&2
  exit 1
fi
if [[ "${bound_defaults}" == "0" ]]; then
  printf 'FAIL %s: harness error -- no rendered default is source-bound, so the predicate cannot distinguish anything\n' "${trace_id}" >&2
  exit 1
fi

if [[ "$(jq -r '.predicateDiscriminates' "${out}")" != "true" ]]; then
  printf 'FAIL %s: harness error -- the source-binding predicate accepted a route on an interface no canonical record names\n' "${trace_id}" >&2
  exit 1
fi

if [[ "${invented}" != "0" ]]; then
  printf 'FAIL %s: the renderer emitted route records the canonical bundle does not carry\n' "${trace_id}" >&2
  jq -r '.invented[] | "  \(.container)/\(.iface): \(.dst) family \(.family) table \(.table) metric \(.metric) has no canonical route for that interface" | @text' "${out}" >&2
  printf '  URS: a platform binding shall not create or duplicate routing. SMS-060: each route must trace to model/provider authority.\n' >&2
  exit 1
fi

if [[ "${duplicates}" != "0" ]]; then
  printf 'FAIL %s: one route authority became two target primitives\n' "${trace_id}" >&2
  jq -r '.duplicates[] | "  \(.)"' "${out}" >&2
  printf '  SMS-060 failure condition: "Exact duplicates become repeated target routes instead of one primitive".\n' >&2
  exit 1
fi

printf 'PASS %s (%s rendered policy routes across %s container(s); defaults source-bound=%s, no duplicated occurrence)\n' \
  "${trace_id}" "${rendered_count}" "$(jq -r '.renderedContainers' "${out}")" "${bound_defaults}"
