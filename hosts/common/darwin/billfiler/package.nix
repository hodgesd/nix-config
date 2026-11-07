# hosts/common/darwin/billfiler/package.nix
# The billfiler CLI, plus the SwiftBar plugin patched to find it.
#
# Deliberately callPackage-able and free of any darwin assumption, so it can
# be built and its suite run on Linux -- which is the only way to exercise the
# tests without a Mac:
#
#   nix build --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage ./hosts/common/darwin/billfiler/package.nix { src = (builtins.getFlake (toString ./.)).inputs.billfiler; }'
#
# The module beside this file is what scopes it to darwin.
{
  lib,
  fetchPypi,
  ocrmypdf,
  poppler-utils,
  python3Packages,
  src,
  version ? "0.1.0",
}: let
  py = python3Packages;

  # Not in nixpkgs (checked 2026-11-01). Only the four runtime dependencies
  # are wired up: billfiler reads PDFs through poppler's pdftotext, so none of
  # invoice2data's OCR, pdfminer, camelot or dateparser extras apply.
  invoice2data = py.buildPythonPackage rec {
    pname = "invoice2data";
    version = "1.0.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-2Y3Ut/NjiMBEuK5TyC3kpQRU7t/2YI+dPNzyu/UsSDI=";
    };

    # mypy is a build input only because upstream requires it unconditionally.
    # The mypyc compilation it exists for stays off: that is gated behind
    # INVOICE2DATA_COMPILE_MYPYC, which we do not set.
    build-system = [py.setuptools py.mypy py.click py.pyyaml py.regex];
    dependencies = [py.click py.python-dateutil py.pyyaml py.regex];

    # Upstream's suite wants the OCR extras and a corpus of sample invoices
    # the sdist does not ship. pythonImportsCheck is the useful part here.
    doCheck = false;
    pythonImportsCheck = ["invoice2data"];
  };
in
  py.buildPythonApplication {
    pname = "billfiler";
    inherit src version;
    pyproject = true;

    build-system = [py.hatchling];
    dependencies = [invoice2data py.pyyaml py.weasyprint];

    # pdftotext is how every template reads a PDF, and a launchd agent
    # inherits almost no environment. Carrying poppler on the wrapper's own
    # PATH is why the agents in default.nix need no PATH of their own, and why
    # `billfiler doctor` reports both tools present under nix.
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath [poppler-utils ocrmypdf]}"
    ];

    # The suite builds its own PDF fixtures with reportlab and reads them back
    # with pdftotext, so both are needed to run it. It covers the parsing,
    # naming, indexing and analysis; none of the macOS integration.
    nativeCheckInputs = [py.pytestCheckHook py.reportlab poppler-utils];

    postInstall = ''
      # The menu bar plugin is a thin shim: SwiftBar's python3 has no PyYAML,
      # so the plugin shells out to this CLI for the whole menu. Its first
      # candidate is a pipx path that does not exist under nix, and SwiftBar
      # does not inherit the user's PATH, so point it at this store path.
      # --replace-fail so an upstream refactor of find_cli() fails the build
      # instead of shipping a plugin stuck on "billfiler not found".
      install -Dm755 plugin/bills.4h.py $out/share/billfiler/bills.4h.py
      substituteInPlace $out/share/billfiler/bills.4h.py \
        --replace-fail 'os.path.expanduser("~/.local/bin/billfiler")' "\"$out/bin/billfiler\""
    '';

    meta = {
      description = "Drop-and-forget household statement archiver, indexer and analyser";
      homepage = "https://github.com/hodgesd/billfiler";
      mainProgram = "billfiler";
    };
  }
