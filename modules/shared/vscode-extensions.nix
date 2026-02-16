{ pkgs, ... }:

let
  inherit (pkgs.vscode-utils) extensionFromVscodeMarketplace extensionsFromVscodeMarketplace;

  programmingLanguages = {
    elm = {
      nixpkgs = with pkgs.vscode-extensions; [
        elmtooling.elm-ls-vscode
      ];
      marketplace = [
        {
          name = "vscode-test-explorer";
          publisher = "hbenl";
          version = "2.22.1";
          sha256 = "sha256-+vW/ZpOQXI7rDUAdWfNOb2sAGQQEolXjSMl2tc/Of8M=";
        }
        {
          name = "test-adapter-converter";
          publisher = "ms-vscode";
          version = "0.2.1";
          sha256 = "sha256-gyyl379atZLgtabbeo26xspdPjLvNud3cZ6kEmAbAjU=";
        }
      ];
    };

    alloy = {
      nixpkgs = [
      ];
      marketplace = [
      ];
      custom = [
        # Custom Alloy extension with updated JAR file (Alloy 6.2.0)
        # After changing this extension, you need to manually update ~/.vscode/extensions/extensions.json:
        # 1. Build: nix run .#private  (or: nix run .#work)
        # 2. Find new path: readlink ~/.vscode/extensions/usabarashi.alloy-custom
        # 3. Quit VSCode: Cmd+Q
        # 4. Backup: cp ~/.vscode/extensions/extensions.json /tmp/extensions.json.backup
        # 5. Update extensions.json: Edit the entry with id "usabarashi.alloy-custom" to use new version and path
        # 6. Restart VSCode
        (
          let
            alloyJar = pkgs.fetchurl {
              url = "https://github.com/AlloyTools/org.alloytools.alloy/releases/download/v6.2.0/org.alloytools.alloy.dist.jar";
              sha256 = "13dpxl0ri6ldcaaa60n75lj8ls3fmghw8d8lqv3xzglkpjsir33b";
            };
            originalExtension = extensionFromVscodeMarketplace {
              name = "alloy";
              publisher = "ArashSahebolamri";
              version = "0.7.1";
              sha256 = "sha256-svHFOCEDZHSLKzLUU2ojDVkbLTJ7hJ75znWuBV5GFQM=";
            };
          in
          pkgs.stdenv.mkDerivation {
            pname = "vscode-extension-alloy-custom";
            version = "6.2.0";

            src = originalExtension;

            nativeBuildInputs = [ pkgs.jq ];

            installPhase = ''
              runHook preInstall

              mkdir -p $out/share/vscode/extensions/usabarashi.alloy-custom
              cp -r share/vscode/extensions/ArashSahebolamri.alloy/* $out/share/vscode/extensions/usabarashi.alloy-custom/

              cd $out/share/vscode/extensions/usabarashi.alloy-custom

              if [ -f package.json ]; then
                jq '.name = "alloy-custom" | .publisher = "usabarashi" | .displayName = "Alloy (Custom)" | .version = "6.2.0"' package.json > package.json.tmp
                mv package.json.tmp package.json
              fi

              if [ -f org.alloytools.alloy.dist.jar ]; then
                cp ${alloyJar} org.alloytools.alloy.dist.jar
              fi

              runHook postInstall
            '';

            passthru = {
              vscodeExtUniqueId = "usabarashi.alloy-custom";
              vscodeExtPublisher = "usabarashi";
              vscodeExtName = "alloy-custom";
            };

            meta = {
              description = "Alloy Extension (Custom Build with Alloy 6.2.0)";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.all;
            };
          }
        )
      ];
    };
  };

  collectExtensions =
    group:
    let
      nixpkgs = group.nixpkgs or [ ];
      marketplace = group.marketplace or [ ];
      custom = group.custom or [ ];
    in
    nixpkgs
    ++ (if marketplace != [ ] then extensionsFromVscodeMarketplace marketplace else [ ])
    ++ custom;

in
{
  inherit
    programmingLanguages
    collectExtensions
    ;
}
