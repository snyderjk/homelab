#!/bin/bash
# Usage: ./decrypt-secret.sh path/to/secret.enc.yaml

if [ -z "$1" ]; then
  echo "Usage: $0 <secret-file.enc.yaml>"
  exit 1
fi

sops --decrypt "$1"
