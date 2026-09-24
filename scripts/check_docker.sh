#!/bin/bash

# Original list of needed binaries
# NEEDED_BINARIES=(
#   soda-opt
#   soda-translate
#   mlir-opt
#   mlir-translate
#   flatbuffer_translate
#   tf-mlir-translate
#   tf-opt
#   torch-mlir-opt
#   bambu
#   openroad
#   yosys
# )

# list of needed binaries
NEEDED_BINARIES=(
  soda-opt
  soda-translate
  mlir-opt
  mlir-translate
  bambu
)

DOCKER_RUN="docker run -u $(id -u):$(id -g) -v $(pwd):$(pwd) -w $(pwd) --rm agostini01/soda"
if ! command -v docker &> /dev/null; then
  DOCKER_RUN=""
  
  # Loop over all needed binaries and check if they are available.
  # This file is sourced, so exiting here also stops the calling script.
  for binary in "${NEEDED_BINARIES[@]}"; do
    if ! command -v $binary &> /dev/null; then
      echo "ERROR: docker was not found and $binary is not available locally. Exiting." >&2
      exit 1
    fi
  done
  # echo "SUCCESS: All needed binaries are available locally."
fi
