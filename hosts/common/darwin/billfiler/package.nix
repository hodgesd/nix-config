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
  stdenv,
  version ? "0.1.0",
}: let
  py = python3Packages;

  # Don't run weasyprint's OWN 4000-test suite on macOS. Nobody else does
  # either: cache.nixos.org 404s for aarch64-darwin and 200s for x86_64-linux,
  # so Hydra's darwin build does not pass, and every Mac build here pays to
  # discover that again.
  #
  # Two different failures, which is the point -- one is a wrong expectation,
  # the other is not a test bug at all:
  #   - tests/draw/test_text.py::test_unicode_range asserts an exact pixel
  #     colour and gets red where it wants white, because font fallback for a
  #     codepoint outside the declared unicode-range resolves differently on
  #     macOS. nixpkgs already disables test_font_stretch two lines up for
  #     this reason ("needs the Ahem font (fails on macOS)") and missed this.
  #   - tests/test_html.py::test_no_ph segfaulted the interpreter (exit 139) on
  #     one runner while the SAME derivation hash built clean on two others
  #     minutes apart. Naming tests cannot fix a nondeterministic native crash;
  #     the next one would just land somewhere else.
  #
  # Note what `doCheck = false` really does here: in nixpkgs' python infra
  # doCheck is already false and `doInstallCheck` is what carries
  # pytestCheckHook, so this flips doInstallCheck and takes weasyprint's
  # pythonImportsCheck and versionCheckHook down with the suite.
  #
  # That is acceptable because billfiler's own suite is the better check and
  # already runs on these same Macs: its tests import weasyprint and render a
  # report, and all 196 passed on aarch64-darwin in CI. A real use of the
  # library on the target platform beats an import check of it.
  #
  # Darwin only, deliberately. Overriding unconditionally would change the
  # derivation on Linux too and throw away a cached build to dodge failures
  # that do not happen there, where the suite passes and is already built.
  weasyprint =
    if stdenv.hostPlatform.isDarwin
    then py.weasyprint.overridePythonAttrs {doCheck = false;}
    else py.weasyprint;

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
    dependencies = [invoice2data py.pyyaml weasyprint];

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
