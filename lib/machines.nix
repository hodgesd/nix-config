# lib/machines.nix
# Machine metadata registry for all systems
{
  # Darwin machines
  mbp = {
    hostname = "mbp";
    type = "darwin";
    chip = "m3-pro";
    formFactor = "laptop";
    primaryUse = "development";
    specs = {
      ram = "18GB";
      storage = "1TB";
      cpu = 12;
      gpu = 18;
    };
    screen = "14\"";
  };

  mini = {
    hostname = "mini";
    type = "darwin";
    chip = "m2-pro";
    formFactor = "desktop";
    primaryUse = "server";
    specs = {
      ram = null;
      storage = null;
      cpu = null;
      gpu = null;
    };
  };

  air = {
    hostname = "air";
    type = "darwin";
    chip = "m1";
    formFactor = "laptop";
    primaryUse = "development";
    specs = {
      ram = "16GB";
      storage = "500GB";
      cpu = 8;
      gpu = 7;
    };
    screen = "13\"";
  };

  # NixOS machines
  desktop = {
    hostname = "desktop";
    type = "nixos";
    formFactor = "desktop";
    primaryUse = "workstation";
  };

  ktz-cloud = {
    hostname = "ktz-cloud";
    type = "nixos";
    formFactor = "server";
    primaryUse = "cloud";
  };

  morphnix = {
    hostname = "morphnix";
    type = "nixos";
    formFactor = "server";
    primaryUse = "server";
  };

  nix-dev = {
    hostname = "nix-dev";
    type = "nixos";
    formFactor = "server";
    primaryUse = "development";
  };

  nvllama = {
    hostname = "nvllama";
    type = "nixos";
    formFactor = "server";
    primaryUse = "ai-inference";
  };

}
