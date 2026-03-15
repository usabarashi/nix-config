{ config, pkgs, ... }:
let
  dockerCompose = pkgs.callPackage ../../packages/docker-compose/default.nix { inherit pkgs; };
in
{
  home.packages = with pkgs; [
    colima
    docker
  ];

  # Colima Settings
  #
  # - Volume Permission
  # ```~/.lima/_config/override.yaml
  # mountType: 9p
  # mounts:
  # - location: "/Users/USER_NAME"
  #   writable: true
  #   9p:
  #   securityModel: mapped-xattr
  #   cache: mmap
  # - location: "~"
  #   writable: true
  #   9p:
  #   securityModel: mapped-xattr
  #   cache: mmap
  # - location: /tmp/colima
  #   writable: true
  #   9p:
  #   securityModel: mapped-xattr
  #   cache: mmap
  # ```
  #
  # - Network Permission
  # ```
  # colima start --network-address --mount-inotify
  # ```

  # see: https://docs.docker.jp/compose/install/compose-plugin.html#compose-install-the-plugin-manually
  home.activation.dockerComposeConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    echo "Setting Docker Compose Plugin configuration..."
    mkdir -p ${config.home.homeDirectory}/.docker/cli-plugins
    rm -f ${config.home.homeDirectory}/.docker/cli-plugins/docker-compose
    ln -s ${dockerCompose}/cli-plugins/docker-compose ${config.home.homeDirectory}/.docker/cli-plugins/docker-compose
  '';
}
