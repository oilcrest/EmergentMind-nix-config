#NOTE: This ISO is NOT minimal. It uses the `hostSpec.isMinimal = false` value because we don't want a minimal
# environment when using the iso for recovery purposes.
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = lib.flatten [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    #"${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
    # This is overkill but I want my core home level utils if I need to use the iso environment for recovery purpose
    inputs.home-manager.nixosModules.home-manager
    (map lib.custom.relativeToRoot [
      "modules/common/host-spec.nix"
      "hosts/common/users/primary/default.nix"
      "hosts/common/users/primary/nixos.nix"
    ])
  ];

  hostSpec = {
    hostName = "iso";
    username = "ta";
    isProduction = lib.mkForce false;

    # Needed because we don't use host/common/core for iso
    networking = inputs.nix-secrets.networking;
    domain = inputs.nix-secrets.domain;

    #TODO: This is stuff for home/ta/common/core/git.nix. should create home/ta/common/optional/development.nix so core git.nix doesn't use it.
    handle = "emergentmind";
    email.gitHub = inputs.nix-secrets.email.gitHub;
  };

  # The default compression-level is (6) and takes too long on some machines (>30m). 3 takes <2m
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  nixpkgs = {
    hostPlatform = lib.mkDefault "x86_64-linux";
    config.allowUnfree = true;
  };

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  services = {
    qemuGuest.enable = true;
    openssh = {
      ports = [ config.hostSpec.networking.ports.tcp.ssh ];
      settings.PermitRootLogin = lib.mkForce "yes";
    };
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    supportedFilesystems = lib.mkForce [
      "btrfs"
      "vfat"
    ];
  };

  networking = {
    hostName = "iso";
  };

  systemd = {
    services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
    # gnome power settings to not turn off screen
    targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };
  };
}
