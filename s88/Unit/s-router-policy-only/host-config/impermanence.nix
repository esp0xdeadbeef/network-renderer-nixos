{ config, lib, ... }:

{

  environment.persistence = {
    "/persist-state" = {
      hideMounts = true;

      # docker / podman state
      directories = [
        "/var/lib/docker"
        "/var/lib/containers"
      ];
    };

    "/persist" = {
      hideMounts = true;

      directories = [
        #"/var/lib"
        #"/var/log"
        "/var/lib/nixos"
        {
          directory = "/root/.ssh";
          user = "root";
          group = "root";
          mode = "0600";
        }
        {
          directory = "/root/.config/sops/age";
          user = "root";
          group = "root";
          mode = "0600";
        }
      ];

      files = [
        "/etc/machine-id"
      ];

      users.deadbeef = {
        directories = [
          ".ssh"
          "github"
        ];

        files = [
          ".zsh_history"
          ".zshrc"
        ];
      };
    };
  };

  # Make rootfs mostly ephemeral
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=755" ];
  };

  systemd.tmpfiles.rules = [
    "f /persist/home/deadbeef/.zshrc 0644 deadbeef users -"
  ];
}
