{config, ...}: {
  # Quick Look syntax highlighting for source files (.py etc.) comes from the
  # `syntax-highlight` cask (sbarex) declared in ../homebrew.nix. It ships a
  # Quick Look *app extension*, and macOS only registers those when the host
  # app is launched once — a freshly (re)installed cask therefore previews
  # as plain text until someone opens the app and toggles it on under
  # System Settings > General > Login Items & Extensions > Quick Look.
  #
  # pluginkit state is per-user, so this runs from Home Manager's activation
  # (as the user), which nix-darwin sequences after the homebrew activation
  # that installs the bundle. Both calls are idempotent: `-a` on an
  # already-known appex is a no-op, `-e use` just re-asserts enabled.
  #
  # Deliberately NOT auto-reinstalling when the bundle is missing: brew's
  # receipt still says installed (seen on mbp and mini, 2026-09-02), and a
  # `brew reinstall` inside activation would put a network download on the
  # switch path — exactly the failure mode ../homebrew.nix warns about.
  home-manager.users.${config.majordouble.user} = {
    home.activation.registerSyntaxHighlightQuickLook = ''
      appex="/Applications/Syntax Highlight.app/Contents/PlugIns/Syntax Highlight Quick Look Extension.appex"
      if [ -e "$appex" ]; then
        run /usr/bin/pluginkit -a "$appex" \
          || echo "pluginkit -a failed for Syntax Highlight (non-fatal)"
        run /usr/bin/pluginkit -e use -i org.sbarex.SourceCodeSyntaxHighlight.QuickLookExtension \
          || echo "pluginkit -e use failed for Syntax Highlight (non-fatal)"
      else
        echo "WARNING: Syntax Highlight.app bundle missing but cask receipt present;" \
          "run: brew reinstall --cask syntax-highlight"
      fi
    '';
  };
}
