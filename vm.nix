{
  config,
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

  enterpriseName = vmInput.enterpriseName;
  siteName = vmInput.siteName;
  requestedBoxName = vmInput.boxName;

  system = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";
  renderer = (builtins.getFlake (toString ./.)).libBySystem.${system};

  renderedVm = renderer.vm.build {
    intentPath = vmInput.intentPath;
    inventoryPath = vmInput.inventoryPath;
    boxName = requestedBoxName;
    simulatedContainerDefaults = {
      autoStart = true;
      privateNetwork = true;
    };
  };

  artifactRootHostDrv =
    pkgs.runCommand
      "network-renderer-nixos-vm-artifacts-${
        builtins.replaceStrings [ "." ":" "/" "@" ] [ "-" "-" "-" "-" ] enterpriseName
      }-${builtins.replaceStrings [ "." ":" "/" "@" ] [ "-" "-" "-" "-" ] siteName}"
      { }
      ''
        mkdir -p "$out/${enterpriseName}/${siteName}"
        cp -R ${vmInput.inventoryPath} "$out/${enterpriseName}/${siteName}/inventory.nix"
        cp -R ${vmInput.intentPath} "$out/${enterpriseName}/${siteName}/intent.nix"
      '';

  artifactRootHost = "${artifactRootHostDrv}";
in
{
  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"
    renderedVm.artifactModule
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

  networking.hostName = renderedVm.boxName;
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.nftables.enable = false;
  networking.firewall.enable = false;

  systemd.network.enable = true;
  systemd.network.netdevs = renderedVm.renderedNetdevs;
  systemd.network.networks = renderedVm.renderedNetworks;

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

  environment.etc."network-artifacts-source".source = artifactRootHost;

  containers = lib.mapAttrs (
    _: container:
    container
    // {
      bindMounts = (container.bindMounts or { }) // {
        "/etc/network-artifacts-source" = {
          hostPath = artifactRootHost;
          isReadOnly = true;
        };
      };
    }
  ) renderedVm.renderedContainers;
}
