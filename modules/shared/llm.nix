{
  pkgs,
  lib,
  config,
  homeDirectory,
  ...
}:

let
  llamaCpp = pkgs.llama-cpp.override {
    cpuArchDynamicDispatch = false;
    blasSupport = true;
  };

  # Built at nix build time — store paths baked in, no TCC issues.
  # Must be executable in store (SwiftBar calls store path directly via plugin's SWITCH_TO)
  switchTo = pkgs.runCommandLocal "switch-to.sh" { } ''
    cp ${
      pkgs.replaceVars ../../config/llama-server/switch-to.sh {
        llamaServer = "${llamaCpp}/bin/llama-server";
      }
    } "$out"
    chmod +x "$out"
  '';

  plugin = pkgs.replaceVars ../../config/swiftbar/llama-server.5s.sh {
    switchTo = "${switchTo}";
  };

  swiftbarPackages = [ pkgs.swiftbar ];
  swiftbarDirectories = [
    "${homeDirectory}/Library/Logs/swiftbar"
    "${homeDirectory}/Library/Application Support/SwiftBar/Plugins"
  ];
in

{
  home = {
    packages = [ llamaCpp ] ++ swiftbarPackages;

    activation.createLlmDirectories = config.lib.dag.entryAfter [ "writeBoundary" ] (
      lib.concatLines (
        (map (d: "run mkdir -p '${d}'") [
          "${homeDirectory}/.cache/llama-server"
          "${homeDirectory}/.cache/llama-server/models"
          "${homeDirectory}/.cache/llama-server-slots"
        ])
        ++ (map (d: "run mkdir -p '${d}'") swiftbarDirectories)
      )
    );

    file = {
      ".config/llama-server/switch-to.sh" = {
        source = switchTo;
        executable = true;
      };
      "Library/Application Support/SwiftBar/Plugins/llama-server.5s.sh" = {
        source = plugin;
        executable = true;
      };
    };
  };

}
