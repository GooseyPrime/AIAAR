#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def validate_scenarios(paths: list[str], require_webhooks: bool = False) -> tuple[int, int]:
    scenario_files = sorted((Path(path) for path in paths), key=lambda path: path.name)
    webhook_urls: list[tuple[str, str]] = []

    for scenario_file in scenario_files:
        try:
            scenario_text = scenario_file.read_text(encoding="utf-8")
        except OSError as exc:
            raise ValueError(f"❌ Failed to read {scenario_file.name}: {exc}") from exc

        try:
            content = json.loads(scenario_text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"❌ Invalid JSON in {scenario_file.name}: {exc}") from exc

        if not isinstance(content, dict):
            raise ValueError(f"❌ Scenario {scenario_file.name} must contain a JSON object")

        webhooks = content.get("webhooks")
        if webhooks is not None and not isinstance(webhooks, list):
            raise ValueError(f"❌ Scenario {scenario_file.name} must define webhooks as a list")

        for webhook in webhooks or []:
            if not isinstance(webhook, dict):
                raise ValueError(f"❌ Scenario {scenario_file.name} contains a webhook entry that is not an object")
            url = webhook.get("url")
            if not isinstance(url, str) or not url.strip():
                raise ValueError(f"❌ Scenario {scenario_file.name} contains a webhook without a URL")
            webhook_urls.append((scenario_file.name, url.strip()))

    if require_webhooks and not webhook_urls:
        raise ValueError("❌ No Make.com webhook URLs were found in the scenario definitions")

    invalid_urls = [
        (name, url)
        for name, url in webhook_urls
        if not url.startswith("{{config.make.webhook_base_url}}/")
    ]
    if invalid_urls:
        invalid_name, invalid_url = invalid_urls[0]
        raise ValueError(
            "❌ Scenario "
            f"{invalid_name} has a webhook URL that does not use "
            f"{{{{config.make.webhook_base_url}}}}/: {invalid_url}"
        )

    return len(scenario_files), len(webhook_urls)


def main(argv: list[str]) -> int:
    require_webhooks = False
    paths: list[str] = []

    for arg in argv[1:]:
        if arg == "--require-webhooks":
            require_webhooks = True
        else:
            paths.append(arg)

    if not paths:
        print("❌ No scenario files were provided for validation", file=sys.stderr)
        return 1

    try:
        scenario_count, webhook_count = validate_scenarios(paths, require_webhooks=require_webhooks)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print(f"✅ Validated {scenario_count} scenario file(s)")
    print(
        "✅ Found "
        f"{webhook_count} Make.com webhook URL(s) using "
        "{{config.make.webhook_base_url}}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
