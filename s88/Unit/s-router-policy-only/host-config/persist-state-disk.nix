# ./persist-state-disk.nix
{
  lib,
  pkgs,
  config,
  ...
}:

let
  dev = "/dev/vdb";
  opts = "noatime,compress=zstd";
in
{

  ##########################################################################
  # Kernel / initrd support
  ##########################################################################
  boot.supportedFilesystems = [ "btrfs" ];
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  environment.systemPackages = [
    pkgs.btrfs-progs
    pkgs.util-linux
  ];

  ##########################################################################
  # INITRD: format + mount (runs before stage-2-init / impermanence)
  ##########################################################################

  boot.initrd.systemd.services.format-persist-state = {
    description = "Format /dev/vdb as btrfs if empty (initrd)";
    wantedBy = [ "initrd-fs-pre.target" ];
    before = [ "initrd-fs.target" ];
    after = [ "dev-vdb.device" ];
    unitConfig.DefaultDependencies = false;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "format-persist-state-initrd" ''
        set -euo pipefail
        dev=${dev}

        # If any FS exists, never touch it
        if ${pkgs.util-linux}/bin/blkid "$dev" >/dev/null 2>&1; then
          exit 0
        fi

        echo "initrd: formatting $dev as btrfs" >&2
        ${pkgs.btrfs-progs}/bin/mkfs.btrfs -f "$dev"
      '';
    };
  };

  boot.initrd.systemd.mounts = [
    {
      what = dev;
      where = "/persist-state";
      type = "btrfs";
      options = opts;
      wantedBy = [ "initrd-fs.target" ];
      before = [ "initrd-fs.target" ];
      after = [
        "dev-vdb.device"
        "format-persist-state.service"
      ];
    }
  ];

  ##########################################################################
  # REAL SYSTEM: mount again (in case helper nukes fileSystems)
  ##########################################################################

  systemd.mounts = [
    {
      what = dev;
      where = "/persist-state";
      type = "btrfs";
      options = opts;
      wantedBy = [ "local-fs.target" ];
      before = [ "local-fs.target" ];
      after = [
        "dev-vdb.device"
        "format-persist-state.service"
      ];
    }
  ];

  ##########################################################################
  # NORMAL BOOT: format fallback (if initrd not used)
  ##########################################################################

  systemd.services.format-persist-state = {
    description = "Format /dev/vdb as btrfs if empty";
    wantedBy = [ "local-fs-pre.target" ];
    before = [ "local-fs.target" ];
    after = [ "dev-vdb.device" ];
    unitConfig.DefaultDependencies = false;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "format-persist-state" ''
        set -euo pipefail
        dev=${dev}
        if ${pkgs.util-linux}/bin/blkid "$dev" >/dev/null 2>&1; then exit 0; fi
        ${pkgs.btrfs-progs}/bin/mkfs.btrfs -f "$dev"
      '';
    };
  };

  ##########################################################################
  # Ensure base dirs exist (after mount)
  ##########################################################################
  systemd.tmpfiles.rules = [
    "d /persist-state 0755 root root -"
    "d /persist-state/var 0755 root root -"
    "d /persist-state/var/lib 0711 root root -"
    "d /persist-state/var/lib/containers 0711 root root -"
    "d /persist-state/var/lib/docker 0711 root root -"
  ];
}
