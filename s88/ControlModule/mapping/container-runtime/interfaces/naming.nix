{ lib }:

let
  interfaceNameMaxLength = 15;

  semanticTokenAliases = {
    upstream = "up";
    downstream = "down";
    selector = "sel";
    policy = "pol";
    access = "acc";
    management = "mgmt";
    overlay = "ovly";
    east = "e";
    west = "w";
    north = "n";
    south = "s";
    uplink = "up";
    isp = "isp";
  };

  nonDistinctContainerTokens = [ "s" "router" "network" "container" ];

  validInterfaceName =
    name: builtins.isString name && name != "" && builtins.stringLength name <= interfaceNameMaxLength;

  aliasToken = token: if builtins.hasAttr token semanticTokenAliases then semanticTokenAliases.${token} else token;

  truncateToken =
    maxLen: token:
    let tokenLen = builtins.stringLength token;
    in if tokenLen <= maxLen then token else builtins.substring 0 maxLen token;

  semanticTokensForName =
    name: map aliasToken (lib.filter (token: token != "") (lib.splitString "-" name));

  compactSemanticName =
    { name, maxLen, fallback, removeTokens ? [ ] }:
    let
      allTokens = semanticTokensForName name;
      preferredTokens = lib.filter (token: !(builtins.elem token removeTokens)) allTokens;
      selectedTokens = if preferredTokens != [ ] then preferredTokens else allTokens;
      compact = lib.concatStringsSep "" (map (truncateToken 3) selectedTokens);
      normalized = if compact != "" then compact else fallback;
    in
    if builtins.stringLength normalized <= maxLen then normalized else builtins.substring 0 maxLen normalized;

  uniqueInterfaceNameCandidate =
    baseName: index:
    if index <= 1 then
      baseName
    else
      let
        suffix = "-${toString index}";
        prefixLen = interfaceNameMaxLength - builtins.stringLength suffix;
        prefix = if prefixLen > 0 then builtins.substring 0 prefixLen baseName else builtins.substring 0 1 baseName;
      in
      "${prefix}${suffix}";

  resolveUniqueInterfaceName =
    { baseName, usedNames, index ? 1 }:
    let candidate = uniqueInterfaceNameCandidate baseName index;
    in
    if !(builtins.hasAttr candidate usedNames) then
      candidate
    else
      resolveUniqueInterfaceName { inherit baseName usedNames; index = index + 1; };

  assignUniqueName =
    field: outputField: entries:
    (builtins.foldl'
      (
        acc: entry:
        let
          baseName = entry.value.${field};
          resolvedName = resolveUniqueInterfaceName {
            inherit baseName;
            usedNames = acc.usedNames;
          };
        in
        {
          usedNames = acc.usedNames // { ${resolvedName} = true; };
          entries = acc.entries ++ [
            (entry // { value = entry.value // { ${outputField} = resolvedName; }; })
          ];
        }
      )
      { usedNames = { }; entries = [ ]; }
      entries).entries;
in
rec {
  inherit validInterfaceName;

  semanticBaseInterfaceName =
    desiredInterfaceName:
    let
      rawTokens = lib.filter (token: token != "") (lib.splitString "-" desiredInterfaceName);
      aliasedTokens = map aliasToken rawTokens;
      candidateNames = [
        desiredInterfaceName
        (lib.concatStringsSep "-" aliasedTokens)
        (lib.concatStringsSep "-" (map (truncateToken 4) aliasedTokens))
        (lib.concatStringsSep "-" (map (truncateToken 3) aliasedTokens))
        (lib.concatStringsSep "" (map (truncateToken 1) aliasedTokens))
        (builtins.substring 0 interfaceNameMaxLength desiredInterfaceName)
      ];
      validNames = lib.filter validInterfaceName candidateNames;
    in
    if validNames != [ ] then
      builtins.head validNames
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: could not derive a valid container interface name

        desiredInterfaceName:
        ${builtins.toJSON desiredInterfaceName}
      '';

  semanticHostVethBaseName =
    { containerName, desiredInterfaceName, adapterName ? null }:
    let
      adapterTokenSource = if builtins.isString adapterName && adapterName != "" then adapterName else desiredInterfaceName;
      containerToken = compactSemanticName {
        name = containerName;
        maxLen = 4;
        fallback = "unit";
        removeTokens = nonDistinctContainerTokens;
      };
      interfaceToken = compactSemanticName { name = adapterTokenSource; maxLen = 6; fallback = "if"; };
      hashSuffix = builtins.substring 0 3 (builtins.hashString "sha256" "${containerName}:${desiredInterfaceName}:${adapterTokenSource}");
    in
    "${containerToken}-${interfaceToken}-${hashSuffix}";

  assignUniqueContainerInterfaceNames = assignUniqueName "containerInterfaceBaseName" "containerInterfaceName";

  assignUniqueHostVethNames =
    entries:
    let
      candidates = lib.filter (entry: !(entry.value.usePrimaryHostBridge or false)) entries;
      resolved = assignUniqueName "hostVethBaseName" "hostVethName" candidates;
      resolvedByIfName = builtins.listToAttrs (map (entry: { name = entry.ifName; value = entry; }) resolved);
    in
    map (
      entry:
      if entry.value.usePrimaryHostBridge or false then
        entry
      else
        let resolvedEntry = resolvedByIfName.${entry.ifName};
        in resolvedEntry // { value = resolvedEntry.value // { hostInterfaceName = resolvedEntry.value.hostVethName; }; }
    ) entries;
}
