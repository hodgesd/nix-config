# lib/machines.nix
# Machine metadata registry for all systems. Reaches every module as the
# `machine` specialArg (hostname injected by lib/helpers.nix). Fields:
#   type       "darwin" | "nixos"
#   formFactor "laptop" | "desktop" | "server" | "vm"
#   primaryUse free-form ("development", "server", "homelab", ...)
#   chip       optional (omit for VMs)
#   username   optional, defaults to "hodgesd"
# Only add a field once a module reads it.
{
  # Darwin machines
  mbp = {
    type = "darwin";
    chip = "m3-pro";
    formFactor = "laptop";
    primaryUse = "development";
    screen = "14\"";
  };

  mini = {
    type = "darwin";
    username = "derrickhodges";
    chip = "m2-pro";
    formFactor = "desktop";
    primaryUse = "server";
  };

  # Local AI inference server (see docs/studio/). primaryUse = "server" is
  # deliberate rather than a new "ai" role: it reuses the existing
  # `primaryUse != "server"` gates, so studio skips masApps, the t3-code
  # cask and the agent-workbench client for free. Studio-only behavior
  # branches on `machine.hostname == "studio"`.
  studio = {
    type = "darwin";
    chip = "m5-ultra";
    formFactor = "desktop";
    primaryUse = "server";
  };

  # NixOS machines
  nixos-infra = {
    type = "nixos";
    formFactor = "vm";
    primaryUse = "homelab";
    # No chip: QEMU guest on the HP mini PC's Proxmox host.
  };

  t3-code = {
    type = "nixos";
    formFactor = "vm";
    primaryUse = "development";
    # No chip: QEMU guest on the HP mini PC's Proxmox host.
  };

  air = {
    type = "darwin";
    chip = "m1";
    formFactor = "laptop";
    primaryUse = "development";
    screen = "13\"";
  };
}
