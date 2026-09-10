#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENARIO_DIR="$REPO_ROOT/make-scenarios"

echo "🔎 AIAAR health check"
echo "===================="

echo "• Verifying setup dry run"
"$SCRIPT_DIR/setup.sh" --dry-run

if [ ! -d "$SCENARIO_DIR" ]; then
    echo "❌ Missing Make.com scenario directory: $SCENARIO_DIR" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ python3 is required to validate Make.com scenario definitions" >&2
    exit 1
fi

echo "• Validating Make.com scenario definition(s)"
python3 - "$SCENARIO_DIR" <<'PY'
import json
import sys
from pathlib import Path

scenario_dir = Path(sys.argv[1])
scenario_files = sorted(path for path in scenario_dir.glob("*.json") if path.is_file())

if not scenario_files:
    print(f"❌ No Make.com scenario definitions found in {scenario_dir}", file=sys.stderr)
    sys.exit(1)

webhook_urls = []

for scenario_file in scenario_files:
    try:
        content = json.loads(scenario_file.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - surfaced through exit status
        print(f"❌ Invalid JSON in {scenario_file.name}: {exc}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(content, dict):
        print(f"❌ Scenario {scenario_file.name} must contain a JSON object", file=sys.stderr)
        sys.exit(1)

    for webhook in content.get("webhooks", []) or []:
        if not isinstance(webhook, dict):
            print(
                f"❌ Scenario {scenario_file.name} contains a webhook entry that is not a JSON object",
                file=sys.stderr,
            )
            sys.exit(1)
        url = webhook.get("url")
        if not isinstance(url, str) or not url.strip():
            print(f"❌ Scenario {scenario_file.name} contains a webhook without a URL", file=sys.stderr)
            sys.exit(1)
        webhook_urls.append((scenario_file.name, url.strip()))

if not webhook_urls:
    print("❌ No Make.com webhook URLs were found in the scenario definitions", file=sys.stderr)
    sys.exit(1)

invalid_urls = [
    (name, url)
    for name, url in webhook_urls
    if not url.startswith("{{config.make.webhook_base_url}}/")
]

if invalid_urls:
    for name, url in invalid_urls:
        print(
            f"❌ Scenario {name} has a webhook URL that does not use "
            f"{{{{config.make.webhook_base_url}}}}/: {url}",
            file=sys.stderr,
        )
    sys.exit(1)

print(f"✅ Validated {len(scenario_files)} scenario file(s)")
print(
    "✅ Found "
    f"{len(webhook_urls)} Make.com webhook URL(s) using "
    "{{config.make.webhook_base_url}}"
)
PY

echo "✅ Health check completed successfully"
