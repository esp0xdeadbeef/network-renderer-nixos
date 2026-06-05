{ lib }:

let
  secretKeyParts = [ "password" "passphrase" "private" "secret" "token" ];

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  stringContains = needle: haystack:
    builtins.match ".*${needle}.*" haystack != null;

  keyIsSecret = key:
    let lower = lib.toLower (builtins.toString key);
    in builtins.any (part: stringContains part lower) secretKeyParts;

  safeValue =
    value:
    if builtins.isAttrs value then
      builtins.listToAttrs (
        map
          (
            key: {
              name = key;
              value = if keyIsSecret key then "<redacted>" else safeValue value.${key};
            }
          )
          (sortedAttrNames value)
      )
    else if builtins.isList value then
      map safeValue value
    else
      value;

  firstAttr =
    values:
    let attrs = builtins.filter builtins.isAttrs values;
    in if attrs == [ ] then { } else builtins.head attrs;

  sourceClasses =
    meta:
    if builtins.isAttrs (meta.sourceClasses or null) then
      safeValue meta.sourceClasses
    else
      let
        aliases = {
          userIntent = [ "userIntent" "userIntentSource" "intent" "intentSource" ];
          publicInventory = [
            "publicInventory"
            "publicInventorySource"
            "inventory"
            "inventorySource"
          ];
          protectedInventory = [ "protectedInventory" "protectedInventorySource" ];
          runtimeFacts = [ "runtimeFacts" "runtimeFactSet" "runtimeFactSource" ];
          validationContext = [
            "validationContext"
            "validationContextFacts"
            "validationContextSource"
          ];
        };

        firstPresent = keys:
          let present = builtins.filter (key: builtins.hasAttr key meta) keys;
          in if present == [ ] then null else builtins.head present;
      in
      builtins.listToAttrs (
        builtins.filter (entry: entry != null) (
          map
            (
              sourceClass:
              let key = firstPresent aliases.${sourceClass};
              in
              if key == null then
                null
              else
                {
                  name = sourceClass;
                  value = safeValue meta.${key};
                }
            )
            (sortedAttrNames aliases)
        )
      );

  upstreamLocks = meta:
    safeValue (
      firstAttr [
        (meta.locks or null)
        (meta.lock or null)
        (meta.lockedToolChain or null)
        (meta.toolChainLocks or null)
        (meta.flakeLocks or null)
      ]
    );

  rendererLockSummary =
    repoRoot:
    let
      lockPath = "${repoRoot}/flake.lock";
    in
    if !(builtins.pathExists (builtins.toPath lockPath)) then
      { available = false; }
    else
      let
        lock = builtins.fromJSON (builtins.readFile (builtins.toPath lockPath));
        nodes = if builtins.isAttrs (lock.nodes or null) then lock.nodes else { };
        lockKeys = [
          "type"
          "owner"
          "repo"
          "rev"
          "narHash"
          "lastModified"
        ];
        nodeSummary = name:
          let
            locked = nodes.${name}.locked or { };
            presentKeys = builtins.filter (key: builtins.hasAttr key locked) lockKeys;
          in
          {
            inherit name;
            value = builtins.listToAttrs (
              map (key: { name = key; value = locked.${key}; }) presentKeys
            );
          };
      in
      {
        available = true;
        nodes = builtins.listToAttrs (
          builtins.filter (entry: entry.value != { }) (
            map nodeSummary (sortedAttrNames nodes)
          )
        );
      };

  derivedScope =
    { deploymentHostNames
    , normalizedRuntimeTargets
    , renderSites
    ,
    }:
    let
      targetNames = sortedAttrNames normalizedRuntimeTargets;
      siteNames = sortedAttrNames renderSites;
      enterprises = lib.unique (
        builtins.filter (value: value != null) (
          map
            (
              name:
              let logical = normalizedRuntimeTargets.${name}.logicalNode or { };
              in logical.enterprise or null
            )
            targetNames
        )
      );
    in
    lib.optionalAttrs (enterprises != [ ]) { inherit enterprises; }
    // lib.optionalAttrs (siteNames != [ ]) { sites = siteNames; }
    // lib.optionalAttrs (targetNames != [ ]) { runtimeTargets = targetNames; }
    // lib.optionalAttrs (deploymentHostNames != [ ]) { targetHosts = deploymentHostNames; }
    // lib.optionalAttrs (targetNames != [ ] || deploymentHostNames != [ ]) { derivedFromInput = true; };

  missingSourceClasses = classes:
    let
      required = [ "userIntent" "publicInventory" "protectedInventory" ];
      optional = [ "runtimeFacts" "validationContext" ];
    in
    (builtins.filter (name: !(builtins.hasAttr name classes)) required)
    ++ (map (name: "${name}:not-declared") (builtins.filter (name: !(builtins.hasAttr name classes)) optional));
in
{
  inherit safeValue;

  build =
    { repoRoot
    , controlPlane
    , metadataSourcePaths
    , deploymentHostNames
    , normalizedRuntimeTargets
    , renderSites
    ,
    }:
    let
      meta = if builtins.isAttrs (controlPlane.meta or null) then controlPlane.meta else { };
      requested = firstAttr [
        (meta.requested or null)
        (meta.request or null)
      ];
      derived = derivedScope {
        inherit deploymentHostNames normalizedRuntimeTargets renderSites;
      };
      scope = firstAttr [
        (requested.scope or null)
        (meta.requestedScope or null)
        derived
      ];
      target = firstAttr [
        (requested.target or null)
        (meta.requestedTarget or null)
        {
          renderer = "nixos";
          role = "renderer-output";
          derivedFromRenderer = true;
        }
      ];
      classes = sourceClasses meta;
      baseline = meta.controlledBaseline or meta.sourceBaseline or null;
    in
    {
      renderer = {
        name = "network-renderer-nixos";
        schemaVersion = 1;
      };
      input = {
        kind = "control-plane-model";
        path = metadataSourcePaths.cpmPath or null;
        controlPlaneModelVersion = controlPlane.version or null;
      };
      output = {
        kind = "nixos-dry-config";
        artifact = "90-dry-config.json";
        companionArtifacts = [
          "10-metadata.json"
          "11-source-paths.json"
          "30-hosts.json"
          "31-nodes.json"
          "32-containers.json"
          "90-render.json"
        ];
      };
      sources = {
        sourceClasses = classes;
        missingSourceClasses = missingSourceClasses classes;
      };
      requested = {
        scope = safeValue scope;
        target = safeValue target;
        derivedScope = safeValue derived;
      };
      locks = {
        upstream = upstreamLocks meta;
        renderer = rendererLockSummary repoRoot;
      };
      redaction = {
        protectedValues = "redacted";
      };
    }
    // lib.optionalAttrs (baseline != null) {
      controlledBaseline = safeValue baseline;
    };
}
