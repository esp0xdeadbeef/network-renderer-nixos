{ lib
, pkgs
, modulesPath
, ...
}:

# NOTE: vm.nix is a testing-only harness. Do not use as a production deployment path.
# Updated (CMC-NIXOS-REMOVE-INTENT-INVENTORY): no longer uses buildHostFromPaths.
# Requires CPM output path via vmInput.cpmPath instead of intentPath/inventoryPath.
# The pipeline (compiler→NFM→CPM) should be run by the test harness, not this file.

let
  vmInputPath =
    let
      candidate = ./vm-input-test.nix;
    in
    if builtins.pathExists candidate then
      candidate
    else if builtins.pathExists ./vm-input-home.nix then
      ./vm-input-home.nix
    else
      throw "network-renderer-nixos: missing vm input file (expected ./vm-input-test.nix or ./vm-input-home.nix)";

  vmInput = import vmInputPath;

  testingSpoofedHostHeadersEnabled =
    if vmInput ? testingSpoofedHostHeadersEnabled then
      vmInput.testingSpoofedHostHeadersEnabled
    else
      false;

  boxName = vmInput.boxName;

  flake = builtins.getFlake (toString ./.);
  api = flake.lib;

  # CPM is required — the VM harness no longer discovers intent/inventory from disk.
  # The caller (vm-input-*.nix) must provide either:
  #   cpmPath: path to pre-built CPM JSON output, OR
  #   cpm: already-loaded CPM output
  resolvedCpm =
    if vmInput ? cpm then
      vmInput.cpm
    else if vmInput ? cpmPath then
      api.renderer.loadControlPlane vmInput.cpmPath
    else
      throw "network-renderer-nixos: vm input must define 'cpm' or 'cpmPath' (CPM output). Per FS-310-HDS-010-SDS-010-SMS-100, renderers consume ONLY CPM output.";

  resolvedInventory =
    if vmInput ? inventory then
      vmInput.inventory
    else
      { };

  hostBuild = api.renderer.buildHostFromControlPlane {
    controlPlaneOut = resolvedCpm;
    selector = boxName;
    inventory = resolvedInventory;
  };

  renderedHost = hostBuild.renderedHost;
in
{
  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  warnings = [
    "network-renderer-nixos: vm.nix is a testing-only harness."
    "network-renderer-nixos: selected vm input path: ${toString vmInputPath}"
    "network-renderer-nixos: do not use vm.nix as a production deployment path."
  ]
  ++ lib.optional testingSpoofedHostHeadersEnabled "network-renderer-nixos: spoofed host headers are enabled for this VM harness.";

  system.stateVersion = "25.11";

  boot.loader.grub.enable = false;
  boot.isContainer = false;

  networking.hostName = boxName;
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.nftables.enable = false;
  networking.firewall.enable = false;

  systemd.network.enable = true;
  systemd.network.netdevs = renderedHost.netdevs or { };
  systemd.network.networks = renderedHost.networks or { };

  virtualisation = {
    memorySize = 4096;
    cores = 4;
    graphics = false;
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
    vmVariant = {
      virtualisation = {
        memorySize = 4096;
        cores = 4;
        graphics = false;
        forwardPorts = [
          {
            from = "host";
            host.port = 2222;
            guest.port = 22;
          }
        ];
      };
    };
  };

  users.mutableUsers = false;
  users.users.root = {
    initialHashedPassword = "";
    shell = pkgs.bashInteractive;
    ignoreShellProgramCheck = true;
  };

  programs.bash.enable = true;
  programs.zsh.enable = false;

  services.getty.autologinUser = "root";
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    bashInteractive
    git
    jq
    vim
    iproute2
    iputils
    tcpdump
    curl
  ];

  containers = renderedHost.containers or { };

  environment.etc."network-artifacts/compiler.json".text = builtins.toJSON hostBuild.compilerOut;
  environment.etc."network-artifacts/forwarding.json".text = builtins.toJSON hostBuild.forwardingOut;
  environment.etc."network-artifacts/control-plane.json".text =
    builtins.toJSON hostBuild.controlPlaneOut;
}
