#!/bin/bash

OUTDIR="/tmp/lima/output"
# Find the latest .qcow2.xz image, or fallback to .qcow2 if not found
IMG_PATH=$(ls -t $OUTDIR/Arch-Linux-aarch64-cloudimg-*.qcow2.xz 2>/dev/null | head -n 1)
if [[ ! -f "$IMG_PATH" ]]; then
  IMG_PATH=$(ls -t $OUTDIR/Arch-Linux-aarch64-cloudimg-*.qcow2 2>/dev/null | head -n 1)
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "No .qcow2(.xz) image found in $OUTDIR"
  exit 1
fi

# Calculate the sha512 digest with openssl
DIGEST="sha512:$(openssl dgst -sha512 -r "$IMG_PATH" | awk '{print tolower($1)}')"

cat > archlinux.yaml <<EOF
# Lima template for local Arch Linux ARM image
images:
- location: "$IMG_PATH"
  arch: "aarch64"
  digest: "$DIGEST"

mounts:
- location: "~"
- location: "/tmp/lima"
  writable: true
EOF

echo "archlinux.yaml created for $IMG_PATH with digest $DIGEST"