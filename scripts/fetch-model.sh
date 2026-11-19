#!/usr/bin/env bash
# Downloads the face-embedding model used by face unlock (AuraFace-v1, Apache-2.0, ~130 MB).
# Source: third-party Core ML conversion of fal/AuraFace-v1 (glintr100). Checked against a pinned hash.
set -euo pipefail
cd "$(dirname "$0")/.."
URL="https://huggingface.co/RuiSumida/AuraFace-v1-CoreML/resolve/main/FaceEmbedding.mlmodel"
SHA="9cb10bef2141a36619bb1fdbf1e0e14e2519c6da4b7e9b9969a4d67702d7122b"
mkdir -p Models
if [ -f Models/FaceEmbedding.mlmodel ] && [ "$(shasum -a 256 Models/FaceEmbedding.mlmodel | cut -d' ' -f1)" = "$SHA" ]; then
  echo "Model already present."; exit 0
fi
curl -L --fail -o Models/FaceEmbedding.mlmodel "$URL"
[ "$(shasum -a 256 Models/FaceEmbedding.mlmodel | cut -d' ' -f1)" = "$SHA" ] || { echo "Hash mismatch, removing."; rm Models/FaceEmbedding.mlmodel; exit 1; }
echo "Done. Run: xcodegen generate"
