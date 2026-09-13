"""Offline fixtures only: no Apple accounts, Keychains, real profiles, or signing."""

from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import importlib.util
import io
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import unittest
from unittest.mock import patch
from uuid import uuid4


TOOLS = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("release_signing", TOOLS / "prepare-release-signing.py")
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)

PREFIX = "A1B2C3D4E5"
TEAM = "Y5UE64R7TQ"
BUNDLE = "solimanali.openlist"
CONTAINER = "iCloud.solimanali.openlist"
GROUP = "Y5UE64R7TQ.solimanali.openlist"
CERTIFICATE = b"OFFLINE SYNTHETIC CERTIFICATE - NOT A REAL CERTIFICATE OR PRIVATE KEY"
OTHER_CERTIFICATE = b"OFFLINE SECOND SYNTHETIC CERTIFICATE"
ORIGINAL_CMS = b"OFFLINE SYNTHETIC CMS FIXTURE - NOT AN APPLE PROVISIONING PROFILE"
PRIVATE_SENTINEL = "OFFLINE-PROFILE-METADATA-MUST-NOT-BE-LOGGED"


def source_fixture():
    return {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.files.user-selected.read-write": True,
        "com.apple.security.network.client": True,
        "com.apple.security.network.server": True,
        "com.apple.security.application-groups": [GROUP],
        "com.apple.developer.icloud-container-identifiers": [CONTAINER],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-environment": "$(ICLOUD_CONTAINER_ENVIRONMENT)",
        "com.apple.developer.aps-environment": "$(APS_ENVIRONMENT)",
    }


def profile_fixture(now=None):
    now = now or datetime.now(timezone.utc)
    return {
        "Name": PRIVATE_SENTINEL,
        "UUID": "00000000-0000-4000-8000-000000000000",
        "CreationDate": now - timedelta(days=1),
        "ExpirationDate": now + timedelta(days=30),
        "Platform": ["OSX"],
        "ProvisionsAllDevices": True,
        "TeamIdentifier": [TEAM],
        "ApplicationIdentifierPrefix": [PREFIX],
        "DeveloperCertificates": [CERTIFICATE, OTHER_CERTIFICATE],
        "Entitlements": {
            "com.apple.application-identifier": f"{PREFIX}.{BUNDLE}",
            "com.apple.developer.team-identifier": TEAM,
            "com.apple.developer.icloud-container-identifiers": [CONTAINER, "iCloud.offline.unused"],
            "com.apple.developer.icloud-services": ["CloudKit", "CloudDocuments"],
            "com.apple.developer.icloud-container-environment": ["Development", "Production"],
            "com.apple.developer.aps-environment": "production",
            "com.apple.security.get-task-allow": False,
            "keychain-access-groups": [f"{PREFIX}.*"],
            "com.apple.developer.ubiquity-kvstore-identifier": f"{PREFIX}.*",
        },
    }


class EntitlementChecks(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2030, 1, 1, tzinfo=timezone.utc)
        self.profile = profile_fixture(self.now)
        self.source = source_fixture()

    def prepare(self):
        return signing.prepare_entitlements(self.profile, self.source, self.now)

    def test_production_entitlements_use_authorized_prefix_and_retain_sandbox_group(self):
        before_profile, before_source = deepcopy(self.profile), deepcopy(self.source)
        result = self.prepare()
        self.assertEqual(result[signing.APP_IDENTIFIER], f"{PREFIX}.{BUNDLE}")
        self.assertNotEqual(PREFIX, TEAM)
        self.assertEqual(result[signing.TEAM_IDENTIFIER], TEAM)
        self.assertEqual(result[signing.CLOUD_ENVIRONMENT], "Production")
        self.assertEqual(result[signing.PUSH_ENVIRONMENT], "production")
        self.assertEqual(result[signing.CONTAINERS], [CONTAINER])
        self.assertEqual(result[signing.SERVICES], ["CloudKit"])
        self.assertIs(result["com.apple.security.app-sandbox"], True)
        self.assertIs(result["com.apple.security.network.client"], True)
        self.assertIs(result["com.apple.security.network.server"], True)
        self.assertIs(result["com.apple.security.files.user-selected.read-write"], True)
        self.assertEqual(result["com.apple.security.application-groups"], [GROUP])
        self.assertEqual(set(result), set(self.source) | {signing.APP_IDENTIFIER, signing.TEAM_IDENTIFIER})
        self.assertNotIn(b"$", plistlib.dumps(result))
        self.assertNotIn(CERTIFICATE, plistlib.dumps(result))
        self.assertNotIn(PRIVATE_SENTINEL.encode(), plistlib.dumps(result))
        self.assertEqual(self.profile, before_profile)
        self.assertEqual(self.source, before_source)

    def test_apple_scalar_services_wildcard_does_not_widen_app_entitlements(self):
        self.profile["Entitlements"][signing.SERVICES] = "*"
        result = self.prepare()
        self.assertEqual(result[signing.SERVICES], ["CloudKit"])
        signing.verify_signature(self.profile, self.source, CERTIFICATE, result, self.now)
        result[signing.SERVICES] = ["*"]
        with self.assertRaises(signing.SigningError):
            signing.verify_signature(self.profile, self.source, CERTIFICATE, result, self.now)

    def test_other_services_scalar_and_container_wildcard_remain_rejected(self):
        for value in ("CloudKit", "Cloud*", ["*"], [], None):
            with self.subTest(value=value):
                self.profile["Entitlements"][signing.SERVICES] = value
                with self.assertRaises(signing.SigningError):
                    self.prepare()
        self.profile["Entitlements"][signing.SERVICES] = "*"
        self.profile["Entitlements"][signing.CONTAINERS] = ["*"]
        with self.assertRaises(signing.SigningError):
            self.prepare()

    def test_profile_extras_and_unrestricted_entitlements_are_not_copied(self):
        self.profile["Entitlements"]["com.apple.security.application-groups"] = ["unused.offline.group"]
        self.profile["Entitlements"]["com.apple.security.cs.allow-jit"] = True
        self.assertEqual(self.prepare()["com.apple.security.application-groups"], [GROUP])
        self.assertNotIn("com.apple.security.cs.allow-jit", self.prepare())
        self.assertNotIn("keychain-access-groups", self.prepare())

    def test_accepts_scalar_production_cloud_authorization_and_resolved_source(self):
        self.profile["Entitlements"][signing.CLOUD_ENVIRONMENT] = "Production"
        self.source[signing.CLOUD_ENVIRONMENT] = "Production"
        self.source[signing.PUSH_ENVIRONMENT] = "production"
        self.source[signing.APP_IDENTIFIER] = f"{PREFIX}.{BUNDLE}"
        self.source[signing.TEAM_IDENTIFIER] = TEAM
        self.assertEqual(self.prepare(), self.source)

    def test_every_required_source_entitlement_is_required(self):
        for key in source_fixture():
            with self.subTest(key=key):
                self.source = source_fixture()
                del self.source[key]
                with self.assertRaises(signing.SigningError):
                    self.prepare()

    def test_wrong_or_widened_source_values_fail(self):
        cases = {
            "com.apple.security.app-sandbox": [False, 1],
            "com.apple.security.network.client": [False, "true"],
            "com.apple.security.network.server": [False, "true"],
            "com.apple.security.files.user-selected.read-write": [False],
            "com.apple.security.application-groups": [["other.group"], [GROUP, "other.group"]],
            signing.CONTAINERS: [["iCloud.wrong"], [CONTAINER, "iCloud.extra"], CONTAINER],
            signing.SERVICES: [["CloudDocuments"], ["CloudKit", "CloudDocuments"]],
            signing.CLOUD_ENVIRONMENT: ["Development", "production", ["Production"]],
            signing.PUSH_ENVIRONMENT: ["development", "Production", ["production"]],
        }
        for key, values in cases.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    self.source = source_fixture()
                    self.source[key] = value
                    with self.assertRaises(signing.SigningError):
                        self.prepare()

    def test_unresolved_placeholders_are_not_expanded_or_signed(self):
        cases = {
            signing.CLOUD_ENVIRONMENT: "$(UNKNOWN_ENVIRONMENT)",
            signing.PUSH_ENVIRONMENT: "${APS_ENVIRONMENT}",
            signing.CONTAINERS: ["$(ICLOUD_CONTAINER_IDENTIFIER)"],
            "com.apple.security.application-groups": ["$(AppIdentifierPrefix)solimanali.openlist"],
            signing.APP_IDENTIFIER: "$(AppIdentifierPrefix)solimanali.openlist",
            signing.TEAM_IDENTIFIER: "$(DEVELOPMENT_TEAM)",
        }
        for key, value in cases.items():
            with self.subTest(key=key):
                self.source = source_fixture()
                self.source[key] = value
                with self.assertRaises(signing.SigningError):
                    self.prepare()

    def test_unsafe_unreviewed_and_ios_source_keys_fail(self):
        for key in (
            "get-task-allow",
            "com.apple.security.get-task-allow",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.cs.allow-jit",
            "aps-environment",
            "application-identifier",
            "keychain-access-groups",
            "unreviewed.capability",
        ):
            with self.subTest(key=key):
                self.source = source_fixture()
                self.source[key] = True
                with self.assertRaisesRegex(signing.SigningError, "Unreviewed or unsafe"):
                    self.prepare()

    def test_wrong_team_or_app_prefix_fail(self):
        cases = [
            ("TeamIdentifier", ["OTHERTEAM1"]),
            ("TeamIdentifier", TEAM),
            ("ApplicationIdentifierPrefix", ["OTHERPREF1"]),
            ("ApplicationIdentifierPrefix", []),
            ("ApplicationIdentifierPrefix", PREFIX),
        ]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                self.profile = profile_fixture(self.now)
                self.profile[key] = value
                with self.assertRaises(signing.SigningError):
                    self.prepare()
        self.profile = profile_fixture(self.now)
        self.profile["Entitlements"][signing.TEAM_IDENTIFIER] = "OTHERTEAM1"
        with self.assertRaisesRegex(signing.SigningError, "team-identifier"):
            self.prepare()

    def test_explicit_native_app_identifier_is_required(self):
        for value in (None, f"{PREFIX}.*", f"{PREFIX}.other.app", f"{TEAM}.{BUNDLE}", f"$({PREFIX}).{BUNDLE}"):
            with self.subTest(value=value):
                self.profile["Entitlements"][signing.APP_IDENTIFIER] = value
                with self.assertRaises(signing.SigningError):
                    self.prepare()
        self.profile = profile_fixture(self.now)
        del self.profile["Entitlements"][signing.APP_IDENTIFIER]
        self.profile["Entitlements"]["application-identifier"] = f"{PREFIX}.{BUNDLE}"
        with self.assertRaises(signing.SigningError):
            self.prepare()

    def test_profile_must_be_developer_id_for_macos(self):
        cases = [
            ("Platform", ["iOS"]),
            ("Platform", ["OSX", "iOS"]),
            ("Platform", None),
            ("ProvisionsAllDevices", False),
            ("ProvisionsAllDevices", 1),
            ("ProvisionsAllDevices", None),
            ("ProvisionedDevices", []),
            ("ProvisionedDevices", ["offline-device"]),
        ]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                self.profile = profile_fixture(self.now)
                self.profile[key] = value
                with self.assertRaisesRegex(signing.SigningError, "Developer ID profile"):
                    self.prepare()

    def test_expired_missing_invalid_and_future_dates_fail(self):
        for expiry in (self.now, self.now - timedelta(seconds=1), None, "2099-01-01"):
            with self.subTest(expiry=expiry):
                self.profile["ExpirationDate"] = expiry
                with self.assertRaises(signing.SigningError):
                    self.prepare()
        for created in (self.now + timedelta(seconds=1), "invalid"):
            with self.subTest(created=created):
                self.profile = profile_fixture(self.now)
                self.profile["CreationDate"] = created
                with self.assertRaises(signing.SigningError):
                    self.prepare()

    def test_naive_plist_dates_are_utc(self):
        expected = self.prepare()
        self.profile["CreationDate"] = self.profile["CreationDate"].replace(tzinfo=None)
        self.profile["ExpirationDate"] = self.profile["ExpirationDate"].replace(tzinfo=None)
        self.assertEqual(self.prepare(), expected)

    def test_cloud_container_and_service_must_be_explicitly_authorized(self):
        cases = [
            (signing.CONTAINERS, None),
            (signing.CONTAINERS, ["iCloud.wrong"]),
            (signing.CONTAINERS, ["iCloud.*"]),
            (signing.CONTAINERS, CONTAINER),
            (signing.CONTAINERS, [CONTAINER, {}]),
            (signing.SERVICES, []),
            (signing.SERVICES, ["CloudDocuments"]),
            (signing.SERVICES, ["*"]),
            (signing.SERVICES, "CloudKit"),
        ]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                self.profile = profile_fixture(self.now)
                self.profile["Entitlements"][key] = value
                with self.assertRaisesRegex(signing.SigningError, "does not authorize"):
                    self.prepare()

    def test_profile_production_cloud_and_native_push_are_required(self):
        for environment in ("Development", "production", ["Development"], ["Production", "*"], [], None):
            with self.subTest(environment=environment):
                self.profile = profile_fixture(self.now)
                self.profile["Entitlements"][signing.CLOUD_ENVIRONMENT] = environment
                with self.assertRaisesRegex(signing.SigningError, "Production iCloud"):
                    self.prepare()
        for environment in ("development", "Production", ["production"], None):
            with self.subTest(push=environment):
                self.profile = profile_fixture(self.now)
                self.profile["Entitlements"][signing.PUSH_ENVIRONMENT] = environment
                self.profile["Entitlements"]["aps-environment"] = "production"
                with self.assertRaisesRegex(signing.SigningError, "native macOS push"):
                    self.prepare()

    def test_profile_debug_entitlements_cannot_be_enabled(self):
        for key in ("get-task-allow", "com.apple.security.get-task-allow"):
            for value in (True, "false", 0):
                with self.subTest(key=key, value=value):
                    self.profile = profile_fixture(self.now)
                    self.profile["Entitlements"][key] = value
                    with self.assertRaisesRegex(signing.SigningError, "get-task-allow"):
                        self.prepare()

    def test_certificate_allowlist_is_required(self):
        for certificates in (None, [], CERTIFICATE, [""], [b""]):
            with self.subTest(certificates=certificates):
                self.profile["DeveloperCertificates"] = certificates
                with self.assertRaisesRegex(signing.SigningError, "DeveloperCertificates"):
                    self.prepare()

    def test_each_authorized_leaf_certificate_passes(self):
        for certificate in (CERTIFICATE, OTHER_CERTIFICATE):
            signing.verify_signature(self.profile, self.source, certificate, self.prepare(), self.now)

    def test_mismatched_or_empty_leaf_certificate_fails(self):
        for certificate in (b"OTHER UNAUTHORIZED OFFLINE CERTIFICATE", b""):
            with self.assertRaisesRegex(signing.SigningError, "Signing certificate is not authorized"):
                signing.verify_signature(self.profile, self.source, certificate, self.prepare(), self.now)

    def test_signed_entitlements_must_match_exactly(self):
        valid = self.prepare()
        cases = [[], {}, dict(valid, **{"com.apple.security.app-sandbox": 1})]
        for key, value in (
            (signing.CLOUD_ENVIRONMENT, "$(ICLOUD_CONTAINER_ENVIRONMENT)"),
            (signing.PUSH_ENVIRONMENT, "development"),
            (signing.APP_IDENTIFIER, f"{TEAM}.{BUNDLE}"),
            ("com.apple.security.get-task-allow", True),
            (signing.CONTAINERS, [CONTAINER, "iCloud.extra"]),
        ):
            cases.append(dict(valid, **{key: value}))
        for signed in cases:
            with self.subTest(signed=signed):
                with self.assertRaisesRegex(signing.SigningError, "Signed app entitlements differ"):
                    signing.verify_signature(self.profile, self.source, CERTIFICATE, signed, self.now)

    def test_profile_and_source_must_be_dictionaries(self):
        for profile, source in (([], self.source), (self.profile, [])):
            with self.assertRaisesRegex(signing.SigningError, "plist dictionaries"):
                signing.prepare_entitlements(profile, source, self.now)


class CommandChecks(unittest.TestCase):
    def setUp(self):
        # Never use system temporary directories or discover local signing material.
        self.work = Path("build/signing-checks") / f"case-{uuid4().hex}"
        self.work.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, self.work)
        self.profile = profile_fixture()
        self.profile_path = self.work / "offline.provisionprofile"
        self.profile_path.write_bytes(ORIGINAL_CMS)
        self.source_path = self.work / "source.entitlements"
        self.source_path.write_bytes(plistlib.dumps(source_fixture()))
        self.app = self.work / "offline.app"
        (self.app / "Contents").mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": BUNDLE}))
        self.output = self.work / "signing/openlist.entitlements"
        self.embedded = self.app / "Contents/embedded.provisionprofile"
        self.signed_path = self.work / "signed.entitlements"
        self.certificate_path = self.work / "signing-cert-0"

    def run_helper(self, command="prepare", result=None, failure=None):
        args = [
            command, "--profile", str(self.profile_path),
            "--source-entitlements", str(self.source_path),
        ]
        if command == "prepare":
            args += ["--app", str(self.app), "--output-entitlements", str(self.output)]
        else:
            args += ["--signed-entitlements", str(self.signed_path), "--signing-certificate", str(self.certificate_path)]
        if result is None:
            result = subprocess.CompletedProcess([], 0, plistlib.dumps(self.profile), PRIVATE_SENTINEL.encode())
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(signing.subprocess, "run", return_value=result, side_effect=failure) as cms:
            with redirect_stdout(stdout), redirect_stderr(stderr):
                status = signing.main(args)
        return status, stdout.getvalue(), stderr.getvalue(), cms

    def assert_no_artifacts(self):
        self.assertFalse(self.output.exists())
        self.assertFalse(self.embedded.exists())

    def test_prepare_embeds_original_cms_and_writes_only_minimal_entitlements(self):
        status, stdout, stderr, cms = self.run_helper()
        self.assertEqual(status, 0, stderr)
        cms.assert_called_once_with(
            ["/usr/bin/security", "cms", "-D"],
            input=ORIGINAL_CMS, capture_output=True, timeout=30, check=False,
        )
        self.assertEqual(self.embedded.read_bytes(), ORIGINAL_CMS)
        expected = signing.prepare_entitlements(self.profile, source_fixture())
        self.assertEqual(plistlib.loads(self.output.read_bytes()), expected)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.embedded.stat().st_mode), 0o644)
        self.assertNotIn(PRIVATE_SENTINEL, stdout + stderr + self.output.read_text())
        self.assertNotIn(CERTIFICATE.decode(), stdout + stderr + self.output.read_text())
        self.assertEqual(self.profile_path.read_bytes(), ORIGINAL_CMS)
        self.assertEqual(plistlib.loads(self.source_path.read_bytes()), source_fixture())

    def test_missing_or_empty_profile_fails_without_running_security(self):
        self.profile_path.unlink()
        status, _, stderr, cms = self.run_helper()
        self.assertEqual(status, 1)
        self.assertIn("APP_PROVISION_PROFILE", stderr)
        cms.assert_not_called()
        self.assert_no_artifacts()
        self.profile_path.write_bytes(b"")
        status, _, stderr, cms = self.run_helper()
        self.assertEqual(status, 1)
        self.assertIn("empty", stderr)
        cms.assert_not_called()
        self.assert_no_artifacts()

    def test_cms_failure_does_not_dump_profile_or_process_output(self):
        result = subprocess.CompletedProcess([], 1, PRIVATE_SENTINEL.encode(), PRIVATE_SENTINEL.encode())
        status, stdout, stderr, _ = self.run_helper(result=result)
        self.assertEqual(status, 1)
        self.assertIn("security cms failed", stderr)
        self.assertNotIn(PRIVATE_SENTINEL, stdout + stderr)
        self.assert_no_artifacts()

    def test_unavailable_or_timed_out_decoder_fails_without_dumping_diagnostics(self):
        for failure in (
            OSError(PRIVATE_SENTINEL),
            subprocess.TimeoutExpired("security", 30, output=PRIVATE_SENTINEL.encode(), stderr=PRIVATE_SENTINEL.encode()),
        ):
            with self.subTest(failure=type(failure).__name__):
                status, stdout, stderr, _ = self.run_helper(failure=failure)
                self.assertEqual(status, 1)
                self.assertIn("Cannot run security cms", stderr)
                self.assertNotIn(PRIVATE_SENTINEL, stdout + stderr)
                self.assert_no_artifacts()

    def test_malformed_decoded_profile_is_rejected_without_dumping_it(self):
        for payload in (PRIVATE_SENTINEL.encode(), b"<plist><dict>", plistlib.dumps([])):
            with self.subTest(payload=payload):
                status, stdout, stderr, _ = self.run_helper(result=subprocess.CompletedProcess([], 0, payload, b""))
                self.assertEqual(status, 1)
                self.assertIn("Decoded provisioning profile", stderr)
                self.assertNotIn(PRIVATE_SENTINEL, stdout + stderr)
                self.assert_no_artifacts()

    def test_expired_profile_produces_no_signing_artifacts(self):
        self.profile["ExpirationDate"] = datetime.now(timezone.utc) - timedelta(days=1)
        status, _, stderr, _ = self.run_helper()
        self.assertEqual(status, 1)
        self.assertIn("expired", stderr)
        self.assert_no_artifacts()

    def test_wrong_built_app_is_rejected_before_writing(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "offline.wrong"}))
        status, _, stderr, _ = self.run_helper()
        self.assertEqual(status, 1)
        self.assertIn("Built app", stderr)
        self.assert_no_artifacts()

    def test_bad_source_cannot_leave_signable_artifacts(self):
        for payload in (b"invalid", plistlib.dumps({"unreviewed.entitlement": PRIVATE_SENTINEL})):
            with self.subTest(payload=payload):
                self.source_path.write_bytes(payload)
                status, stdout, stderr, _ = self.run_helper()
                self.assertEqual(status, 1)
                self.assertNotIn(PRIVATE_SENTINEL, stdout + stderr)
                self.assert_no_artifacts()

    def test_output_cannot_overwrite_source(self):
        self.output = self.source_path
        original = self.source_path.read_bytes()
        status, _, stderr, _ = self.run_helper()
        self.assertEqual(status, 1)
        self.assertIn("must not overwrite", stderr)
        self.assertEqual(self.source_path.read_bytes(), original)
        self.assertFalse(self.embedded.exists())

    def test_verify_uses_extracted_public_certificate_and_does_not_write(self):
        self.signed_path.write_bytes(plistlib.dumps(signing.prepare_entitlements(self.profile, source_fixture())))
        self.certificate_path.write_bytes(CERTIFICATE)
        status, _, stderr, _ = self.run_helper("verify")
        self.assertEqual(status, 0, stderr)
        self.assert_no_artifacts()
        self.certificate_path.write_bytes(b"UNAUTHORIZED OFFLINE CERTIFICATE")
        status, _, stderr, _ = self.run_helper("verify")
        self.assertEqual(status, 1)
        self.assertIn("Signing certificate is not authorized", stderr)
        self.assert_no_artifacts()


class PipelineChecks(unittest.TestCase):
    def test_ci_and_release_select_latest_stable_hosted_xcode(self):
        for name in ("ci.yml", "release.yml"):
            with self.subTest(workflow=name):
                workflow = (TOOLS.parent / ".github/workflows" / name).read_text()
                self.assertIn("runs-on: macos-latest", workflow)
                self.assertRegex(workflow, r"uses: maxim-lobanov/setup-xcode@[0-9a-f]{40}\b")
                self.assertIn("xcode-version: latest-stable", workflow)
                self.assertNotIn("DEVELOPER_DIR:", workflow)
                self.assertLess(workflow.index("xcode-version: latest-stable"), workflow.index("./Tools/check.sh"))
                self.assertIn("xcodebuild -version && swift --version && uname -m", workflow)

    def test_checked_in_app_entitlements_match_the_release_policy(self):
        source = plistlib.loads((TOOLS.parent / "Config/openlist.entitlements").read_bytes())
        resolved = signing.prepare_entitlements(profile_fixture(), source)
        self.assertEqual(resolved[signing.CONTAINERS], [CONTAINER])
        self.assertEqual(resolved[signing.CLOUD_ENVIRONMENT], "Production")
        self.assertEqual(resolved[signing.PUSH_ENVIRONMENT], "production")
        self.assertIs(resolved["com.apple.security.network.server"], True)

    def test_packaging_prepares_before_signing_and_verifies_before_notarization(self):
        script = (TOOLS / "package-release.sh").read_text()
        self.assertIn('${APP_PROVISION_PROFILE:?', script)
        self.assertLess(script.index("prepare-release-signing.py prepare"), script.index("for component in"))
        helper = script.index('"$APP/Contents/MacOS/openlist-mcp"')
        self.assertLess(script.index("prepare-release-signing.py prepare"), helper)
        self.assertLess(helper, script.index("for component in"))
        self.assertLess(script.index("prepare-release-signing.py verify"), script.index("xcrun notarytool submit"))
        self.assertIn('--profile "$APP/Contents/embedded.provisionprofile"', script)
        self.assertIn('--signing-certificate "$SIGNING_DIR/signing-cert-0"', script)
        self.assertIn('codesign --display --extract-certificates="$SIGNING_DIR/signing-cert-" "$APP"', script)
        self.assertIn('entitlements="Config/OpenlistWidget.entitlements"', script)
        self.assertIn('entitlements="$SIGNING_DIR/openlist.entitlements"', script)
        self.assertIn('for component in OpenlistWidget openlist', script)

    def test_ci_requires_profile_secret_and_cleans_up_only_its_named_file(self):
        workflow = (TOOLS.parent / ".github/workflows/release.yml").read_text()
        self.assertIn("secrets.MACOS_APP_PROVISION_PROFILE_BASE64", workflow)
        self.assertIn('${APP_PROFILE:?Missing MACOS_APP_PROVISION_PROFILE_BASE64}', workflow)
        self.assertIn("APP_PROVISION_PROFILE: ${{ runner.temp }}/openlist.provisionprofile", workflow)
        profile_write = 'printf \'%s\' "$APP_PROFILE" | base64 --decode > "$RUNNER_TEMP/openlist.provisionprofile"'
        self.assertLess(workflow.index("umask 077"), workflow.index(profile_write))
        self.assertIn(
            'rm -f "$RUNNER_TEMP/certificate.p12" "$RUNNER_TEMP/notary.p8" "$RUNNER_TEMP/openlist.provisionprofile"',
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
