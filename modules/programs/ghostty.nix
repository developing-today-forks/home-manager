{ config, lib, pkgs, ... }:
let
  cfg = config.programs.ghostty;
  keyValueSettings = {
    listsAsDuplicateKeys = true;
    mkKeyValue = lib.generators.mkKeyValueDefault { } " = ";
  };
  keyValue = pkgs.formats.keyValue keyValueSettings;
in {
  meta.maintainers = [ lib.maintainers.HeitorAugustoLN ];

  options.programs.ghostty = {
    enable = lib.mkEnableOption "ghostty";

    package = lib.mkPackageOption pkgs "ghostty" { };

    settings = lib.mkOption {
      inherit (keyValue) type;
      default = { };
      example = lib.literalExpression ''
        {
          theme = "catppuccin-mocha";
          font-size = 10;
        }
      '';
      description = ''
        Configuration written to {file}`$XDG_CONFIG_HOME/ghostty/config`.

        See <https://ghostty.org/docs/config/reference> for more information.
      '';
    };

    themes = lib.mkOption {
      type = lib.types.attrsOf keyValue.type;
      default = { };
      example = {
        catppuccin-mocha = {
          palette = [
            "0=#45475a"
            "1=#f38ba8"
            "2=#a6e3a1"
            "3=#f9e2af"
            "4=#89b4fa"
            "5=#f5c2e7"
            "6=#94e2d5"
            "7=#bac2de"
            "8=#585b70"
            "9=#f38ba8"
            "10=#a6e3a1"
            "11=#f9e2af"
            "12=#89b4fa"
            "13=#f5c2e7"
            "14=#94e2d5"
            "15=#a6adc8"
          ];
          background = "1e1e2e";
          foreground = "cdd6f4";
          cursor-color = "f5e0dc";
          selection-background = "353749";
          selection-foreground = "cdd6f4";
        };
      };
      description = ''
        Custom themes written to {file}`$XDG_CONFIG_HOME/ghostty/themes`.

        See <https://ghostty.org/docs/features/theme#authoring-a-custom-theme> for more information.
      '';
    };

    clearDefaultKeybinds = lib.mkEnableOption "" // {
      description = "Whether to clear default keybinds.";
    };

    installBatSyntax =
      lib.mkEnableOption "installation of ghostty configuration syntax for bat"
      // {
        default = true;
      };

    installVimSyntax = lib.mkEnableOption
      "installation of ghostty configuration syntax for vim/neovim";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [ cfg.package ];

      programs.ghostty.settings = lib.mkIf cfg.clearDefaultKeybinds {
        keybind = lib.mkBefore [ "clear" ];
      };

      xdg.configFile = lib.mkMerge [
        {
          "ghostty/config" = lib.mkIf (cfg.settings != { }) {
            source = keyValue.generate "ghostty-config" cfg.settings;
          };
        }

        (lib.mkIf (cfg.themes != { }) (lib.mapAttrs' (name: value: {
          name = "ghostty/themes/${name}";
          value.source = keyValue.generate "ghostty-${name}-theme" value;
        }) cfg.themes))
      ];
    }
    (lib.mkIf cfg.installBatSyntax {
      programs.bat = {
        syntaxes.ghostty = {
          src = cfg.package;
          file = "share/bat/syntaxes/ghostty.sublime-syntax";
        };
        config.map-syntax = [ "*/ghostty/config:Ghostty Config" ];
      };
    })
    (lib.mkIf cfg.installVimSyntax {
      programs.vim.plugins = [ cfg.package.vim ];
      programs.neovim.plugins = [ cfg.package.vim ];
    })
  ]);
}
