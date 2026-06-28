#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap "rm -rf '$TMP_DIR'" EXIT

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    echo "Expected $file to contain: $expected" >&2
    echo "--- $file contents ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

write_mock_bin() {
  mkdir -p "$TMP_DIR/bin"
  cat >"$TMP_DIR/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
headers=""
while (($#)); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -D) headers="$2"; shift 2 ;;
    -w) shift 2 ;;
    --retry|--connect-timeout|--max-time) shift 2 ;;
    -sS) shift ;;
    *) shift ;;
  esac
done
: >"$headers"
cp "$MOCK_RESPONSE" "$out"
printf '200'
SH
  chmod +x "$TMP_DIR/bin/curl"

  cat >"$TMP_DIR/bin/buildkite-agent" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "metadata:$*" >>"$MOCK_METADATA_LOG"
SH
  chmod +x "$TMP_DIR/bin/buildkite-agent"
}

write_response() {
  local verdict="$1"
  cat >"$TMP_DIR/response.json" <<JSON
{
  "verdict": "$verdict",
  "verdict_label": "Abort Mission 🛑",
  "verdict_text": "The cards advise ceremony.",
  "role": "DevOps Engineer",
  "intent": "Full Release",
  "cards": [
    {
      "position": "foundation",
      "position_label": "The Foundation",
      "name": "The Tower",
      "reversed": true,
      "narrative": "The foundation shakes."
    }
  ],
  "share_url": "https://deploytarot.com/r/example"
}
JSON
}

write_mock_bin
export PATH="$TMP_DIR/bin:$PATH"
export MOCK_RESPONSE="$TMP_DIR/response.json"
export MOCK_METADATA_LOG="$TMP_DIR/metadata.log"

write_response "tread-carefully"
BK_DEPLOY_TAROT_ROLE=devops \
BK_DEPLOY_TAROT_INTENT=full-release \
BK_DEPLOY_TAROT_RENDER_IMAGES=true \
  "$ROOT_DIR/hooks/pre-command" >"$TMP_DIR/output.log"

assert_contains "$TMP_DIR/output.log" "--- ☽ Deploy Tarot ☾"
assert_contains "$TMP_DIR/output.log" "Reading by Deploy Tarot: https://deploytarot.com"
assert_contains "$TMP_DIR/output.log" "Verdict: Abort Mission 🛑"
assert_contains "$TMP_DIR/output.log" "✦ The Foundation: The Tower (reversed)"
assert_contains "$TMP_DIR/output.log" "https://deploytarot.com/static/cards/16_the_tower.webp"
assert_contains "$TMP_DIR/output.log" "Share URL: https://deploytarot.com/r/example"

if grep -Fq -- "+++ The Foundation" "$TMP_DIR/output.log"; then
  echo "Expected card titles not to be rendered as Buildkite headings" >&2
  cat "$TMP_DIR/output.log" >&2
  exit 1
fi

if [[ -e "$TMP_DIR/metadata.log" ]]; then
  echo "Expected metadata not to be stored by default" >&2
  cat "$TMP_DIR/metadata.log" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/cards"
printf 'fake webp' >"$TMP_DIR/cards/16_the_tower.webp"
BUILDKITE=true \
BK_DEPLOY_TAROT_ROLE=devops \
BK_DEPLOY_TAROT_INTENT=full-release \
BK_DEPLOY_TAROT_RENDER_IMAGES=true \
BK_DEPLOY_TAROT_IMAGE_BASE_URL="file://$TMP_DIR/cards" \
  bash -c 'cd "$1" && "$2"' _ "$TMP_DIR" "$ROOT_DIR/hooks/pre-command" >"$TMP_DIR/artifact-output.log"

assert_contains "$TMP_DIR/artifact-output.log" $'\033]1337;File=inline=1;'
assert_contains "$TMP_DIR/artifact-output.log" "ZmFrZSB3ZWJw"

if grep -Fq -- "artifact://" "$TMP_DIR/artifact-output.log"; then
  echo "Expected Buildkite image rendering not to use artifacts" >&2
  cat "$TMP_DIR/artifact-output.log" >&2
  exit 1
fi

rm -f "$TMP_DIR/metadata.log"

BK_DEPLOY_TAROT_ROLE=devops \
BK_DEPLOY_TAROT_INTENT=full-release \
BK_DEPLOY_TAROT_RENDER_IMAGES=true \
BK_DEPLOY_TAROT_STORE_METADATA=true \
  "$ROOT_DIR/hooks/pre-command" >"$TMP_DIR/metadata-output.log"

assert_contains "$TMP_DIR/metadata.log" "metadata:meta-data set deploy-tarot:verdict tread-carefully"

write_response "abort-mission"
set +e
BK_DEPLOY_TAROT_ROLE=devops \
BK_DEPLOY_TAROT_INTENT=full-release \
BK_DEPLOY_TAROT_FAIL_ON_ABORT=true \
  "$ROOT_DIR/hooks/pre-command" >"$TMP_DIR/fail-output.log" 2>"$TMP_DIR/fail-error.log"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "Expected fail_on_abort to exit non-zero" >&2
  exit 1
fi
assert_contains "$TMP_DIR/fail-error.log" "fail_on_abort is enabled"

echo "tests passed"
