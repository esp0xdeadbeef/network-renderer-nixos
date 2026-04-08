{ lib }:
valueOrPath:
if builtins.isPath valueOrPath then
  import valueOrPath
else if builtins.isString valueOrPath then
  if valueOrPath == "" then
    { }
  else if builtins.match ".*\\.json$" valueOrPath != null then
    builtins.fromJSON (builtins.readFile valueOrPath)
  else
    import valueOrPath
else
  valueOrPath
