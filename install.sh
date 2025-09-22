#!/bin/bash

# This script downloads and installs the autocommit tool.

set -e

# --- Configuration ---
# The script in the repository has a .sh extension for syntax highlighting.
SCRIPT_URL="https://raw.githubusercontent.com/Skediaio/autocommit/main/autocommit.sh"

# The destination command will have no extension for a cleaner user experience.
INSTALL_DIR="$HOME/.local/bin"
DEST_PATH="$INSTALL_DIR/autocommit"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Starting installation of autocommit...${NC}"

# Create installation directory if it doesn't exist
echo "Ensuring installation directory exists at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Download the script, renaming it in the process
echo "Downloading autocommit.sh and installing as 'autocommit'..."
if command -v curl >/dev/null 2>&1; then
  # Use -fsSL: fail silently, show errors, follow redirects
  curl -fsSL -o "$DEST_PATH" "$SCRIPT_URL"
elif command -v wget >/dev/null 2>&1; then
  # Use -qO: quiet, output to file
  wget -qO "$DEST_PATH" "$SCRIPT_URL"
else
  echo -e "${RED}Error: You need either 'curl' or 'wget' to download the script.${NC}"
  exit 1
fi

# Make the script executable
echo "Making the script executable..."
chmod +x "$DEST_PATH"

echo -e "${GREEN}✅ autocommit has been successfully installed to $DEST_PATH${NC}"
echo ""

# Check if the installation directory is in the user's PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo -e "${YELLOW}NOTE: Your PATH does not seem to include $INSTALL_DIR.${NC}"
  echo "To run 'autocommit' from anywhere, you need to add it to your PATH."
  echo "Add the following line to your shell profile file (e.g., ~/.bashrc, ~/.zshrc):"
  echo ""
  echo -e "  ${BLUE}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
  echo ""
  echo "Then, restart your shell or run 'source ~/.bashrc' (or your respective profile file)."
fi

echo "Installation complete. Try running 'autocommit --help' to get started."
