{
  lib,
  config,
  pkgs,
  ...
}:

{

  nixpkgs.hostPlatform = "x86_64-linux";

  # cores, disk and mem:
  virtualisation = {
    cores = 42;
    memorySize = 40 * 1024;
    diskSize = 20 * 1024;
  };
  # Network settings:
  virtualisation.qemu.networkingOptions = [
    "-nic none"
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
  ];

  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/persist" = "/persist/vm-persists/${config.networking.hostName}";
    };
  };
}
