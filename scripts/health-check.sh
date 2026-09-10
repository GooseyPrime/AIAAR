#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔎 AIAAR health check"
echo "===================="
"$SCRIPT_DIR/setup.sh" --dry-run
echo "✅ Dry run completed successfully"
