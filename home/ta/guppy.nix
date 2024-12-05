{ ... }:
{
  imports = [
    #
    # ========== Required Configs ==========
    #
    common/core
  ];

  services.yubikey-touch-detector.enable = true;
}
