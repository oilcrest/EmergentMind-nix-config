# User config applicable only to nixos
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  hostSpec = config.hostSpec;
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;

  #FIXME:(sops) sops-nix apparently works with darwin now so can probably move this, and password entries for user and root below to default.nix
  # Decrypt password to /run/secrets-for-users/ so it can be used to create the user
  sopsHashedPasswordFile = lib.optionalString (
    !config.hostSpec.isMinimal
  ) config.sops.secrets."passwords/${hostSpec.username}".path;
in
{
  users.mutableUsers = false; # Only allow declarative credentials; Required for password to be set via sops during system activation!
  users.users.${hostSpec.username} = {
    home = "/home/${hostSpec.username}";
    isNormalUser = true;
    hashedPasswordFile = sopsHashedPasswordFile; # Blank if sops is not working.
    # These gets overridden if sops is working; only used with nixos-installer. For some reason, password sticking so using hashedPassword instead.
    hashedPassword = "$y$j9T$Ac.m5IZ6ku/nrqK9K9kBi1$lRHp3Xg4Vk7Ly/VAiv5d839VlwDRNt2w9ACMMKe8kR2";
    # password = lib.mkForce "nixos";

    extraGroups = lib.flatten [
      "wheel"
      (ifTheyExist [
        "audio"
        "video"
        "docker"
        "git"
        "networkmanager"
        "scanner" # for print/scan"
        "lp" # for print/scan"
      ])
    ];
  };

  # No matter what environment we are in we want these tools for root, and the user(s)
  programs.git.enable = true;

  # root's ssh key are mainly used for remote deployment, borg, and some other specific ops
  users.users.root = {
    shell = pkgs.zsh;
    hashedPasswordFile = config.users.users.${hostSpec.username}.hashedPasswordFile;
    hashedPassword = config.users.users.${hostSpec.username}.hashedPassword; # This gets overridden if sops is working; it is only used if the hostSpec.hostName == "iso"
    # password = lib.mkForce config.users.users.${hostSpec.username}.password; # This gets overridden if sops is working; it is only used if the hostSpec.hostName == "iso"
    # root's ssh keys are mainly used for remote deployment.
    openssh.authorizedKeys.keys = config.users.users.${hostSpec.username}.openssh.authorizedKeys.keys;
  };
}
// lib.optionalAttrs (inputs ? "home-manager") {

  # Setup p10k.zsh for root
  home-manager.users.root = lib.optionalAttrs (!hostSpec.isMinimal) {
    home.stateVersion = "23.05"; # Avoid error
    programs.zsh = {
      enable = true;
      plugins = [
        {
          name = "powerlevel10k-config";
          src = lib.custom.relativeToRoot "home/${hostSpec.username}/common/core/zsh/p10k";
          file = "p10k.zsh";
        }
      ];
    };
  };
}
