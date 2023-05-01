#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2023-04-01 00:05:05 +0100 (Sat, 01 Apr 2023)
#
#  https://github.com/HariSekhon/DevOps-Bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
. "$srcdir/../lib/utils.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Installs K3d wrapper for k3s mini kubernetes distribution
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args="[<version_tag>]"

version="${1:-}"

if [ -n "$version" ]; then
    export TAG="$version"
fi

timestamp "Installing K3d"

curl -sSf https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
