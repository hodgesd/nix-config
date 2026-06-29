{
  inputs,
  outputs,
  ...
}: let
  helpers = import ./helpers.nix {inherit inputs outputs;};
  machines = import ./machines.nix;
in {
  inherit
    (helpers)
    mkDarwin
    ;

  # Export machine metadata for reference
  inherit machines;
}
