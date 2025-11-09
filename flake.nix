{
  description = "Trendy monorepo development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Node.js and package managers
            nodejs_20
            yarn

            # Go toolchain and C compiler
            go
            gcc

            # Build tools
            just

            # Database tools
            postgresql
            supabase-cli

            # Development utilities
            git
            curl
            jq

            # Optional: iOS development (if on macOS)
            # xcode-install would go here but it's macOS specific
          ];

          shellHook = ''
            echo "🚀 Trendy monorepo development environment"
            echo ""
            echo "📦 Available tools:"
            echo "  - Node.js $(node --version)"
            echo "  - Yarn $(yarn --version)"
            echo "  - Go $(go version | cut -d' ' -f3)"
            echo "  - Just $(just --version)"
            echo "  - Supabase CLI $(supabase --version | head -n1)"
            echo ""
            echo "💡 Quick commands:"
            echo "  just --list          # Show all available commands"
            echo "  just install         # Install all dependencies"
            echo "  just dev             # Start development servers"
            echo "  just db-migrate      # Run database migrations"
            echo ""
          '';
        };
      }
    );
}
