{
  description = "StoryGraph KOReader plugin — dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.permittedInsecurePackages = [ "openssl-1.1.1w" ];
        };

        koreader = pkgs.callPackage ./packages/koreader.nix { };

        koreaderFrontendPath = "${koreader}/lib/koreader/frontend";

        # Dev launcher: symlinks the plugin into KO_HOME, then runs KOReader.
        # Avoids rebuilding the koreader derivation on every source change.
        storygraphDev = pkgs.writeShellScriptBin "dev" ''
          set -e
          REPO_ROOT="$(git rev-parse --show-toplevel)"
          PLUGIN_SRC="$REPO_ROOT"
          KO_HOME="''${KO_HOME:-$REPO_ROOT/.koreader-data}"
          PLUGIN_DIR="$KO_HOME/plugins/storygraph.koplugin"

          mkdir -p "$KO_HOME/plugins"
          rm -rf "$PLUGIN_DIR"
          mkdir -p "$PLUGIN_DIR"

          # Symlink plugin files so edits are live
          for f in "$PLUGIN_SRC"/*.lua; do
            [ -f "$f" ] && ln -sf "$f" "$PLUGIN_DIR/$(basename "$f")"
          done

          export KO_HOME
          echo "==> KO_HOME=$KO_HOME"
          echo "==> Plugin files in $PLUGIN_DIR:"
          ls -la "$PLUGIN_DIR/"
          exec ${koreader}/bin/koreader "$@"
        '';

        storygraphCheckLint = pkgs.writeShellScriptBin "check-lint" ''
          set -e
          cd "$(git rev-parse --show-toplevel)"
          exec ${pkgs.luajitPackages.luacheck}/bin/luacheck *.lua spec/unit/*.lua spec/integration/*.lua
        '';

        storygraphCheckTypes = pkgs.writeShellScriptBin "check-types" ''
          set -e
          cd "$(git rev-parse --show-toplevel)"
          exec python3 ${./ci/lua-language-server-check.py} .
        '';

        storygraphTest = pkgs.writeShellScriptBin "run-tests" ''
          set -euo pipefail
          REPO_ROOT="$(git rev-parse --show-toplevel)"
          export KOREADER_PATH="${koreader}"
          export KO_HOME="$(mktemp -d)"
          trap 'rm -rf "$KO_HOME"' EXIT
          MODE="''${1:-all}"
          echo "==> KOReader: ${koreader}"
          echo "==> Test storage: $KO_HOME"
          echo ""
          cd "$REPO_ROOT"
          if [ "$MODE" = "unit" ] || [ "$MODE" = "all" ]; then
            echo "=== Unit tests (mocked KOReader) ==="
            ${pkgs.luajitPackages.busted}/bin/busted --lua=luajit spec/unit/
            echo ""
          fi
          if [ "$MODE" = "integration" ] || [ "$MODE" = "all" ]; then
            echo "=== Integration tests (real KOReader modules) ==="
            ${pkgs.luajitPackages.busted}/bin/busted --lua=luajit spec/integration/
            echo ""
          fi
          echo "==> All tests passed."
        '';
      in {
        packages.koreader = koreader;

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            git
            lua-language-server
            luajitPackages.luacheck
            luajit
            luajitPackages.busted
            luajitPackages.luacheck
            python3
            storygraphDev
            storygraphCheckLint
            storygraphCheckTypes
            storygraphTest
          ];

          shellHook = ''
            cat > .luarc.json << 'LUACEOF'
          {
            "$schema": "https://raw.githubusercontent.com/sumneko/vscode-lua/master/setting/schema.json",
            "diagnostics.globals": [
              "G_reader_settings",
              "G_defaults",
              "logger",
              "UIManager",
              "InputContainer",
              "InfoMessage",
              "NetworkMgr",
              "socket",
              "describe",
              "it",
              "before_each",
              "after_each",
              "assert"
            ],
            "workspace.library": [
              "''${3rd}/busted/library",
              "${koreaderFrontendPath}"
            ],
            "runtime.version": "LuaJIT",
            "diagnostics.neededFileStatus": {
              "codestyle-check": "Any"
            }
          }
          LUACEOF

            echo "StoryGraph KOReader plugin devShell activated."
            echo "  dev          — launch KOReader with the plugin loaded"
            echo "  check-lint   — run luacheck on *.lua"
            echo "  check-types  — run lua-language-server diagnostics"
            echo "  run-tests    — run test suite (unit, integration, or all)"
          '';
        };
      }
    );
}
