{
  description = "MLIR and ClangIR Build with Python Bindings";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      llvmVersion = "23.1.2";
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
            hash = "sha256-7RkcTVAGsNCZGGRi/qZrKxhFGDGRoYlu/WYvnvYzwCU=";
          };
          python = pkgs.python312.override {
            packageOverrides = pfinal: pprev: {
              numpy = pprev.numpy.overridePythonAttrs (old: rec {
                version = "2.1.2";
                src = pkgs.fetchPypi {
                  inherit (old) pname;
                  inherit version;
                  hash = "sha256-E1MqCIIX+mJMmbhD7rVGQN4js0FLFKpm0COAXrcxBmw=";
                };
              });
              lit = pprev.lit.overridePythonAttrs (old: {
                version = litVersion;
                src = llvmSrc;
                sourceRoot = "source/llvm/utils/lit";
                doCheck = false;
              });
            };
          };
          pythonEnv = python.withPackages (ps: with ps; [
            nanobind pyyaml typing-extensions numpy ml-dtypes lit
          ]);
          litDriver = pkgs.writeTextFile {
            name = "lit-driver";
            destination = "/bin/lit";
            executable = true;
            text = ''
              #!${pythonEnv.interpreter}

              from lit.main import main

              if __name__ == "__main__":
                  main()
            '';
          };
          mkMlir = enableCIR: pkgs.llvmPackages_23.stdenv.mkDerivation {
            pname = if enableCIR then "mlir-custom-cir" else "mlir-custom";
            version = gitRevision;
            src = llvmSrc;
            sourceRoot = "source/llvm";
            nativeBuildInputs = with pkgs; [
              cmake
              ninja
              mold
              pythonEnv
              llvmPackages_23.clang
              llvmPackages_23.bintools
            ];
            buildInputs = with pkgs; [ libxml2 ncurses zlib ];
            hardeningDisable = [ "libcxxhardeningfast" ];
            cmakeFlags = [
              "-DCMAKE_C_COMPILER=clang"
              "-DCMAKE_CXX_COMPILER=clang++"
              "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
              "-DCMAKE_CXX_STANDARD=17"
              "-DLLVM_TARGETS_TO_BUILD=host"
              "-DLLVM_ENABLE_PROJECTS=clang;mlir"
              "-DCLANG_ENABLE_CIR=${if enableCIR then "ON" else "OFF"}"
              "-DLLVM_USE_LINKER=mold"
              "-DBUILD_SHARED_LIBS=OFF"
              "-DLLVM_INSTALL_UTILS=ON"
              "-DLLVM_ENABLE_ASSERTIONS=ON"
              "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
              "-DMLIR_ENABLE_EXECUTION_ENGINE=ON"
              "-DLLVM_BUILD_TOOLS=ON"
              "-DLLVM_INCLUDE_BENCHMARKS=OFF"
              "-DMLIR_BUILD_MLIR_C_DYLIB=OFF"
              "-DMLIR_ENABLE_BINDINGS_PYTHON=ON"
              "-DPython_EXECUTABLE=${pythonEnv.interpreter}"
              "-DPython3_EXECUTABLE=${pythonEnv.interpreter}"
            ];
            postInstall = ''
              ln -sf ${litDriver}/bin/lit $out/bin/lit
            '';
            passthru = {
              isClang = true;
              inherit (pkgs.llvmPackages_23.clang-unwrapped) hardeningUnsupportedFlagsByTargetPlatform;
            };
          };
          mlir = mkMlir false;
          mlirCir = mkMlir true;
          mkClang = cc: pkgs.wrapCCWith {
            inherit cc;
            libcxx = null;
          };
          clang = mkClang mlir;
          clangCir = mkClang mlirCir;
          clangStdenv = pkgs.overrideCC pkgs.stdenv clang;
        in {
          inherit mlir python pythonEnv clang clangStdenv;
          mlir-cir = mlirCir;
          clang-cir = clangCir;
          default = mlir;
        });

      overlays.default = final: prev: {
        mlir-custom = self.packages.${final.stdenv.hostPlatform.system}.mlir;
        mlir-clang = self.packages.${final.stdenv.hostPlatform.system}.clang;
      };

      nixosModules.default = { pkgs, ... }: {
        nixpkgs.overlays = [ self.overlays.default ];
        environment.systemPackages = [ pkgs.mlir-custom ];
      };
    };
}
