{ config, ... }:
{

  # Set a temp password for use by minimal builds like installer and iso
  users.users.${config.hostSpec.username} = {
    isNormalUser = true;
    hashedPassword = "$y$j9T$Ac.m5IZ6ku/nrqK9K9kBi1$lRHp3Xg4Vk7Ly/VAiv5d839VlwDRNt2w9ACMMKe8kR2";
    extraGroups = [ "wheel" ];
  };
  users.users.root = {
    hashedPassword = config.users.users.${config.hostSpec.username}.hashedPassword;
    openssh.authorizedKeys.keys =
      # root's ssh keys are mainly used for remote deployment. These will come from hosts/common/users/primary/default.nix
      config.users.users.${config.hostSpec.username}.openssh.authorizedKeys.keys;
  };
}
