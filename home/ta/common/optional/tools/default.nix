{ pkgs, ... }:
{
  #imports = [ ./foo.nix ];

  home.packages = builtins.attrValues {
    inherit (pkgs)
      # Development
      tokei

      # Device imaging
      rpi-imager
      #etcher #was disabled in nixpkgs due to dependency on insecure version of Electron

      # Productivity
      grimblast
      #drawio #temporarily moved to stable because of build issue waiting for lock on this package for 20+mins
      libreoffice

      # Privacy
      #veracrypt
      #keepassxc

      # Web sites
      zola

      # Media production
      audacity
      blender
      gimp
      inkscape
      obs-studio
      # VM and RDP
      # remmina
      ;

    inherit (pkgs.stable)
      drawio
      ;
  };
  #Disabled for now. grimblast
  #  services.flameshot = {
  #      enable = true;
  #     package = flameshotGrim;
  #  };
}
