import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "validate_scenarios.py"


class ValidateScenariosTest(unittest.TestCase):
    def run_validator(
        self, contents: dict[str, str], *extra_args: str
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            paths = []
            for name, content in contents.items():
                path = tmpdir_path / name
                path.write_text(content, encoding="utf-8")
                paths.append(str(path))

            return subprocess.run(
                ["python3", str(SCRIPT_PATH), *extra_args, *paths],
                capture_output=True,
                text=True,
                check=False,
            )

    def test_accepts_valid_scenario(self) -> None:
        result = self.run_validator(
            {
                "valid.json": json.dumps(
                    {
                        "webhooks": [
                            {"url": "{{config.make.webhook_base_url}}/auction-won"},
                            {"url": "{{config.make.webhook_base_url}}/item-sold"},
                        ]
                    }
                )
            }
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("✅ Validated 1 scenario file(s)", result.stdout)
        self.assertIn("✅ Found 2 Make.com webhook URL(s)", result.stdout)

    def test_rejects_invalid_json(self) -> None:
        result = self.run_validator({"invalid.json": "{not-json}"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("❌ Invalid JSON in invalid.json", result.stderr)

    def test_rejects_missing_webhook_url(self) -> None:
        result = self.run_validator({"missing-url.json": json.dumps({"webhooks": [{}]})})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("❌ Scenario missing-url.json contains a webhook without a URL", result.stderr)

    def test_rejects_invalid_webhook_prefix(self) -> None:
        result = self.run_validator(
            {
                "invalid-prefix.json": json.dumps(
                    {"webhooks": [{"url": "https://example.com/not-make"}]}
                )
            }
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "❌ Scenario invalid-prefix.json has a webhook URL that does not use {{config.make.webhook_base_url}}/: https://example.com/not-make",
            result.stderr,
        )

    def test_allows_missing_webhooks_without_requirement(self) -> None:
        result = self.run_validator({"missing-webhooks.json": json.dumps({})})

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("✅ Validated 1 scenario file(s)", result.stdout)
        self.assertIn("✅ Found 0 Make.com webhook URL(s)", result.stdout)

    def test_rejects_missing_webhooks_when_required(self) -> None:
        result = self.run_validator({"missing-webhooks.json": json.dumps({})}, "--require-webhooks")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("❌ No Make.com webhook URLs were found in the scenario definitions", result.stderr)

    def test_rejects_missing_webhooks_when_flag_follows_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "missing-webhooks.json"
            path.write_text(json.dumps({}), encoding="utf-8")

            result = subprocess.run(
                ["python3", str(SCRIPT_PATH), str(path), "--require-webhooks"],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("❌ No Make.com webhook URLs were found in the scenario definitions", result.stderr)

    def test_rejects_non_object_webhook_entry(self) -> None:
        result = self.run_validator(
            {"invalid-webhook.json": json.dumps({"webhooks": ["not-an-object"]})}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "❌ Scenario invalid-webhook.json contains a webhook entry that is not an object",
            result.stderr,
        )

    def test_rejects_non_list_webhooks(self) -> None:
        result = self.run_validator(
            {"invalid-webhooks.json": json.dumps({"webhooks": {"url": "x"}})}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "❌ Scenario invalid-webhooks.json must define webhooks as a list",
            result.stderr,
        )

    def test_rejects_empty_invocation(self) -> None:
        result = subprocess.run(
            ["python3", str(SCRIPT_PATH)],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("❌ No scenario files were provided for validation", result.stderr)


if __name__ == "__main__":
    unittest.main()
