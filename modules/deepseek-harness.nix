{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.deepseek-harness;

  inherit (lib)
    concatLists
    escapeShellArg
    escapeShellArgs
    getExe
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    optionals
    types
    ;

  command = escapeShellArgs (
    [
      (getExe cfg.package)
      "web"
      "--host"
      cfg.host
      "--port"
      (toString cfg.port)
    ]
    ++ optionals (cfg.trustedHosts != [ ]) (
      concatLists (
        map (h: [
          "--trusted-host"
          h
        ]) cfg.trustedHosts
      )
    )
    ++ cfg.extraArgs
  );

  launchdArgs = [
    (getExe cfg.package)
    "web"
    "--host"
    cfg.host
    "--port"
    (toString cfg.port)
  ]
  ++ optionals (cfg.trustedHosts != [ ]) (
    concatLists (
      map (h: [
        "--trusted-host"
        h
      ]) cfg.trustedHosts
    )
  )
  ++ cfg.extraArgs;

  settingsFile = (pkgs.formats.yaml { }).generate "settings.yaml" cfg.settings;

  desktopLauncher = pkgs.writeShellScript "deepseek-harness-desktop" ''
    export DSH_HOST=${escapeShellArg cfg.host}
    export DSH_PORT=${toString cfg.port}
    exec ${getExe cfg.desktop.package}
  '';
in
{
  options.services.deepseek-harness = {
    enable = mkEnableOption "the DeepSeek Harness (dsh) web UI";

    package = mkOption {
      type = types.package;
      # No default here: the flake's homeManagerModules entry injects the
      # matching package via lib.mkDefault. When importing this module
      # directly, set this option explicitly.
      description = "The deepseek-harness package to use.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address the web UI binds to.";
    };

    port = mkOption {
      type = types.port;
      default = 3080;
      description = "Port the web UI listens on; use 0 to let the OS pick a free port.";
    };

    trustedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "localhost"
        "myhost.local:3080"
      ];
      description = "Extra authorities accepted by the /api browser-trust fence.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "--patch"
        "/path/to/overlay.yaml"
      ];
      description = "Extra arguments passed through to `dsh web`.";
    };

    dshHome = mkOption {
      type = types.str;
      default = "${config.xdg.configHome}/deepseek-harness";
      defaultText = "\${config.xdg.configHome}/deepseek-harness";
      example = "~/.dsh";
      description = ''
        The `DSH_HOME` directory used to store profiles, settings, and user
        data. Defaults to an XDG config directory so the declarative
        {option}`services.deepseek-harness.settings` document (written to
        `settings.yaml` inside this directory) is picked up by the harness.
      '';
    };

    environmentFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "/run/user/1000/secrets/dsh.env"
      ];
      description = ''
        Environment files sourced into the service environment, typically
        produced by sops-nix or agenix. On Linux these map to systemd's
        `EnvironmentFile`; launchd has no native equivalent, so this option
        is ignored on macOS.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      example = lib.literalExpression ''
        {
          models = {
            provider = "deepseek";
            apiKey = "DEEPSEEK_API_KEY";
          };
          telemetry = { mode = "off"; };
        }
      '';
      description = ''
        Declarative harness settings, rendered to YAML and written to
        `settings.yaml` inside {option}`services.deepseek-harness.dshHome`.
        Top-level keys are setting namespaces (for example `models`,
        `credentials`, `telemetry`). Secret values should be references to
        environment-variable names (such as `DEEPSEEK_API_KEY`) supplied
        through {option}`services.deepseek-harness.environmentFiles`.

        The generated file is a read-only symlink into the Nix store, so
        settings changed through the Web UI are not persisted and are reset
        on the next activation.
      '';
    };

    desktop = {
      enable = mkEnableOption "the DeepSeek Harness desktop application (a Tauri window wrapping the web UI)";

      package = mkOption {
        type = types.package;
        # No default here: the flake's homeManagerModules entry injects the
        # matching package via lib.mkDefault. When importing this module
        # directly, set this option explicitly.
        description = "The deepseek-harness desktop package to use.";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      home.packages = [ cfg.package ];

      home.file."${cfg.dshHome}/settings.yaml" = mkIf (cfg.settings != { }) {
        source = settingsFile;
      };

      warnings = optionals (cfg.environmentFiles != [ ] && pkgs.stdenv.hostPlatform.isDarwin) [
        "services.deepseek-harness.environmentFiles is ignored on macOS: launchd does not support environment files."
      ];

      systemd.user.services.deepseek-harness = {
        Unit = {
          Description = "DeepSeek Harness web UI";
          After = [ "network.target" ];
          Wants = [ "network.target" ];
        };

        Service = {
          ExecStart = command;
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [ "DSH_HOME=${cfg.dshHome}" ];
          EnvironmentFile = cfg.environmentFiles;
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      launchd.agents.deepseek-harness = {
        enable = true;
        config = {
          Label = "deepseek-harness";
          ProgramArguments = launchdArgs;
          RunAtLoad = true;
          KeepAlive = {
            SuccessfulExit = false;
          };
          ProcessType = "Interactive";
          EnvironmentVariables = {
            DSH_HOME = cfg.dshHome;
          };
        };
      };
    })

    (mkIf cfg.desktop.enable {
      home.packages = [ cfg.desktop.package ];

      xdg.dataFile."icons/hicolor/scalable/apps/deepseek-harness.svg".source =
        ../assets/deepseek-harness.svg;

      xdg.desktopEntries.deepseek-harness = {
        name = "DeepSeek Harness";
        genericName = "Agent Harness";
        comment = "Open the DeepSeek Harness web UI";
        exec = "${desktopLauncher}";
        icon = "deepseek-harness";
        terminal = false;
        categories = [
          "Office"
        ];
      };
    })
  ];
}
