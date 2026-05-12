#!/bin/sh

# Base image configuration
IBM_ACTIVE_TRANSFER_IMAGE="${IBM_ACTIVE_TRANSFER_IMAGE:-ibmwebmethods.azurecr.io/webmethods-activetransfer}"
IBM_ACTIVE_TRANSFER_IMAGE_TAG="${IBM_ACTIVE_TRANSFER_IMAGE_TAG:-11.1.0.4}"

# Destination image configuration
DEST_IMAGE="${DEST_IMAGE:-active-transfer-ingest}"
DEST_IMAGE_TAG="${IBM_ACTIVE_TRANSFER_IMAGE_TAG}-$(date +%Y%m%d)-$(git rev-parse --short HEAD)"

# Pull base image early (optimization)
echo "Pulling base image: ${IBM_ACTIVE_TRANSFER_IMAGE}:${IBM_ACTIVE_TRANSFER_IMAGE_TAG}"
docker pull "${IBM_ACTIVE_TRANSFER_IMAGE}:${IBM_ACTIVE_TRANSFER_IMAGE_TAG}"

# Build image with proper build arguments
echo "Building image: ${DEST_IMAGE}:${DEST_IMAGE_TAG}"
docker buildx build -t "${DEST_IMAGE}:${DEST_IMAGE_TAG}" \
  --build-arg __active_transfer_ibm_image="${IBM_ACTIVE_TRANSFER_IMAGE}" \
  --build-arg __active_transfer_ibm_image_tag="${IBM_ACTIVE_TRANSFER_IMAGE_TAG}" \
  -f Dockerfile \
  .

echo "Build complete: ${DEST_IMAGE}:${DEST_IMAGE_TAG}"
