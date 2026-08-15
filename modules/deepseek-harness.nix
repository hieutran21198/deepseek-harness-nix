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
    getExe
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    optionals
    escapeShellArgs
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
      type = types.nullOr types.str;
      default = null;
      description = ''
        Overrides the `DSH_HOME` directory used to store profiles and user
        data. When null, the harness default (`~/.dsh`) is used.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

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
        Environment = optionals (cfg.dshHome != null) [ "DSH_HOME=${cfg.dshHome}" ];
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
        EnvironmentVariables = optionalAttrs (cfg.dshHome != null) {
          DSH_HOME = cfg.dshHome;
        };
      };
    };
  };
}
