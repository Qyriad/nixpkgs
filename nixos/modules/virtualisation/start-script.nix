{
  lib,
  stdenv,
  nixos-container,
  replaceVarsWith,
  #runtimeShell,
  systemd,
  containerConfig,
}: let
  inherit (lib) optionalString;

  cfg = containerConfig;
  nonEmptyList = list: list != null && list != [ ];

  #containerInit = replaceVarsWith {
  #  src = ./container-init.bash;
  #  replacements = {
  #    inherit runtimeShell;
  #
  #    handleExtraVeths = cfg.extraVeths
  #    |> lib.mapAttrsToList renderExtraVeth
  #    |> lib.concatStringsSep "\n";
  #  };
  #
  #  name = "container-init-stage2";
  #  dir = "bin";
  #  isExecutable = true;
  #  meta.mainProgram = "container-init-stage2";
  #};

  #renderExtraVeth = name: cfg: ''
  #  handleExtraVeth "${name}" \
  #    "${toString cfg.localAddress}" \
  #    "${toString cfg.hostAddress}" \
  #    "${toString cfg.localAddress6}" \
  #    "${toString cfg.hostAddress6}"
  #'';
in replaceVarsWith {
  src = ./start-script.bash;
  replacements = {
    nixos_container = lib.getExe nixos-container;
    host_platform_system = stdenv.hostPlatform.system;
    extra_veths = cfg.extraVeths
    |> lib.mapAttrsToList (name: _cfg: "--network-veth-extra=${name}")
    |> lib.escapeShellArgs
    ;
    systemd_nspawn = lib.getExe' systemd "systemd-nspawn";
    link_journal_arg = optionalString cfg.ephemeral "--link-journal=try-guest";
    ephemeral_arg = optionalString cfg.ephemeral "--ephemeral";
    capability_arg = optionalString (nonEmptyList cfg.additionalCapabilities)
      ''--capability="${lib.concatStringsSep "," cfg.additionalCapabilities}"''
    ;
    tmpfs_arg = optionalString (nonEmptyList cfg.tmpfs)
      ''--tmpfs=${lib.concatStringsSep " --tmpfs=" cfg.tmpfs}''
    ;
    container_init = lib.getExe containerConfig.finalInitScript;
  };

  name = "nixos-container-start-script";
  dir = "bin";
  isExecutable = true;
  meta.mainProgram = "nixos-container-start-script";
}
