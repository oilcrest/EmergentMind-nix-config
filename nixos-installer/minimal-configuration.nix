{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "modules/common/host-spec.nix"
      "hosts/common/users/primary"
      "hosts/common/users/primary/nixos.nix"
    ])
  ];

  hostSpec = {
    isMinimal = lib.mkForce true;
    username = "ta";
  };

  users.users.${config.hostSpec.username}.password = lib.mkForce "nixos";
  # Adding this whole set explicitly for the iso so it doesn't barf about sops being non-existent
  #  users.users.${config.hostSpec.username} = {
  #    isNormalUser = true;
  #    password = lib.mkForce "nixos";
  #    extraGroups = [ "wheel" ];
  #  };
  #
  #  # root's ssh key are mainly used for remote deployment
  #  users.extraUsers.root = {
  #    inherit (config.users.users.${config.hostSpec.username}) password;
  #    openssh.authorizedKeys.keys =
  #      config.users.users.${config.hostSpec.username}.openssh.authorizedKeys.keys;
  #  };

  fileSystems."/boot".options = [ "umask=0077" ]; # Removes permissions and security warnings.
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot = {
    enable = true;
    # we use Git for version control, so we don't need to keep too many generations.
    configurationLimit = lib.mkDefault 3;
    # pick the highest resolution for systemd-boot's console.
    consoleMode = lib.mkDefault "max";
  };
  boot.initrd.systemd.enable = true;

  networking = {
    # configures the network interface(include wireless) via `nmcli` & `nmtui`
    networkmanager.enable = true;
  };

  services = {
    qemuGuest.enable = true;
    openssh = {
      enable = true;
      ports = [ 22 ];
      settings.PermitRootLogin = "yes";
    };
  };

  # allow sudo over ssh with yubikey
  security.pam = {
    sshAgentAuth.enable = true;
    services.sudo = {
      u2fAuth = true;
      sshAgentAuth = true;
    };
  };

  environment.systemPackages = builtins.attrValues { inherit (pkgs) wget curl rsync; };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    warn-dirty = false;
  };
  system.stateVersion = "23.11";
}
