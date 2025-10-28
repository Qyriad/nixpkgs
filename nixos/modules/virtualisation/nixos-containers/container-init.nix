{
  replaceVarsWith,
  runtimeShell,
  containerConfig,
}: replaceVarsWith {
  src = ./container-init.bash;

  replacements = {
    inherit runtimeShell;
    handleExtraVeths = containerConfig.extraVethsRendered;
  };

  name = "container-init-stage2";
  dir = "bin";
  isExecutable = true;
  meta.mainProgram = "container-init-stage2";
}
