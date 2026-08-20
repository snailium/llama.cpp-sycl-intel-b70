#!/usr/bin/env bash
set -euo pipefail

# Build community B70-optimized llama.cpp SYCL image
# Usage:
#   ./scripts/build-b70-image.sh [target] [tag]
# target: server (default), light, full

TARGET=${1:-server}
TAG=${2:-llama.cpp-sycl-b70:${TARGET}}

echo "Building target=${TARGET} tag=${TAG}"

docker build \
  --target "${TARGET}" \
  -t "${TAG}" \
  -f .devops/intel.Dockerfile \
  --build-arg ONEAPI_VERSION=2026.1-devel-ubuntu24.04 \
  --build-arg GGML_SYCL_F16=ON \
  --build-arg GGML_SYCL_DEVICE_ARCH=bmg-g31 \
  .

echo "Done: ${TAG}"
echo "Test with:"
echo "  docker run --rm -it --device /dev/dri/renderD128:/dev/dri/renderD128 -v \$PWD/models:/models -p 8080:8080 ${TAG} --help"
