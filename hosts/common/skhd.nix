# hosts/common/skhd.nix
{ config, lib, pkgs, ... }:

{
  services.skhd.enable = true;

  # MacOS Bundle ID List:  https://nikitabobko.github.io/AeroSpace/goodies
	
  home-manager.users.hodgesd = {
    home.file.".skhdrc".text = ''
      hyper - s : open -a "Safari"
      hyper - d : open -a "Drafts"
      hyper - c : open -a "ChatGPT"
      hyper - t : open -a "Warp"
      hyper - p : open -a "PyCharm"
      hyper - f : open -a "Finder"
      hyper - m : open -b com.apple.MobileSMS
    '';
  };
}
