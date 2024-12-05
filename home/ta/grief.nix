{ ... }:
{
  imports = [
    #
    # ========== Required Configs ==========
    #
    common/core

    #
    # ========== Host-specific Optional Configs ==========
    #
    common/optional/sops.nix
    common/optional/helper-scripts

    #common/optional/desktops
  ];

  services.yubikey-touch-detector.enable = true;
}
