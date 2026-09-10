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

scenario_files=()
while IFS= read -r scenario_file; do
    if [ -n "$scenario_file" ]; then
        scenario_files+=("$scenario_file")
    fi
done <<EOF
$(find "$SCENARIO_DIR" -maxdepth 1 -type f -name '*.json' | sort)
EOF

if [ "${#scenario_files[@]}" -eq 0 ]; then
    echo "❌ No Make.com scenario definitions found in $SCENARIO_DIR" >&2
    exit 1
fi

echo "• Validating ${#scenario_files[@]} Make.com scenario definition(s)"
python3 - "${scenario_files[@]}" <<'PY'
import json
import sys
from pathlib import Path

scenario_files = [Path(path) for path in sys.argv[1:]]
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
