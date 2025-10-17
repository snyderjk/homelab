#!/bin/bash
# Usage: ./encrypt-secret.sh path/to/secret.yaml

if [ -z "$1" ]; then
  echo "Usage: $0 <secret-file.yaml>"
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${INPUT_FILE%.yaml}.enc.yaml"

sops --encrypt "$INPUT_FILE" >"$OUTPUT_FILE"
echo "Encrypted: $OUTPUT_FILE"
