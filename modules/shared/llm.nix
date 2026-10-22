{
  pkgs,
  lib,
  config,
  homeDirectory,
  ...
}:

let
  llamaCpp =
    (pkgs.llama-cpp.override {
      cpuArchDynamicDispatch = false;
      blasSupport = true;
    }).overrideAttrs
      (old: {
        # nixpkgs' llama-cpp sets `GGML_METAL_DEVICES=0` in preCheck, which in
        # llama.cpp v0.6.0 makes the test process register zero Metal devices
        # (the variable is the device *count*, not an index). Disabling
        # cpuArchDynamicDispatch (GGML_BACKEND_DL=OFF) additionally makes
        # upstream build test-metal-graph-optimize, which requires a GPU device
        # and aborts on `GGML_ASSERT(device)`. Skip that test, since the nixpkgs
        # check environment deliberately runs without a GPU.
        disabledTests = (old.disabledTests or [ ]) ++ [ "test-metal-graph-optimize" ];
      });

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
      ".config/llama-server/webui-defaults.json" = {
        source = ../../config/llama-server/webui-defaults.json;
      };
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
