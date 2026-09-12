#!/usr/bin/env python3
"""Prepare and check native macOS Developer ID entitlements without private keys."""

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from xml.parsers.expat import ExpatError


BUNDLE_ID = "solimanali.openlist"
TEAM_ID = "Y5UE64R7TQ"
APP_GROUP = "Y5UE64R7TQ.solimanali.openlist"
CONTAINER_ID = "iCloud.solimanali.openlist"
APP_IDENTIFIER = "com.apple.application-identifier"
TEAM_IDENTIFIER = "com.apple.developer.team-identifier"
CONTAINERS = "com.apple.developer.icloud-container-identifiers"
SERVICES = "com.apple.developer.icloud-services"
CLOUD_ENVIRONMENT = "com.apple.developer.icloud-container-environment"
PUSH_ENVIRONMENT = "com.apple.developer.aps-environment"
SOURCE_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.network.client": True,
    "com.apple.security.network.server": True,
    "com.apple.security.application-groups": [APP_GROUP],
    CONTAINERS: [CONTAINER_ID],
    SERVICES: ["CloudKit"],
}
ENVIRONMENTS = {
    CLOUD_ENVIRONMENT: ("$(ICLOUD_CONTAINER_ENVIRONMENT)", "Production"),
    PUSH_ENVIRONMENT: ("$(APS_ENVIRONMENT)", "production"),
}


class SigningError(ValueError):
    pass


def utc(value, label):
    if not isinstance(value, datetime):
        raise SigningError(f"{label} must be a plist date.")
    # plistlib reads plist dates as naive UTC on older Python versions.
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def authorized_values(entitlements, key, required):
    values = entitlements.get(key)
    if (
        not isinstance(values, list)
        or not values
        or any(not isinstance(value, str) or not value for value in values)
        or not set(required).issubset(values)
    ):
        raise SigningError(f"Profile does not authorize the required {key}; regenerate the Developer ID profile.")


def prepare_entitlements(profile, source, now=None):
    """Accept a decoded profile for offline checks; claim only reviewed app entitlements."""
    if not isinstance(profile, dict) or not isinstance(source, dict):
        raise SigningError("Profile and source entitlements must be plist dictionaries.")
    now = utc(now or datetime.now(timezone.utc), "Current time")
    expiry = utc(profile.get("ExpirationDate"), "Profile ExpirationDate")
    if expiry <= now:
        raise SigningError("Provisioning profile has expired; generate a new Developer ID profile.")
    if "CreationDate" in profile:
        created = utc(profile["CreationDate"], "Profile CreationDate")
        if created > now or created >= expiry:
            raise SigningError("Provisioning profile is not yet valid or has an invalid validity interval.")
    # TN3125: Developer ID profiles provision all devices, unlike development/App Store profiles.
    if (
        profile.get("Platform") != ["OSX"]
        or profile.get("ProvisionsAllDevices") is not True
        or "ProvisionedDevices" in profile
    ):
        raise SigningError("Use a macOS Developer ID profile (OSX, ProvisionsAllDevices=true, no device list).")
    if profile.get("TeamIdentifier") != [TEAM_ID]:
        raise SigningError(f"Provisioning profile must belong to team {TEAM_ID}.")
    allowed = profile.get("Entitlements")
    if not isinstance(allowed, dict):
        raise SigningError("Provisioning profile has no valid Entitlements dictionary.")
    if allowed.get(TEAM_IDENTIFIER) != TEAM_ID:
        raise SigningError(f"Profile must authorize {TEAM_IDENTIFIER} for team {TEAM_ID}.")
    for key in ("get-task-allow", "com.apple.security.get-task-allow"):
        if key in allowed and allowed[key] is not False:
            raise SigningError("A release profile must not enable get-task-allow.")

    prefixes = profile.get("ApplicationIdentifierPrefix")
    app_identifier = allowed.get(APP_IDENTIFIER)
    if (
        not isinstance(prefixes, list)
        or not prefixes
        or any(not isinstance(prefix, str) or not prefix for prefix in prefixes)
        or not isinstance(app_identifier, str)
        or "*" in app_identifier
        or "$" in app_identifier
    ):
        raise SigningError("Profile must authorize an explicit native macOS App ID and its App ID prefix.")
    prefix, separator, bundle_id = app_identifier.partition(".")
    if not separator or prefix not in prefixes or bundle_id != BUNDLE_ID:
        raise SigningError(f"Profile App ID/prefix must authorize exactly {BUNDLE_ID}, not a wildcard or another app.")

    certificates = profile.get("DeveloperCertificates")
    if (
        not isinstance(certificates, list)
        or not certificates
        or any(not isinstance(certificate, bytes) or not certificate for certificate in certificates)
    ):
        raise SigningError("Profile has no DeveloperCertificates; regenerate it with the release signing certificate.")
    authorized_values(allowed, CONTAINERS, [CONTAINER_ID])
    authorized_values(allowed, SERVICES, ["CloudKit"])
    cloud_environment = allowed.get(CLOUD_ENVIRONMENT)
    if isinstance(cloud_environment, list):
        if (
            not cloud_environment
            or any(value not in ("Development", "Production") for value in cloud_environment)
            or "Production" not in cloud_environment
        ):
            raise SigningError("Profile must authorize the Production iCloud container environment.")
    elif cloud_environment != "Production":
        raise SigningError("Profile must authorize the Production iCloud container environment.")
    if allowed.get(PUSH_ENVIRONMENT) != "production":
        raise SigningError("Profile must authorize native macOS push notifications in production.")

    reviewed_keys = set(SOURCE_ENTITLEMENTS) | set(ENVIRONMENTS) | {APP_IDENTIFIER, TEAM_IDENTIFIER}
    if set(source) - reviewed_keys:
        raise SigningError("Unreviewed or unsafe source entitlement; update the release signing policy explicitly.")
    for key, expected in SOURCE_ENTITLEMENTS.items():
        if type(source.get(key)) is not type(expected) or source.get(key) != expected:
            raise SigningError(f"Source entitlement {key} must match the reviewed release value.")
    resolved = dict(source)
    for key, (placeholder, production) in ENVIRONMENTS.items():
        if source.get(key) not in (placeholder, production):
            raise SigningError(f"Source entitlement {key} must use its known build placeholder or production value.")
        resolved[key] = production
    for key, value in ((APP_IDENTIFIER, app_identifier), (TEAM_IDENTIFIER, allowed[TEAM_IDENTIFIER])):
        if key in source and source[key] != value:
            raise SigningError(f"Source entitlement {key} conflicts with the provisioning profile.")
        resolved[key] = value
    # Sandbox and team-prefixed macOS App Groups are unrestricted (TN3125).
    # Do not copy the profile's other capabilities, wildcard grants, or metadata.
    return resolved


def verify_signature(profile, source, certificate, signed_entitlements, now=None):
    expected = prepare_entitlements(profile, source, now)
    if not certificate or certificate not in profile["DeveloperCertificates"]:
        raise SigningError("Signing certificate is not authorized by the embedded profile; regenerate it for this identity.")
    if (
        not isinstance(signed_entitlements, dict)
        or signed_entitlements != expected
        or any(type(signed_entitlements[key]) is not type(value) for key, value in expected.items())
    ):
        raise SigningError("Signed app entitlements differ from the validated release entitlements; refuse publication.")


def read_bytes(path, label):
    try:
        data = path.read_bytes()
    except OSError as error:
        raise SigningError(f"Cannot read {label}; supply an existing, readable file.") from error
    if not data:
        raise SigningError(f"{label} is empty; supply a valid file.")
    return data


def decode_plist(data, label):
    try:
        value = plistlib.loads(data)
    except (plistlib.InvalidFileException, ExpatError, ValueError, TypeError, OverflowError) as error:
        raise SigningError(f"{label} is not a valid plist.") from error
    if not isinstance(value, dict):
        raise SigningError(f"{label} must be a plist dictionary.")
    return value


def read_profile(path):
    original = read_bytes(path, "APP_PROVISION_PROFILE (original Apple-issued .provisionprofile)")
    try:
        result = subprocess.run(
            ["/usr/bin/security", "cms", "-D"],
            input=original,
            capture_output=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SigningError("Cannot run security cms; use macOS and an original Apple-issued provisioning profile.") from error
    if result.returncode:
        raise SigningError(
            f"security cms failed (exit {result.returncode}); supply the original Apple-issued Developer ID profile, "
            "not a decoded plist or base64 text."
        )
    return original, decode_plist(result.stdout, "Decoded provisioning profile")


def write_file(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(descriptor, "wb") as output:
        os.fchmod(output.fileno(), mode)
        output.write(data)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("prepare", help="Validate, embed the original profile, and resolve release entitlements")
    verify = commands.add_parser("verify", help="Check the signed app's extracted public certificate and entitlements")
    for command in (prepare, verify):
        command.add_argument("--profile", required=True, type=Path)
        command.add_argument("--source-entitlements", required=True, type=Path)
    prepare.add_argument("--app", required=True, type=Path)
    prepare.add_argument("--output-entitlements", required=True, type=Path)
    verify.add_argument("--signed-entitlements", required=True, type=Path)
    verify.add_argument("--signing-certificate", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        original, profile = read_profile(args.profile)
        source = decode_plist(read_bytes(args.source_entitlements, "Source entitlements"), "Source entitlements")
        if args.command == "prepare":
            entitlements = prepare_entitlements(profile, source)
            info = decode_plist(read_bytes(args.app / "Contents/Info.plist", "App Info.plist"), "App Info.plist")
            if info.get("CFBundleIdentifier") != BUNDLE_ID:
                raise SigningError(f"Built app must have bundle identifier {BUNDLE_ID}.")
            if args.output_entitlements.resolve() in (args.source_entitlements.resolve(), args.profile.resolve()):
                raise SigningError("Output entitlements must not overwrite source entitlements or the original profile.")
            write_file(args.output_entitlements, plistlib.dumps(entitlements), 0o600)
            write_file(args.app / "Contents/embedded.provisionprofile", original, 0o644)
            print("Validated Developer ID profile; embedded original profile and prepared Production release entitlements.")
        else:
            signed = decode_plist(read_bytes(args.signed_entitlements, "Signed entitlements"), "Signed entitlements")
            certificate = read_bytes(args.signing_certificate, "Extracted signing certificate")
            verify_signature(profile, source, certificate, signed)
            print("Verified profile authorization for the signed app's public certificate and release entitlements.")
    except (SigningError, OSError) as error:
        message = str(error) if isinstance(error, SigningError) else "Cannot write signing artifacts; check output permissions."
        print(f"Release signing error: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
