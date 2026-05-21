{}:

let
  enabled = builtins.getEnv "S88_RENDER_TRACE" == "1";
in
{
  emit =
    label: value:
    if enabled then builtins.trace "s88-render-trace ${label}" value else value;
}
