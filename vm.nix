{
  lib,
  pkgs,
  modulesPath,
  ...
}:

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

  haveBuildPaths = vmInput ? intentPath && vmInput ? inventoryPath;

  _requireBuildPaths =
    if haveBuildPaths then
      true
    else
      throw "network-renderer-nixos: vm input must define (intentPath + inventoryPath) (the VM harness does not accept raw CPM-only inputs)";

  hostBuild = api.renderer.buildHostFromPaths {
    selector = boxName;
    intentPath = vmInput.intentPath;
    inventoryPath = vmInput.inventoryPath;
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
