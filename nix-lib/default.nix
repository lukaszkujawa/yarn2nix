{ lib, pkgs }:

let
  # Build an attrset of node dependencies suitable for the `nodeBuildInputs`
  # argument of `buildNodePackage`. The input is the path of a dependency
  # file generated by the `yarn2nix` utility from a `yarn.lock` file,
  # in turn the output of the `yarn` tool for an npm package.
  buildNodeDeps = lockDotNix: lib.fix
    (lib.extends
      (import lockDotNix { inherit (pkgs) fetchurl fetchgit; })
      (self: {
        # wrap the invocation in the fix point, to construct the
        # list of { name, drv } needed by buildNodePackage
        # from the templates.
        # It is basically a manual paramorphism, carrying parts of the
        # information of the previous layer (the original package name).
        _buildNodePackage = { name, ... }@args:
          { inherit name; drv = buildNodePackage args; };
      }));

  # Build a package template generated by the `yarn2nix --template`
  # utility from a yarn package. The first input is the path to the
  # template nix file, the second input is all node dependencies
  # needed by the template, in the form generated by `buildNodeDeps`.
  callTemplate = yarn2nixTemplate: allDeps:
    pkgs.callPackage yarn2nixTemplate {
      inherit buildNodePackage removePrefixes;
    } allDeps;


  buildNodePackage = import ./buildNodePackage.nix {
    inherit linkNodeDeps;
    inherit (pkgs) stdenv nodejs;
  };

  # Link together a `node_modules` folder that can be used
  # by npm’s module system to call dependencies.
  # Also link executables of all dependencies into `.bin`.
  # TODO: copy manpages & docs as well
  # type: String -> ListOf { name: String, drv : Drv } -> Drv
  linkNodeDeps = name: packageDeps:
    pkgs.runCommand (name + "-node_modules") {} ''
      mkdir -p $out/.bin
      ${lib.concatMapStringsSep "\n"
        (dep: ''
          echo "linking node dependency ${dep.name}"
          ln -sT ${dep.drv} "$out/${dep.name}"
          ${ # TODO: remove static building once RPATHs are fixed
             pkgs.haskell.lib.justStaticExecutables
               pkgs.haskellPackages.yarn2nix}/bin/setup-node-package-paths \
            bin \
            --to=$out/.bin \
            --package=$out/${dep.name}
        '')
        packageDeps}
    '';

  # Filter out files/directories with one of the given prefix names
  # from the given path.
  # type: ListOf File -> Path -> Drv
  removePrefixes = prfxs: path:
    let
      hasPrefix = file: prfx: lib.hasPrefix ((builtins.toPath path) + "/" + prfx) file;
      hasAnyPrefix = file: lib.any (hasPrefix file) prfxs;
    in
      builtins.filterSource (file: _: ! (hasAnyPrefix file)) path;

in {
  inherit buildNodeDeps callTemplate removePrefixes;
}
