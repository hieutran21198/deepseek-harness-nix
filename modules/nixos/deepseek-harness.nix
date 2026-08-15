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
    escapeShellArgs
    getExe
    hasPrefix
    mkEnableOption
    mkIf
    mkOption
    optionals
    removePrefix
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

  settingsFile = (pkgs.formats.yaml { }).generate "settings.yaml" cfg.settings;
in
{
  options.services.deepseek-harness = {
    enable = mkEnableOption "the DeepSeek Harness (dsh) web UI";

    package = mkOption {
      type = types.package;
      # No default here: the flake's nixosModules entry injects the matching
      # package via lib.mkDefault. When importing this module directly, set
      # this option explicitly.
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
      default = "/var/lib/deepseek-harness";
      description = ''
        The `DSH_HOME` directory used to store profiles, settings, and user
        data. When it lives under `/var/lib`, a matching systemd
        `StateDirectory` is declared so the service user can write to it.
      '';
    };

    environmentFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "/run/secrets/deepseek-harness.env"
      ];
      description = ''
        Environment files sourced into the service environment, typically
        produced by sops-nix or agenix (systemd `EnvironmentFile`).
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

    openFirewall = mkEnableOption "opening the web UI port in the firewall";
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.deepseek-harness = {
      description = "DeepSeek Harness web UI";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      wants = [ "network.target" ];

      preStart = mkIf (cfg.settings != { }) ''
        ln -sfn ${settingsFile} "${cfg.dshHome}/settings.yaml"
      '';

      serviceConfig = {
        ExecStart = command;
        WorkingDirectory = cfg.dshHome;
        Environment = [ "DSH_HOME=${cfg.dshHome}" ];
        EnvironmentFile = cfg.environmentFiles;
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        StateDirectory = mkIf (hasPrefix "/var/lib/" cfg.dshHome) (removePrefix "/var/lib/" cfg.dshHome);

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
