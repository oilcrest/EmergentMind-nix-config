# IMPORTANT: This is used by NixOS and nix-darwin so options must exist in both!
{
  inputs,
  outputs,
  config,
  lib,
  pkgs,
  isDarwin,
  ...
}:
let

  #TODO: primaryUser* bindings should maybe be assigned values elsewhere but are
  # needed for imports instead of using hostSpec to avoid infinite recursion
  primaryUser = "ta";
  primaryUserHandle = "emergentmind";
  platform = if isDarwin then "darwin" else "nixos";
  platformModules = "${platform}Modules";
in
{
  imports = lib.flatten [
    inputs.home-manager.${platformModules}.home-manager
    inputs.sops-nix.${platformModules}.sops

    (map lib.custom.relativeToRoot [
      "modules/common"
      "modules/${platform}"
      "hosts/common/core/${platform}.nix"
      "hosts/common/core/sops.nix"
      #"hosts/common/core/services" #not used yet
      "hosts/common/users/${primaryUser}"
      "hosts/common/users/${primaryUser}/${platform}.nix"
    ])
  ];

  #
  # ========== Core Host Specifications ==========
  #
  hostSpec = {
    username = primaryUser;
    handle = primaryUserHandle;
    inherit (inputs.nix-secrets)
      domain
      email
      userFullName
      networking
      ;
  };

  networking.hostName = config.hostSpec.hostName;

  # Force home-manager to use global packages
  home-manager.useGlobalPkgs = true;
  # If there is a conflict file that is backed up, use this extension
  home-manager.backupFileExtension = "bk";
  # home-manager.useUserPackages = true;

  #
  # ========== Overlays ==========
  #
  nixpkgs = {
    overlays = [
      outputs.overlays.default
    ];
    config = {
      allowUnfree = true;
    };
  };

  #
  # ========== Nix Nix Nix ==========
  #
  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # See https://jackson.dev/post/nix-reasonable-defaults/
      connect-timeout = 5;
      log-lines = 25;
      min-free = 128000000; # 128MB
      max-free = 1000000000; # 1GB

      trusted-users = [ "@wheel" ];
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
      warn-dirty = false;

      allow-import-from-derivation = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  #
  # ========== Basic Shell Enablement ==========
  #
  # On darwin it's important this is outside home-manager
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    promptInit = "source ''${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
  };
}
