{
  description = "MLIR Build with Python Bindings";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  outputs = { self, nixpkgs }:
    let
      llvmVersion = "22.1.7";
      gitRevision = "llvmorg-${llvmVersion}";
      litVersion = llvmVersion;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          llvmSrc = pkgs.fetchFromGitHub {
            owner = "llvm";
            repo = "llvm-project";
            rev = gitRevision;
            hash = "sha256-AmozlrL8AAlfr+F7OrJqr3ecd/KhBx5Bngj3SopPdyY=";
          };
          python = pkgs.python312.override {
            packageOverrides = pfinal: pprev: {
              numpy = pprev.numpy.overridePythonAttrs (old: rec {
                version = "2.1.2";
                src = pkgs.fetchPypi {
                  inherit (old) pname; inherit version;
                  hash = "sha256-E1MqCIIX+mJMmbhD7rVGQN4js0FLFKpm0COAXrcxBmw=";
                };
              });
              exhale = pfinal.buildPythonPackage rec {
                pname = "exhale"; version = "0.3.7"; pyproject = true;
                src = pkgs.fetchPypi {
                  inherit pname version;
                  hash = "sha256-dSqW0KWUVlEdkzMR1KgfZCzWaClurNJWGQVyfV7WsNg=";
                };
                build-system = [ pfinal.setuptools ];
                dependencies = [ pfinal.breathe pfinal.beautifulsoup4 pfinal.lxml pfinal.six ];
                doCheck = false;
              };
              lit = pprev.lit.overridePythonAttrs (old: {
                version = litVersion;
                src = llvmSrc;
                sourceRoot = "source/llvm/utils/lit";
                doCheck = false;
              });
            };
          };
          pythonEnv = python.withPackages (ps: with ps; [
            nanobind pyyaml typing-extensions numpy ml-dtypes
            breathe myst-parser scikit-build-core sphinx sphinx-rtd-theme
            exhale lit
          ]);
          mlir = pkgs.llvmPackages_22.stdenv.mkDerivation {
            pname = "mlir-custom";
            version = gitRevision;
            src = llvmSrc;
            sourceRoot = "source/llvm";
            nativeBuildInputs = with pkgs; [
              cmake
              ninja
              mold
              pythonEnv
              llvmPackages_22.clang
              llvmPackages_22.bintools
            ];
            buildInputs = with pkgs; [ libxml2 ncurses zlib ];
            cmakeFlags = [
              "-DCMAKE_C_COMPILER=clang"
              "-DCMAKE_CXX_COMPILER=clang++"
              "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
              "-DCMAKE_CXX_STANDARD=17"
              "-DLLVM_TARGETS_TO_BUILD=host"
              "-DLLVM_ENABLE_PROJECTS=mlir"
              "-DLLVM_USE_LINKER=mold"
              "-DBUILD_SHARED_LIBS=OFF"
              "-DLLVM_INSTALL_UTILS=ON"
              "-DLLVM_ENABLE_ASSERTIONS=ON"
              "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
              "-DMLIR_ENABLE_EXECUTION_ENGINE=ON"
              "-DLLVM_BUILD_TOOLS=ON"
              "-DMLIR_BUILD_MLIR_C_DYLIB=OFF"
              "-DLLVM_OPTIMIZED_TABLEGEN=ON"
              "-DMLIR_ENABLE_BINDINGS_PYTHON=ON"
              "-DPython_EXECUTABLE=${pythonEnv.interpreter}"
              "-DPython3_EXECUTABLE=${pythonEnv.interpreter}"
            ];
            postInstall = ''
              ln -s ${pythonEnv}/bin/lit $out/bin/lit
            '';
          };
        in {
          inherit mlir python pythonEnv;
          default = mlir;
        });
        overlays.default = final: prev: {
          mlir-custom = self.packages.${final.system}.mlir;
        };
        nixosModules.default = { pkgs, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
          environment.systemPackages = [ pkgs.mlir-custom ];
        };
    };
}
