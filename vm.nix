{
  pkgs,
  ...
}:
let
  input = import ./vm-input-home.nix;

  system = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";

  renderer = (builtins.getFlake (toString ./.)).libBySystem.${system};

  testingSpoofedHostHeadersEnabled =
    if input ? testingSpoofedHostHeadersEnabled then input.testingSpoofedHostHeadersEnabled else false;

  _requireExplicitTestingOptIn =
    if testingSpoofedHostHeadersEnabled then
      true
    else
      throw ''
        network-renderer-nixos: vm.nix test harness requires explicit testing opt-in for spoofed host headers
        Set `testingSpoofedHostHeadersEnabled = true;` in the selected vm-input file.
        This path is for testing only and must not be used as production configuration.
      '';

  vm = builtins.seq _requireExplicitTestingOptIn (
    renderer.vm.build {
      inherit (input)
        intentPath
        inventoryPath
        ;
      boxName = input.boxName or null;
    }
  );
in
{
  imports = [ vm.artifactModule ];

  assertions = [
    {
      assertion = input.intentPath != null;
      message = "vm-input.nix requires intentPath";
    }
    {
      assertion = input.inventoryPath != null;
      message = "vm-input.nix requires inventoryPath";
    }
    {
      assertion = vm.boxName != null;
      message = "vm-input.nix requires a resolved boxName";
    }
    {
      assertion = testingSpoofedHostHeadersEnabled == true;
      message = "vm.nix is a testing-only harness using spoofed host headers; set testingSpoofedHostHeadersEnabled = true explicitly";
    }
  ];

  warnings = [
    "network-renderer-nixos: vm.nix is a testing-only harness."
    "network-renderer-nixos: spoofed host headers are enabled for this VM harness."
    "network-renderer-nixos: do not use vm.nix as a production deployment path."
  ];

  system.stateVersion = "25.11";

  networking.hostName = "TEST-ONLY-SPOOFED-HOST-HEADERS";
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.netdevs = vm.renderedNetdevs;
  systemd.network.networks = vm.renderedNetworks;

  boot.enableContainers = true;
  containers = vm.renderedContainers;

  systemd.services."container@" = {
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
  };

  networking.useDHCP = true;
  services.resolved.enable = true;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };

  boot.kernelModules = [ "br_netfilter" ];

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    containerlab
    iproute2
    jq
    gron
    tmux
    neovim
    tcpdump
    traceroute
    nftables
  ];

  networking.nftables.enable = true;

  users.users.root.shell = pkgs.bash;

  virtualisation.memorySize = 1024 * 24;
  virtualisation.cores = 22;
  environment.etc.hosts.enable = false;
  services.openssh.enable = true;

  nixos-shell.mounts = {
    cache = "none";
  };
}
