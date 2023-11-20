{ pkgs

# Note, this should be "the standard library" + HM extensions.
, lib ? import ../modules/lib/stdlib-extended.nix pkgs.lib

, release, isReleaseBranch }:

let

  nmdSrc = fetchTarball {
    url =
      "https://git.sr.ht/~rycee/nmd/archive/824a380546b5d0d0eb701ff8cd5dbafb360750ff.tar.gz";
    sha256 = "0vvj40k6bw8ssra8wil9rqbsznmfy1kwy7cihvm13rajwdg9ycgg";
  };

  nmd = import nmdSrc {
    inherit lib;
    # The DocBook output of `nixos-render-docs` doesn't have the change
    # `nmd` uses to work around the broken stylesheets in
    # `docbook-xsl-ns`, so we restore the patched version here.
    pkgs = pkgs // {
      docbook-xsl-ns =
        pkgs.docbook-xsl-ns.override { withManOptDedupPatch = true; };
    };
  };

  # Make sure the used package is scrubbed to avoid actually
  # instantiating derivations.
  scrubbedPkgsModule = {
    imports = [{
      _module.args = {
        pkgs = lib.mkForce (nmd.scrubDerivations "pkgs" pkgs);
        pkgs_i686 = lib.mkForce { };
      };
    }];
  };

  dontCheckDefinitions = { _module.check = false; };

  gitHubDeclaration = user: repo: subpath:
    let urlRef = if isReleaseBranch then "release-${release}" else "master";
    in {
      url = "https://github.com/${user}/${repo}/blob/${urlRef}/${subpath}";
      name = "<${repo}/${subpath}>";
    };

  hmPath = toString ./..;

  buildOptionsDocs = args@{ modules, includeModuleSystemOptions ? true, ... }:
    let options = (lib.evalModules { inherit modules; }).options;
    in pkgs.buildPackages.nixosOptionsDoc ({
      options = if includeModuleSystemOptions then
        options
      else
        builtins.removeAttrs options [ "_module" ];
      transformOptions = opt:
        opt // {
          # Clean up declaration sites to not refer to the Home Manager
          # source tree.
          declarations = map (decl:
            if lib.hasPrefix hmPath (toString decl) then
              gitHubDeclaration "nix-community" "home-manager"
              (lib.removePrefix "/" (lib.removePrefix hmPath (toString decl)))
            else if decl == "lib/modules.nix" then
            # TODO: handle this in a better way (may require upstream
            # changes to nixpkgs)
              gitHubDeclaration "NixOS" "nixpkgs" decl
            else
              decl) opt.declarations;
        };
    } // builtins.removeAttrs args [ "modules" "includeModuleSystemOptions" ]);

  hmOptionsDocs = buildOptionsDocs {
    modules = import ../modules/modules.nix {
      inherit lib pkgs;
      check = false;
    } ++ [ scrubbedPkgsModule ];
    variablelistId = "home-manager-options";
  };

  nixosOptionsDocs = buildOptionsDocs {
    modules = [ ../nixos scrubbedPkgsModule dontCheckDefinitions ];
    includeModuleSystemOptions = false;
    variablelistId = "nixos-options";
    optionIdPrefix = "nixos-opt-";
  };

  nixDarwinOptionsDocs = buildOptionsDocs {
    modules = [ ../nix-darwin scrubbedPkgsModule dontCheckDefinitions ];
    includeModuleSystemOptions = false;
    variablelistId = "nix-darwin-options";
    optionIdPrefix = "nix-darwin-opt-";
  };

  # home-manager specialized version of nixos-render-docs
  home-manager-render-docs = let python = pkgs.buildPackages.python3;
  in python.pkgs.callPackage ./home-manager-render-docs.nix {
    python = python;
    nixos-render-docs = python.pkgs.toPythonModule pkgs.nixos-render-docs;
  };

  release-config = builtins.fromJSON (builtins.readFile ../release.json);
  revision = "release-${release-config.release}";
  # Generate the `man home-configuration.nix` package
  home-configuration-manual =
    pkgs.runCommand "home-configuration-reference-manpage" {
      nativeBuildInputs =
        [ pkgs.buildPackages.installShellFiles home-manager-render-docs ];
      allowedReferences = [ "out" ];
    } ''
      # Generate manpages.
      mkdir -p $out/share/man/man5
      mkdir -p $out/share/man/man1
      home-manager-render-docs -j $NIX_BUILD_CORES options manpage \
        --revision ${revision} \
        ${hmOptionsDocs.optionsJSON}/share/doc/nixos/options.json \
        $out/share/man/man5/home-configuration.nix.5
      cp ${./home-manager.1} $out/share/man/man1/home-manager.1
    '';
  # Generate the HTML manual pages
  home-manager-manual = pkgs.callPackage ./home-manager-manual.nix {
    optionsDoc = hmOptionsDocs;
    nmd = nmdSrc;
    home-manager-options = {
      home-manager = hmOptionsDocs.optionsJSON;
      nixos = nixosOptionsDocs.optionsJSON;
      nix-darwin = nixDarwinOptionsDocs.optionsJSON;
    };
    inherit revision home-manager-render-docs;
  };
in {
  inherit nmdSrc;

  options = {
    # TODO: Use `hmOptionsDocs.optionsJSON` directly once upstream
    # `nixosOptionsDoc` is more customizable.
    json = pkgs.runCommand "options.json" {
      meta.description = "List of Home Manager options in JSON format";
    } ''
      mkdir -p $out/{share/doc,nix-support}
      cp -a ${hmOptionsDocs.optionsJSON}/share/doc/nixos $out/share/doc/home-manager
      substitute \
        ${hmOptionsDocs.optionsJSON}/nix-support/hydra-build-products \
        $out/nix-support/hydra-build-products \
        --replace \
          '${hmOptionsDocs.optionsJSON}/share/doc/nixos' \
          "$out/share/doc/home-manager"
    '';
  };

  manPages = home-configuration-manual;

  manual = { html = home-manager-manual; };

  # Unstable, mainly for CI.
  jsonModuleMaintainers = pkgs.writeText "hm-module-maintainers.json" (let
    result = lib.evalModules {
      modules = import ../modules/modules.nix {
        inherit lib pkgs;
        check = false;
      } ++ [ scrubbedPkgsModule ];
    };
  in builtins.toJSON result.config.meta.maintainers);
}
