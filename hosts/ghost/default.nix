#############################################################
#
#  Ghost - Main Desktop
#  NixOS running on Ryzen 5 3600X, Radeon RX 5700 XT, 64GB RAM
#
###############################################################

{
  inputs,
  lib,
  configVars,
  configLib,
  pkgs,
  ...
}:
{
  imports = lib.flatten [
    #################### Every Host Needs This ####################
    ./hardware-configuration.nix

    #################### Hardware Modules ####################
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-gpu-amd
    inputs.hardware.nixosModules.common-pc-ssd

    #################### Disk Layout ####################
    inputs.disko.nixosModules.disko
    (configLib.relativeToRoot "hosts/common/disks/ghost.nix")

    #################### Misc Inputs ####################
    inputs.stylix.nixosModules.stylix

    (map configLib.relativeToRoot [
      #################### Required Configs ####################
      "hosts/common/core"

      #################### Host-specific Optional Configs ####################
      "hosts/common/optional/services/openssh.nix" # allow remote SSH access
      "hosts/common/optional/services/printing.nix" # CUPS
      "hosts/common/optional/audio.nix" # pipewire and cli controls
      "hosts/common/optional/libvirt.nix" # vm tools
      "hosts/common/optional/gaming.nix" # steam, gamescope, gamemode, and related hardware
      "hosts/common/optional/msmtp.nix" # for sending email notifications
      "hosts/common/optional/nvtop.nix" # GPU monitor (not available in home-manager)
      "hosts/common/optional/obsidian.nix" # wiki
      "hosts/common/optional/plymouth.nix" # fancy boot screen
      "hosts/common/optional/scanning.nix" # SANE and simple-scan
      "hosts/common/optional/vlc.nix" # media player
      "hosts/common/optional/yubikey.nix" # yubikey related packages and configs
      "hosts/common/optional/zsa-keeb.nix" # Moonlander keeb flashing stuff

      #################### Desktop ####################
      "hosts/common/optional/services/greetd.nix" # display manager
      "hosts/common/optional/hyprland.nix" # window manager
      "hosts/common/optional/thunar.nix" # file manager
      "hosts/common/optional/wayland.nix" # wayland components and pkgs not available in home-manager
    ])
    #################### Ghost specific####################
    ./samba.nix

  ];

  networking = {
    hostName = "ghost";
    networkmanager.enable = true;
    enableIPv6 = false;
  };

  #FIXME:(clamav) something not working. disabled to reduce log spam
  semi-active-av.enable = false;

  services.backup = {
    enable = true;
    borgBackupStartTime = "02:00:00";
    borgServer = "${configVars.networking.subnets.oops.ip}";
    borgUser = "${configVars.username}";
    borgPort = "${builtins.toString configVars.networking.subnets.oops.port}";
    borgBackupPath = "/var/services/homes/${configVars.username}/backups";
    borgNotifyFrom = "${configVars.email.notifier}";
    borgNotifyTo = "${configVars.email.backup}";
  };

  boot.loader = {
    systemd-boot = {
      enable = true;
      # When using plymouth, initrd can expand by a lot each time, so limit how many we keep around
      configurationLimit = lib.mkDefault 10;
    };
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };

  boot.initrd = {
    systemd.enable = true;
  };

  # needed unlock LUKS on secondary drives
  # use partition UUID
  # https://wiki.nixos.org/wiki/Full_Disk_Encryption#Unlocking_secondary_drives
  environment.etc.crypttab.text = lib.optionalString (!configVars.isMinimal) ''
    cryptextra UUID=d90345b2-6673-4f8e-a5ef-dc764958ea14 /luks-secondary-unlock.key
    cryptvms UUID=ce5f47f8-d5df-4c96-b2a8-766384780a91 /luks-secondary-unlock.key
  '';

  #TODO:(stylix) move this stuff to separate file but define theme itself per host
  # host-wide styling
  stylix = {
    enable = true;
    image = /home/ta/sync/wallpaper/1126712.png;
    #      base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-medium.yaml";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    #      cursor = {
    #        package = pkgs.foo;
    #        name = "";
    #      };
    #     fonts = {
    #monospace = {
    #    package = pkgs.foo;
    #    name = "";
    #};
    #sanSerif = {
    #    package = pkgs.foo;
    #    name = "";
    #};
    #serif = {
    #    package = pkgs.foo;
    #    name = "";
    #};
    #    sizes = {
    #        applications = 12;
    #        terminal = 12;
    #        desktop = 12;
    #        popups = 10;
    #    };
    #};
    opacity = {
      applications = 1.0;
      terminal = 1.0;
      desktop = 1.0;
      popups = 0.8;
    };
    polarity = "dark";
    # program specific exclusions
    #targets.foo.enable = false;
  };
  #hyprland border override example
  #  wayland.windowManager.hyprland.settings.general."col.active_border" = lib.mkForce "rgb(${config.stylix.base16Scheme.base0E});

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.05";
}
