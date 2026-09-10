import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SETUP_SCRIPT = REPO_ROOT / "scripts" / "setup.sh"
HEALTH_CHECK_SCRIPT = REPO_ROOT / "scripts" / "health_check.sh"
VALIDATOR_SCRIPT = REPO_ROOT / "scripts" / "validate_scenarios.py"


class SetupAndHealthCheckTest(unittest.TestCase):
    def health_check_env(self, scenario_dir: Path, setup_script: Path) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "SCENARIO_DIR": str(scenario_dir),
                "SETUP_SCRIPT": str(setup_script),
                "SCENARIO_VALIDATOR": str(VALIDATOR_SCRIPT),
            }
        )
        return env

    def test_setup_dry_run_allows_placeholder_env(self) -> None:
        env_path = REPO_ROOT / ".env"
        config_path = REPO_ROOT / "config" / "environment.yml"

        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            env_backup = tmpdir_path / "env.bak"
            config_backup = tmpdir_path / "environment.yml.bak"

            if env_path.exists():
                shutil.copy2(env_path, env_backup)
            if config_path.exists():
                shutil.copy2(config_path, config_backup)

            try:
                shutil.copy2(REPO_ROOT / ".env.example", env_path)
                if config_path.exists():
                    config_path.unlink()

                result = subprocess.run(
                    ["bash", str(SETUP_SCRIPT), "--dry-run"],
                    cwd=REPO_ROOT,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            finally:
                if env_backup.exists():
                    shutil.move(str(env_backup), str(env_path))
                else:
                    env_path.unlink(missing_ok=True)

                if config_backup.exists():
                    config_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(config_backup), str(config_path))
                else:
                    config_path.unlink(missing_ok=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("🧪 Dry run only - no live API calls will be made.", result.stdout)

    def test_health_check_fails_for_missing_scenario_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            missing_dir = tmpdir_path / "missing-scenarios"
            setup_stub = tmpdir_path / "setup.sh"
            setup_stub.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            setup_stub.chmod(0o755)

            result = subprocess.run(
                ["bash", str(HEALTH_CHECK_SCRIPT)],
                cwd=REPO_ROOT,
                env=self.health_check_env(missing_dir, setup_stub),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f"❌ Missing Make.com scenario directory: {missing_dir}", result.stderr)

    def test_health_check_fails_for_missing_json_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            scenario_dir = tmpdir_path / "scenarios"
            scenario_dir.mkdir()
            setup_stub = tmpdir_path / "setup.sh"
            setup_stub.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            setup_stub.chmod(0o755)

            result = subprocess.run(
                ["bash", str(HEALTH_CHECK_SCRIPT)],
                cwd=REPO_ROOT,
                env=self.health_check_env(scenario_dir, setup_stub),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f"❌ No Make.com scenario definitions found in {scenario_dir}", result.stderr)

    def test_health_check_uses_validator_for_json_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            scenario_dir = tmpdir_path / "scenarios"
            scenario_dir.mkdir()
            (scenario_dir / "scenario.json").write_text(
                textwrap.dedent(
                    """\
                    {
                      "webhooks": [
                        {"url": "{{config.make.webhook_base_url}}/auction-won"}
                      ]
                    }
                    """
                ),
                encoding="utf-8",
            )
            setup_stub = tmpdir_path / "setup.sh"
            setup_stub.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            setup_stub.chmod(0o755)

            result = subprocess.run(
                ["bash", str(HEALTH_CHECK_SCRIPT)],
                cwd=REPO_ROOT,
                env=self.health_check_env(scenario_dir, setup_stub),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("✅ Health check completed successfully", result.stdout)

    def test_health_check_requires_webhook_urls(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            scenario_dir = tmpdir_path / "scenarios"
            scenario_dir.mkdir()
            (scenario_dir / "scenario.json").write_text("{}", encoding="utf-8")
            setup_stub = tmpdir_path / "setup.sh"
            setup_stub.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            setup_stub.chmod(0o755)

            result = subprocess.run(
                ["bash", str(HEALTH_CHECK_SCRIPT)],
                cwd=REPO_ROOT,
                env=self.health_check_env(scenario_dir, setup_stub),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("❌ No Make.com webhook URLs were found in the scenario definitions", result.stderr)


if __name__ == "__main__":
    unittest.main()
