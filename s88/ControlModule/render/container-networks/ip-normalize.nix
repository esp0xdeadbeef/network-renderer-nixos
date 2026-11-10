{ lib }:
let
  stripLeadingZeros =
    hextet:
    let
      matched = builtins.match "0*([0-9a-f]+)" hextet;
    in
    if matched == null then hextet else builtins.head matched;

  hextetsOf = text: if text == "" then [ ] else lib.splitString ":" text;

  longestZeroRun =
    groups:
    let
      indices = lib.genList (index: index) (builtins.length groups);
      step =
        acc: index:
        let
          isZero = builtins.elemAt groups index == "0";
          start = if isZero && !acc.inRun then index else acc.runStart;
          length = if isZero then acc.runLength + 1 else 0;
          longer = length > acc.bestLength;
        in
        {
          inRun = isZero;
          runStart = start;
          runLength = length;
          bestLength = if longer then length else acc.bestLength;
          bestStart = if longer then start else acc.bestStart;
        };
      result = builtins.foldl' step {
        inRun = false;
        runStart = 0;
        runLength = 0;
        bestLength = 0;
        bestStart = 0;
      } indices;
    in
    if result.bestLength >= 2 then
      {
        start = result.bestStart;
        length = result.bestLength;
      }
    else
      null;

  joinHextets = groups: lib.concatStringsSep ":" groups;

  compressRun =
    groups: run:
    let
      left = lib.take run.start groups;
      right = lib.drop (run.start + run.length) groups;
    in
    if left == [ ] && right == [ ] then
      "::"
    else if left == [ ] then
      "::" + joinHextets right
    else if right == [ ] then
      joinHextets left + "::"
    else
      joinHextets left + "::" + joinHextets right;

  canonicalIpv6 =
    address:
    let
      halves = lib.splitString "::" address;
      compressed = builtins.length halves > 1;
      left = hextetsOf (builtins.head halves);
      right = if compressed then hextetsOf (builtins.elemAt halves 1) else [ ];
      missing = 8 - builtins.length left - builtins.length right;
      groups =
        if compressed then
          left ++ lib.genList (_: "0") (if missing < 0 then 0 else missing) ++ right
        else
          left;
      normalised = map (hextet: stripLeadingZeros (lib.toLower hextet)) groups;
      run = longestZeroRun normalised;
    in
    if builtins.length normalised != 8 then
      address
    else if run == null then
      joinHextets normalised
    else
      compressRun normalised run;
in
{

  canonicalAddress =
    value:
    if !(builtins.isString value) || value == "" then
      value
    else if lib.hasInfix ":" value then
      let
        parts = lib.splitString "/" value;
        address = builtins.head parts;
        suffix = if builtins.length parts > 1 then "/" + builtins.elemAt parts 1 else "";
      in
      canonicalIpv6 address + suffix
    else
      value;
}
