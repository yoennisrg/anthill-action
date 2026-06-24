#!/bin/sh
set -e

REPO="yoennisrg/anthill-action"
BIN="anthill"
INSTALL_DIR="/usr/local/bin"

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
  linux)  OS="linux" ;;
  darwin) OS="darwin" ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

# Detect arch
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

ASSET="${BIN}-${OS}-${ARCH}"
URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"

echo "Downloading anthill (${OS}/${ARCH})..."
curl -sSL "$URL" -o "/tmp/${ASSET}"
chmod +x "/tmp/${ASSET}"

# Install (try without sudo, fall back to sudo)
if mv "/tmp/${ASSET}" "${INSTALL_DIR}/${BIN}" 2>/dev/null; then
  :
elif command -v sudo >/dev/null 2>&1; then
  sudo mv "/tmp/${ASSET}" "${INSTALL_DIR}/${BIN}"
else
  echo "Cannot write to ${INSTALL_DIR}. Try: sudo mv /tmp/${ASSET} ${INSTALL_DIR}/${BIN}"
  exit 1
fi

echo "anthill installed to ${INSTALL_DIR}/${BIN}"
anthill version
