{
  description = "Trendy monorepo development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
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

            # Cloud deployment tools
            google-cloud-sdk
            firebase-tools
            docker

            # Development utilities
            git
            curl
            jq

            # Optional: iOS development (if on macOS)
            # xcode-install would go here but it's macOS specific
          ];

          shellHook = ''
            # Add Homebrew Ruby to PATH (required for Fastlane, avoids Xcode SDK conflicts)
            export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
            export PATH="$(/opt/homebrew/opt/ruby/bin/gem environment gemdir 2>/dev/null)/bin:$PATH"

            # Unset nix SDK variables that conflict with Xcode toolchain for Ruby gem compilation
            unset DEVELOPER_DIR_arm64_apple_darwin
            unset DEVELOPER_DIR_FOR_TARGET
            unset SDKROOT
            unset NIX_CFLAGS_COMPILE_FOR_TARGET
            unset NIX_LDFLAGS_FOR_TARGET

            echo "🚀 Trendy monorepo development environment"
            echo ""
            echo "📦 Available tools:"
            echo "  - Node.js $(node --version)"
            echo "  - Yarn $(yarn --version)"
            echo "  - Go $(go version | cut -d' ' -f3)"
            echo "  - Ruby $(ruby --version 2>/dev/null | cut -d' ' -f2 || echo 'not found')"
            echo "  - Just $(just --version)"
            echo "  - Supabase CLI $(supabase --version | head -n1)"
            echo "  - Google Cloud SDK $(gcloud --version | head -n1)"
            echo "  - Docker $(docker --version)"
            echo ""
            echo "💡 Quick commands:"
            echo "  just --list          # Show all available commands"
            echo "  just install         # Install all dependencies"
            echo "  just dev             # Start development servers"
            echo "  just db-migrate      # Run database migrations"
            echo "  just gcp-setup       # Setup Google Cloud deployment"
            echo ""
            echo "📱 iOS Fastlane:"
            echo "  cd apps/ios && bundle install  # Install Fastlane"
            echo "  bundle exec fastlane beta      # Deploy to TestFlight"
            echo ""
          '';
        };
      }
    );
}
