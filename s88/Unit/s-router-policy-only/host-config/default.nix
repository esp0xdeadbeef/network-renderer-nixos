# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  name,
  outPath,
  ...
}:
{
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/nixos):
    # outputs.nixosModules.example
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    # inputs.nvf.nixosModules.default
    # inputs.nixvim.nixosModules.nixvim
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/vm-storage-persist.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/debug-packages.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/ssh-auth.nix"
    "${outPath}/library/01-general/desktop/shell-env.nix"
    ./vm-settings.nix
    ./restart-container.nix
    ./network.nix
    ./network-tenant-vlans.nix
    ./ssh.nix
    ./impermanence.nix
    ./persist-state-disk.nix
  ];

  networking.hostName = name;

  sops.defaultSopsFile = "${outPath}/secrets/${config.networking.hostName}.yaml";
  # This will automatically import SSH keys as age keys
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  # This is using an age key that is expected to already be in the filesystem
  # sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  # This will generate a new key if the key specified above does not exist
  #sops.age.generateKey = true;
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";
  # This is the actual specification of the secrets.
  # sops.secrets.example-key = { };
  # sops.secrets."myservice/my_subdir/my_secret" = { };

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        # Enable flakes and new 'nix' command
        experimental-features = "nix-command flakes";
        # Opinionated: disable global registry
        flake-registry = "";
        # Workaround for https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;
      };
      # Opinionated: disable channels
      channel.enable = false;

      # Opinionated: make flake registry and nix path match flake inputs
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  # FIXME: Add the rest of your current configuration

  # networking.networkmanager.enable = true;
  time.timeZone = "Europe/Amsterdam";

  #networking.networkmanager.enable = true;
  # unlock gnome shit at unlock:
  security.pam.services.login.enableGnomeKeyring = true;
  environment.interactiveShellInit = ''
    ZSH_THEME=alanpeabody

  '';

  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true; # make it available before the user is created
  };
  # TODO: Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    # FIXME: Replace with your username
    deadbeef = {
      # TODO: You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!

      # initialPassword = " ";
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;

      isNormalUser = true;
      # TODO: Be sure to add any other groups you need (such as networkmanager, audio, docker, etc)
      extraGroups = [ "wheel" ];
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
