# FS-310-HDS-020-SDS-010-SMS-060 (rendered policy route placement / lane
# occurrence).
#
# A canonical route record carries five things that decide where the route is
# installed: (interface, table, dst, gateway, metric). The renderer is allowed to
# map that onto a platform primitive. It is not allowed to decide it.
#
# It does decide it today: `policy-routing/route-helpers.nix` recomputes the
# output interface (`routeOutputInterface`) and `policy-routing/aggregate.nix`
# recomputes the table (`tableForOutputIfName`), and
# `render/container-networks/interface-units.nix` appends the model's own records
# to the derived ones, deleting duplicates with `dropDerivedCopies`. That
# heuristic keys on all five parts, so a derived route that agrees on dst,
# gateway and metric but disagrees on TABLE is not a duplicate: it survives next
# to the canonical record, one model route becomes two target primitives in two
# tables, and nothing reports it. Measured on the provider-overlay example: 97
# canonical records become 363 rendered routes.
#
# This module is the enforcement, not the repair. Where a derived route and a
# canonical record describe the same route (same dst, gateway, metric) for the
# same interface in different tables, the render throws and names the row, the
# five-part identity, and both places. Deleting the re-derivation, or making it
# agree with the model, is the fix and is a separate change.
{ lib }:

let
  placeOf =
    route:
    {
      table = route.Table or route.table or null;
      dst = route.Destination or route.dst or null;
      gateway = route.Gateway or route.gateway or null;
      metric = route.Metric or route.metric or null;
    };

  # Everything except the table: the parts that identify WHICH route this is.
  identityWithoutTable =
    place: "${toString place.dst}|${toString place.gateway}|${toString place.metric}";

  # Every (derived, canonical) pair that describes one route in two tables.
  disagreements =
    {
      canonicalRoutes ? [ ],
      derivedRoutes ? [ ],
    }:
    let
      canonicalPlaces = map placeOf (lib.filter builtins.isAttrs canonicalRoutes);
      derivedPlaces = map placeOf (lib.filter builtins.isAttrs derivedRoutes);
    in
    builtins.concatMap (
      derived:
      map (canonical: { inherit derived canonical; }) (
        builtins.filter (
          canonical:
          canonical.dst != null
          && identityWithoutTable canonical == identityWithoutTable derived
          && canonical.table != derived.table
        ) canonicalPlaces
      )
    ) (builtins.filter (place: place.dst != null) derivedPlaces);
in
{
  inherit disagreements placeOf;

  # `true` when the renderer's place agrees with the model's for every route both
  # describe. Throws otherwise -- never a warning, never a preference.
  assertAgrees =
    {
      ifName,
      canonicalRoutes ? [ ],
      derivedRoutes ? [ ],
    }:
    let
      found = disagreements { inherit canonicalRoutes derivedRoutes; };
    in
    if found == [ ] then
      true
    else
      let
        first = builtins.head found;
        d = first.derived;
        c = first.canonical;
      in
      throw "FS-310-HDS-020-SDS-010-SMS-060: a rendered route's place disagrees with the canonical record. Route identity (interface, table, dst, gateway, metric): rendered ('${ifName}', ${toString d.table}, '${toString d.dst}', '${toString d.gateway}', '${toString d.metric}') vs canonical ('${ifName}', ${toString c.table}, '${toString c.dst}', '${toString c.gateway}', '${toString c.metric}'). The renderer recomputed the output interface and table and then appended the canonical record beside the derived copy, so one model route becomes two target primitives in two tables. A renderer may not choose a route's table or lane occurrence. ${builtins.toString (builtins.length found)} disagreement(s) on interface '${ifName}'.";
}
