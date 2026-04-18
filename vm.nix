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
    if builtins.pathExists candidate then candidate else ./vm-input.nix;

  vmInput = import vmInputPath;

  testingSpoofedHostHeadersEnabled =
    if vmInput ? testingSpoofedHostHeadersEnabled then
      vmInput.testingSpoofedHostHeadersEnabled
    else
      false;

  boxName = vmInput.boxName;

  system = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";

  renderer = (builtins.getFlake (toString ./.)).libBySystem.${system};

  vmBuild = renderer.vm.build {
    intentPath = vmInput.intentPath;
    inventoryPath = vmInput.inventoryPath;
    inherit boxName;
    simulatedContainerDefaults = {
      autoStart = true;
      privateNetwork = true;
    };
  };
in
{
  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"
    vmBuild.artifactModule
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

  networking.hostName = vmBuild.boxName;
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.nftables.enable = false;
  networking.firewall.enable = false;

  systemd.network.enable = true;
  systemd.network.netdevs = vmBuild.renderedNetdevs;
  systemd.network.networks = vmBuild.renderedNetworks;

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

  containers = vmBuild.renderedContainers;
}
