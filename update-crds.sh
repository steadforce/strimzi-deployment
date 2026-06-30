#!/usr/bin/env bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1; pwd -P )"

require_cmd() {
  local cmd="$1"
  local hint="$2"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed or not in PATH." >&2
    echo "Hint: $hint" >&2
    exit 127
  fi
}

require_mikefarah_yq_v4() {
  local yq_version

  yq_version="$(yq --version 2>/dev/null || true)"

  # This script requires mikefarah/yq v4 syntax (yq e -p yaml -o yaml -s ...).
  if [[ "$yq_version" != *"mikefarah"* ]] || [[ "$yq_version" != *"version v4"* ]]; then
    echo "Error: incompatible yq detected." >&2
    echo "Found: ${yq_version:-unknown}" >&2
    echo "This script requires mikefarah/yq v4." >&2
    echo "Hint: apt yq is usually the Python wrapper and is incompatible here." >&2
    echo "Install mikefarah/yq v4 with: sudo snap install yq" >&2
    echo "If apt yq shadows snap yq, remove it with: sudo apt remove yq" >&2
    exit 1
  fi
}

require_cmd helm "Install with: sudo snap install helm --classic or run script from inside the workbench"
require_cmd yq "Install with: sudo snap install yq or run script from inside the workbench"
require_mikefarah_yq_v4

cd "$DIR"

# Make sure to remove existing crds first to use current crds
rm -f templates/*-crd.yaml

helm template --include-crds . |\
  yq e -p yaml \
       -o yaml \
       -s '"templates/" + .metadata.name + "-crd.yaml"' 'select(.kind == "CustomResourceDefinition") | .metadata.annotations."argocd.argoproj.io/sync-options" |= "ServerSideApply=true"'
