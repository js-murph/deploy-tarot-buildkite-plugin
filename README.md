# Deploy Tarot Buildkite Plugin

Draws a [Deploy Tarot](https://deploytarot.com/api) reading before a Buildkite step runs, prints the oracle's verdict, and renders the drawn Major Arcana cards directly in the Buildkite log.

This is a Buildkite plugin for [deploytarot.com](https://deploytarot.com). The readings, verdicts, share pages, API, and card artwork are provided by Deploy Tarot; this plugin only requests a reading and formats it for Buildkite logs.

Buildkite renders images from log output via ANSI escape codes, so this plugin maps the card names returned by the Deploy Tarot API to Deploy Tarot's public card artwork. In Buildkite jobs, the plugin embeds the card art directly in the log using Buildkite's supported base64 inline image format so the images render reliably.

## Example

```yaml
steps:
  - label: "☽ ask the deploy tarot ☾"
    plugins:
      - github.com/your-org/bk-deploy-tarot-plugin#v1.0.0: ~
    command: ./deploy.sh
```

With no configuration, the plugin:

- uses role `devops` unless the Buildkite build author looks bot-like, in which case it uses `ai-agent`
- infers intent from Buildkite branch, tag, source, and pull request metadata
- renders card images in the Buildkite log
- lets the step continue even when the verdict is `abort-mission`

## Full configuration

```yaml
steps:
  - label: "deploy"
    plugins:
      - github.com/your-org/bk-deploy-tarot-plugin#v1.0.0:
          role: senior-dev
          intent: db-migration
          fail_on_abort: true
          render_images: true
          store_metadata: true
    command: ./deploy.sh
```

## Configuration

### `role` (optional)

Your role. Defaults to `devops`, or `ai-agent` if the build author looks bot-like.

Valid values are the Deploy Tarot API roles, including `devops`, `sre`, `senior-dev`, `tech-lead`, `ai-agent`, `rubber-duck`, and `tarot-reader`.

### `intent` (optional)

What you are deploying. If omitted, the plugin infers an intent:

| Buildkite context | Intent |
| --- | --- |
| Tag build, `main`, or `master` | `full-release` |
| Scheduled build | `dependency-update` |
| UI or trigger job | `just-vibes` |
| `dependabot/*` or `renovate/*` | `dependency-update` |
| `fix/*` or `hotfix/*` | `hotfix-prod` |
| `feat/*` or `feature/*` | `new-feature` |
| `refactor/*` or `chore/*` | `refactor` |
| `db/*` or `migration/*` | `db-migration` |
| `infra/*` or `ops/*` | `infra-change` |
| `docs/*` | `public-doc-release` |
| `security/*` | `security-patch` |
| Anything else | `quick-fix` |

### `fail_on_abort` (optional, default `false`)

When `true`, the plugin exits non-zero if Deploy Tarot returns `abort-mission`, preventing the command from running.

### `render_images` (optional, default `true`)

When `true`, emits Buildkite inline image escape sequences for the drawn cards. In Buildkite jobs, the images are embedded directly in the log using base64 inline image output.

### `store_metadata` (optional, default `false`)

When `true` and `buildkite-agent` is available, stores the verdict details in Buildkite metadata for downstream steps.

### `api_url` (optional)

Defaults to `https://deploytarot.com/api/reading`.

### `image_base_url` (optional)

Source URL used when downloading card images for inline rendering. Defaults to `https://deploytarot.com/static/cards`.

### `timeout` (optional, default `15`)

Curl connect and request timeout in seconds.

### `retries` (optional, default `2`)

Curl retry count for transient request failures.

## Metadata

Metadata is opt-in. Set `store_metadata: true` to store:

- `deploy-tarot:verdict`
- `deploy-tarot:verdict-label`
- `deploy-tarot:share-url`

Example downstream use:

```bash
verdict="$(buildkite-agent meta-data get deploy-tarot:verdict)"
if [[ "$verdict" == "abort-mission" ]]; then
  echo "The cards said no."
  exit 1
fi
```

## Requirements

- Bash
- curl
- Python 3

## Local testing

```bash
BK_DEPLOY_TAROT_ROLE=devops BK_DEPLOY_TAROT_INTENT=full-release hooks/pre-command
```

## API limits

Deploy Tarot allows 60 requests per minute per IP. A rate-limited request returns HTTP 429 with `Retry-After: 60`.
