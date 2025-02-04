#!/usr/bin/env bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1; pwd -P )"

# Make sure to remove existing crds first to use current crds
rm -f templates/*-crd.yaml

helm template --include-crds . |\
  yq e -p yaml \
       -o yaml \
       -s '"templates/" + .metadata.name + "-crd.yaml"' 'select(.kind == "CustomResourceDefinition") | .metadata.annotations."argocd.argoproj.io/sync-options" |= "ServerSideApply=true"'
