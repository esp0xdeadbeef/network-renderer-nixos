{
  boxName = "s-router-test";

  testingSpoofedHostHeadersEnabled = true;

  cpmPath =
    let
      raw = builtins.getEnv "NETWORK_CPM_OUTPUT";
    in
    if raw == "" then
      throw "network-renderer-nixos: set NETWORK_CPM_OUTPUT to the pre-built control-plane JSON for the VM harness"
    else
      /. + raw;

  inventory = { };
}
