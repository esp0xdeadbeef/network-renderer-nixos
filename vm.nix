{
  pkgs,
  ...
}:
let
  input = import ./vm-input-home.nix;

  system = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";

  renderer = (builtins.getFlake (toString ./.)).libBySystem.${system};

  vm = renderer.vm.build {
    inherit (input)
      intentPath
      inventoryPath
      ;
    boxName = input.boxName or null;
  };
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
  ];

  system.stateVersion = "25.11";

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
