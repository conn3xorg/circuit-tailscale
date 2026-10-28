#!/usr/bin/env sh
# Removes the container and everything up.sh and Conn3x created here.
set -eu
cd "$(dirname "$0")"
${PODMAN:-podman} rm -f -v "${NAME:-circuit-tailscale}" >/dev/null 2>&1 || true
rm -rf id_ed25519 id_ed25519.pub known_hosts .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
echo "Removed."
