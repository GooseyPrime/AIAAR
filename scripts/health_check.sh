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
import re
import sys
from pathlib import Path

scenario_dir = Path(sys.argv[1])
scenario_files = sorted(path for path in scenario_dir.glob("*.json") if path.is_file())

if not scenario_files:
    print(f"❌ No Make.com scenario definitions found in {scenario_dir}", file=sys.stderr)
    sys.exit(1)

registered_webhooks = []

for scenario_file in scenario_files:
    try:
        content = json.loads(scenario_file.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - surfaced through exit status
        print(f"❌ Invalid JSON in {scenario_file.name}: {exc}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(content, dict):
        print(f"❌ Scenario {scenario_file.name} must contain a JSON object", file=sys.stderr)
        sys.exit(1)

    webhooks = content.get("webhooks", [])
    if webhooks is None:
        webhooks = []
    if not isinstance(webhooks, list):
        print(f"❌ Scenario {scenario_file.name} has a non-list `webhooks` section", file=sys.stderr)
        sys.exit(1)

    for webhook in webhooks:
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
        registered_webhooks.append((scenario_file.name, url.strip()))

if not registered_webhooks:
    print("ℹ️ No Make.com webhook connectivity definitions were found to validate")
    sys.exit(0)

placeholder_pattern = re.compile(r"^\{\{\s*config\.make\.webhook_base_url\s*\}\}(?:/.*)?$")

invalid_urls = [
    (name, url)
    for name, url in registered_webhooks
    if not placeholder_pattern.match(url)
]

if invalid_urls:
    for name, url in invalid_urls:
        print(
            f"❌ Scenario {name} has a Make.com webhook definition that does not reference "
            f"config.make.webhook_base_url: {url}",
            file=sys.stderr,
        )
    sys.exit(1)

print(f"✅ Validated {len(scenario_files)} scenario file(s)")
print(
    "✅ Found "
    f"{len(registered_webhooks)} registered webhook definition(s) referencing "
    "config.make.webhook_base_url"
)
PY

echo "✅ Health check completed successfully"
