{
  inputs,
  outputs,
  stateVersion,
  ...
}: let
  helpers = import ./helpers.nix {inherit inputs outputs stateVersion;};
  machines = import ./machines.nix;
in {
  inherit
    (helpers)
    mkDarwin
    mkNixos
    ;

  # Export machine metadata for reference
  inherit machines;
}
