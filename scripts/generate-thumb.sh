#!/usr/bin/env bash
# Generate a thumbnail image using Gemini API (gemini-3.1-flash-image-preview)
#
# Usage:
#   ./scripts/generate-thumb.sh <output_path> "<prompt>"
#   ./scripts/generate-thumb.sh <output_path> "<prompt>" <reference_image>
#
# Environment:
#   GEMINI_API_KEY - Required. Your Gemini API key.
#
# Examples:
#   ./scripts/generate-thumb.sh static/img/thumbs/project_foo.jpeg \
#     "A minimal modern logo with letter F, neon blue on dark background, project icon style"
#
#   ./scripts/generate-thumb.sh static/img/thumbs/defidash_preview-leverage.jpeg \
#     "DeFi leverage trading dashboard visualization, dark theme, minimal" \
#     static/img/thumbs/project_defidash.jpeg

set -uo pipefail

# --- Load environment (for GEMINI_API_KEY etc.) ---
if [ -z "${GEMINI_API_KEY:-}" ] && [ -f "$HOME/.zshrc" ]; then
  set +eu
  source "$HOME/.zshrc" 2>/dev/null || true
  set -eu
fi

set -e

# --- Args ---
OUTPUT_PATH="${1:-}"
PROMPT="${2:-}"
REFERENCE_IMAGE="${3:-}"

if [ -z "$OUTPUT_PATH" ] || [ -z "$PROMPT" ]; then
  echo "Usage: $0 <output_path> \"<prompt>\" [reference_image]"
  exit 1
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "Error: GEMINI_API_KEY environment variable is not set"
  exit 1
fi

# --- Config ---
MODEL="gemini-3.1-flash-image-preview"
ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

# --- Build request body ---
if [ -n "$REFERENCE_IMAGE" ] && [ -f "$REFERENCE_IMAGE" ]; then
  # With reference image (style transfer / editing)
  MIME_TYPE="image/jpeg"
  case "$REFERENCE_IMAGE" in
    *.png) MIME_TYPE="image/png" ;;
    *.webp) MIME_TYPE="image/webp" ;;
  esac
  BASE64_IMG=$(base64 < "$REFERENCE_IMAGE" | tr -d '\n')

  REQUEST_BODY=$(cat <<JSONEOF
{
  "contents": [{
    "parts": [
      {"text": "Generate a new image in the same visual style as the reference image. ${PROMPT}"},
      {
        "inline_data": {
          "mime_type": "${MIME_TYPE}",
          "data": "${BASE64_IMG}"
        }
      }
    ]
  }],
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"]
  }
}
JSONEOF
)
else
  # Text-to-image only
  REQUEST_BODY=$(cat <<JSONEOF
{
  "contents": [{
    "parts": [
      {"text": "${PROMPT}"}
    ]
  }],
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"]
  }
}
JSONEOF
)
fi

# --- Call Gemini API ---
echo "Generating image with Gemini (${MODEL})..."

RESPONSE=$(curl -s -X POST "$ENDPOINT" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY")

# --- Extract base64 image from response ---
IMAGE_DATA=$(echo "$RESPONSE" | python3 -c "
import sys, json

try:
    resp = json.load(sys.stdin)
except json.JSONDecodeError:
    print('', end='')
    sys.exit(1)

# Check for API errors
if 'error' in resp:
    print(f\"API Error: {resp['error'].get('message', 'Unknown error')}\", file=sys.stderr)
    sys.exit(1)

for candidate in resp.get('candidates', []):
    for part in candidate.get('content', {}).get('parts', []):
        if 'inlineData' in part:
            print(part['inlineData']['data'], end='')
            sys.exit(0)

print('No image found in response', file=sys.stderr)
sys.exit(1)
" 2>&1)

if [ $? -ne 0 ] || [ -z "$IMAGE_DATA" ] || [[ "$IMAGE_DATA" == *"Error"* ]] || [[ "$IMAGE_DATA" == *"No image"* ]]; then
  echo "Error: Failed to extract image from response"
  echo "$IMAGE_DATA"
  echo ""
  echo "Raw response (first 500 chars):"
  echo "$RESPONSE" | head -c 500
  exit 1
fi

# --- Ensure output directory exists ---
mkdir -p "$(dirname "$OUTPUT_PATH")"

# --- Decode and save ---
echo "$IMAGE_DATA" | base64 -d > "$OUTPUT_PATH"

# --- Verify ---
FILE_SIZE=$(wc -c < "$OUTPUT_PATH" | tr -d ' ')
echo "Generated: ${OUTPUT_PATH} (${FILE_SIZE} bytes)"
