#!/usr/bin/env python3
"""Adds the iPhone companion's targets to openlist.xcodeproj and keeps their
shared-file membership in step with Tools/iOS/shared-sources.txt.

    python3 Tools/add-ios-targets.py           # add the targets, then sync membership
    python3 Tools/add-ios-targets.py --check   # exit 1 if the project and the seed disagree

objectVersion 77 synchronized folders have no per-file entries. Each iOS
target owns its own folder; the app and widget also own Shared/ and
SharediOS/ wholesale. Single files from the folders the Mac targets own
(openlist/, OpenlistWidget/) join an iOS target through a
PBXFileSystemSynchronizedBuildFileExceptionSet on that folder: for a target
that does not list the folder in its fileSystemSynchronizedGroups,
membershipExceptions is an allow-list of exact file paths (directories and
globs are ignored). New Mac files therefore never reach iOS until the seed
names them.

Targets are added once; later runs leave their build settings alone (edit
those in Xcode) and only rewrite the exception sets from the seed, so the
seed stays the one list to edit. Every edit asserts its anchor appears
exactly once, so a project that changed shape fails loudly instead of being
half-edited, and the result must pass `plutil -lint` before it is written.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "openlist.xcodeproj/project.pbxproj"
MANIFEST = ROOT / "Tools/iOS/shared-sources.txt"
TEAM = "Y5UE64R7TQ"

# Existing objects in project.pbxproj.
PROJECT_OBJ = "41362FCD304B659900C93862"
PROJECT_CONFIG_LIST = "41362FD0304B659900C93862"
PRODUCTS_GROUP = "41362FD6304B659900C93862"
SHARED_GROUP = "41362FF0304B659900C93862"
MCP_TARGET = "4D4350480000000000000001"
# Folders owned by Mac targets that may lend single files to iOS targets.
LENDING_GROUPS = {"openlist": "41362FD7304B659900C93862", "OpenlistWidget": "41362FF1304B659900C93862"}


def oid(n):
    return f"0A105100000000000000{n:04X}"


APP, WIDGET, TESTS, UITESTS = "OpenlistiOS", "OpenlistiOSWidget", "OpenlistiOSTests", "OpenlistiOSUITests"
IDS = dict(
    g_app=oid(0x01), g_widget=oid(0x02), g_tests=oid(0x03), g_uitests=oid(0x04), g_shared_ios=oid(0x05),
    p_app=oid(0x10), p_widget=oid(0x11), p_tests=oid(0x12), p_uitests=oid(0x13),
    t_app=oid(0x20), t_widget=oid(0x21), t_tests=oid(0x22), t_uitests=oid(0x23),
    app_src=oid(0x30), app_fw=oid(0x31), app_res=oid(0x32), app_embed=oid(0x33),
    w_src=oid(0x34), w_fw=oid(0x35), w_res=oid(0x36),
    ut_src=oid(0x37), ut_fw=oid(0x38), ut_res=oid(0x39),
    ui_src=oid(0x3A), ui_fw=oid(0x3B), ui_res=oid(0x3C),
    embed_file=oid(0x40),
    px_widget=oid(0x50), px_tests=oid(0x51), px_uitests=oid(0x52),
    dep_widget=oid(0x60), dep_tests=oid(0x61), dep_uitests=oid(0x62),
    cl_app=oid(0x70), cl_widget=oid(0x71), cl_tests=oid(0x72), cl_uitests=oid(0x73),
)
CONFIGS = ("Debug", "Dev", "Release")
CONFIG_IDS = {
    "app": dict(zip(CONFIGS, (oid(0x80), oid(0x81), oid(0x82)))),
    "widget": dict(zip(CONFIGS, (oid(0x83), oid(0x84), oid(0x85)))),
    "tests": dict(zip(CONFIGS, (oid(0x86), oid(0x87), oid(0x88)))),
    "uitests": dict(zip(CONFIGS, (oid(0x89), oid(0x8A), oid(0x8B)))),
}
TARGET_IDS = {APP: IDS["t_app"], WIDGET: IDS["t_widget"]}
EXCEPTION_IDS = {("openlist", APP): oid(0x90), ("OpenlistWidget", WIDGET): oid(0x91),
                 ("openlist", WIDGET): oid(0x92), ("OpenlistWidget", APP): oid(0x93)}
EXCEPTION_SECTION = "PBXFileSystemSynchronizedBuildFileExceptionSet"


def once(text, old, new):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one anchor, found {count}: {old[:100]!r}")
    return text.replace(old, new, 1)


def before(text, marker, addition):
    return once(text, marker, addition + marker)


def q(value):
    return value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else '"' + value.replace('"', '\\"') + '"'


def object_pattern(ident):
    return re.compile(rf"^\t\t{ident} /\*[^\n]*?\*/ = \{{\n.*?^\t\t\}};\n", re.S | re.M)


# MARK: - Seed

def read_manifest():
    """{(group, target): [path, ...]} from the seed, validated against the tree."""
    membership, seen = {}, set()
    for number, raw in enumerate(MANIFEST.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) != 3:
            raise SystemExit(f"{MANIFEST.name}:{number}: expected '<target> <group> <path>'")
        target, group, path = fields
        if target not in TARGET_IDS:
            raise SystemExit(f"{MANIFEST.name}:{number}: unknown target {target} (expected {' or '.join(TARGET_IDS)})")
        if group not in LENDING_GROUPS:
            raise SystemExit(f"{MANIFEST.name}:{number}: {group} is not a folder the Mac targets own "
                             f"({', '.join(LENDING_GROUPS)}); iOS targets already own Shared/ and SharediOS/")
        if not (ROOT / group / path).exists():
            raise SystemExit(f"{MANIFEST.name}:{number}: {group}/{path} does not exist")
        if (target, group, path) in seen:
            raise SystemExit(f"{MANIFEST.name}:{number}: {target} {group} {path} is listed twice")
        seen.add((target, group, path))
        membership.setdefault((group, target), []).append(path)
    return membership


# MARK: - Target generation (first run only)

COMMON_IOS = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": TEAM,
    "GENERATE_INFOPLIST_FILE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "27.0",
    "MARKETING_VERSION": "0.1.0",
    # Keep the product (and so the module) name fixed in every configuration:
    # the Mac's Dev rename would turn the module into Openlist_Dev and break
    # `@testable import OpenlistiOS`.
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    # Otherwise an Apple silicon Mac could run a second, iPhone-flavoured
    # Openlist against the same CloudKit container.
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "TARGETED_DEVICE_FAMILY": "1",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
    "SWIFT_VERSION": "6.0",
}
COPYRIGHT = "Copyright © 2026 Ali Soliman. MIT License."
CALENDAR = ("Openlist reads your calendars to schedule tasks around busy events. "
            "It never creates, changes, or deletes calendar events.")


def app_settings(name):
    dev = name == "Dev"
    settings = dict(COMMON_IOS)
    settings.update({
        "ASSETCATALOG_COMPILER_APPICON_NAME": "OpenlistDev" if dev else "Openlist",
        "CODE_SIGN_ENTITLEMENTS": f"Config/{'OpenlistiOSDev' if dev else 'OpenlistiOS'}.entitlements",
        "ENABLE_PREVIEWS": "YES",
        "INFOPLIST_FILE": f"Config/{'OpenlistiOSDev' if dev else 'OpenlistiOS'}-Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": "Openlist Dev" if dev else "Openlist",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
        "INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription": CALENDAR,
        "INFOPLIST_KEY_NSHumanReadableCopyright": COPYRIGHT,
        "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "PRODUCT_BUNDLE_IDENTIFIER": "solimanali.openlist.ios.dev" if dev else "solimanali.openlist.ios",
        "REGISTER_APP_GROUPS": "YES",
        "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
        # Must match the Mac app, so shared files infer the same isolation.
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    })
    if not dev:
        # Also fills OpenlistICloudEnvironment in the Info.plist, which is how
        # the app decides whether it may open CloudKit. Dev never syncs.
        settings["APS_ENVIRONMENT"] = "production" if name == "Release" else "development"
        settings["ICLOUD_CONTAINER_ENVIRONMENT"] = "Production" if name == "Release" else "Development"
    return settings


def widget_settings(name):
    dev = name == "Dev"
    settings = dict(COMMON_IOS)
    settings.update({
        "CODE_SIGN_ENTITLEMENTS": f"Config/{'OpenlistiOSDevWidget' if dev else 'OpenlistiOSWidget'}.entitlements",
        "INFOPLIST_FILE": "Config/OpenlistiOSWidget-Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": "Openlist Dev" if dev else "Openlist",
        "INFOPLIST_KEY_NSHumanReadableCopyright": COPYRIGHT,
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
        "PRODUCT_BUNDLE_IDENTIFIER": "solimanali.openlist.ios.dev.widget" if dev else "solimanali.openlist.ios.widget",
        "REGISTER_APP_GROUPS": "YES",
        "SKIP_INSTALL": "YES",
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    })
    return settings


def test_settings(ui):
    settings = dict(COMMON_IOS)
    settings["SWIFT_EMIT_LOC_STRINGS"] = "NO"
    if ui:
        # XCUIApplication's API is main-actor isolated on its own.
        settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "solimanali.openlist.ios.uitests", "TEST_TARGET_NAME": APP})
    else:
        settings.update({
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "PRODUCT_BUNDLE_IDENTIFIER": "solimanali.openlist.ios.tests",
            "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
            "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}",
        })
    return settings


def settings_block(values):
    lines = []
    for key in sorted(values):
        value = values[key]
        if isinstance(value, list):
            items = "".join(f"\t\t\t\t\t{q(v)},\n" for v in value)
            lines.append(f"\t\t\t\t{key} = (\n{items}\t\t\t\t);\n")
        else:
            lines.append(f"\t\t\t\t{key} = {q(str(value))};\n")
    return "".join(lines)


def config(ident, name, values):
    return (f"\t\t{ident} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n"
            f"{settings_block(values)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")


def config_list(ident, name, ids):
    items = "".join(f"\t\t\t\t{ids[c]} /* {c} */,\n" for c in CONFIGS)
    return (f"\t\t{ident} /* Build configuration list for PBXNativeTarget \"{name}\" */ = {{\n"
            f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n{items}\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")


def phase(ident, isa, name):
    return (f"\t\t{ident} /* {name} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")


def sync_group(ident, path):
    return (f"\t\t{ident} /* {path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
            f"\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")


def native_target(ident, name, config_list_id, phases, deps, groups, product, product_name, product_type):
    phase_lines = "".join(f"\t\t\t\t{p} /* {n} */,\n" for p, n in phases)
    dep_lines = "".join(f"\t\t\t\t{d} /* PBXTargetDependency */,\n" for d in deps)
    group_lines = "".join(f"\t\t\t\t{g} /* {n} */,\n" for g, n in groups)
    return (f"\t\t{ident} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {config_list_id} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
            f"\t\t\tbuildPhases = (\n{phase_lines}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
            f"\t\t\tdependencies = (\n{dep_lines}\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n{group_lines}\t\t\t);\n"
            f"\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {name};\n"
            f"\t\t\tproductReference = {product} /* {product_name} */;\n\t\t\tproductType = \"{product_type}\";\n\t\t}};\n")


def add_targets(src):
    # Products.
    src = before(src, "/* End PBXFileReference section */",
        f'\t\t{IDS["p_app"]} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
        f'\t\t{IDS["p_widget"]} /* {WIDGET}.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {WIDGET}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
        f'\t\t{IDS["p_tests"]} /* {TESTS}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TESTS}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
        f'\t\t{IDS["p_uitests"]} /* {UITESTS}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {UITESTS}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n')

    # Embed the widget in the iOS app (PlugIns: dstSubfolderSpec 13), as the Mac app embeds its own.
    src = before(src, "/* End PBXBuildFile section */",
        f'\t\t{IDS["embed_file"]} /* {WIDGET}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {IDS["p_widget"]} /* {WIDGET}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n')
    src = before(src, "/* End PBXCopyFilesBuildPhase section */",
        f'\t\t{IDS["app_embed"]} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n'
        f'\t\t\t\t{IDS["embed_file"]} /* {WIDGET}.appex in Embed Foundation Extensions */,\n\t\t\t);\n'
        f'\t\t\tname = "Embed Foundation Extensions";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n')

    # Dependencies: the app builds its widget; both test bundles build the app.
    proxies, deps = "", ""
    for proxy, dep, target, name in ((IDS["px_widget"], IDS["dep_widget"], IDS["t_widget"], WIDGET),
                                     (IDS["px_tests"], IDS["dep_tests"], IDS["t_app"], APP),
                                     (IDS["px_uitests"], IDS["dep_uitests"], IDS["t_app"], APP)):
        proxies += (f"\t\t{proxy} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
                    f"\t\t\tcontainerPortal = {PROJECT_OBJ} /* Project object */;\n\t\t\tproxyType = 1;\n"
                    f"\t\t\tremoteGlobalIDString = {target};\n\t\t\tremoteInfo = {name};\n\t\t}};\n")
        deps += (f"\t\t{dep} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
                 f"\t\t\ttarget = {target} /* {name} */;\n\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;\n\t\t}};\n")
    src = before(src, "/* End PBXContainerItemProxy section */", proxies)
    src = before(src, "/* End PBXTargetDependency section */", deps)

    # The folders the iOS targets own.
    src = before(src, "/* End PBXFileSystemSynchronizedRootGroup section */",
                 sync_group(IDS["g_app"], APP) + sync_group(IDS["g_widget"], WIDGET) +
                 sync_group(IDS["g_tests"], TESTS) + sync_group(IDS["g_uitests"], UITESTS) +
                 sync_group(IDS["g_shared_ios"], "SharediOS"))

    # Build phases. Synchronized folders fill them; they stay empty here.
    src = before(src, "/* End PBXFrameworksBuildPhase section */",
                 "".join(phase(IDS[k], "PBXFrameworksBuildPhase", "Frameworks") for k in ("app_fw", "w_fw", "ut_fw", "ui_fw")))
    src = before(src, "/* End PBXResourcesBuildPhase section */",
                 "".join(phase(IDS[k], "PBXResourcesBuildPhase", "Resources") for k in ("app_res", "w_res", "ut_res", "ui_res")))
    src = before(src, "/* End PBXSourcesBuildPhase section */",
                 "".join(phase(IDS[k], "PBXSourcesBuildPhase", "Sources") for k in ("app_src", "w_src", "ut_src", "ui_src")))

    # Navigator.
    src = once(src, f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";",
               f"\t\t\t\t{IDS['g_app']} /* {APP} */,\n\t\t\t\t{IDS['g_widget']} /* {WIDGET} */,\n"
               f"\t\t\t\t{IDS['g_shared_ios']} /* SharediOS */,\n"
               f"\t\t\t\t{IDS['g_tests']} /* {TESTS} */,\n\t\t\t\t{IDS['g_uitests']} /* {UITESTS} */,\n"
               f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";")
    src = once(src, "\t\t\t);\n\t\t\tname = Products;",
               f"\t\t\t\t{IDS['p_app']} /* {APP}.app */,\n\t\t\t\t{IDS['p_widget']} /* {WIDGET}.appex */,\n"
               f"\t\t\t\t{IDS['p_tests']} /* {TESTS}.xctest */,\n\t\t\t\t{IDS['p_uitests']} /* {UITESTS}.xctest */,\n"
               "\t\t\t);\n\t\t\tname = Products;")

    # Targets. The app and widget own Shared/ and SharediOS/ but not openlist/
    # or OpenlistWidget/, which is what makes their exception sets allow-lists.
    shared = (SHARED_GROUP, "Shared")
    shared_ios = (IDS["g_shared_ios"], "SharediOS")
    src = before(src, "/* End PBXNativeTarget section */",
        native_target(IDS["t_app"], APP, IDS["cl_app"],
                      [(IDS["app_src"], "Sources"), (IDS["app_fw"], "Frameworks"), (IDS["app_res"], "Resources"),
                       (IDS["app_embed"], "Embed Foundation Extensions")],
                      [IDS["dep_widget"]], [(IDS["g_app"], APP), shared, shared_ios],
                      IDS["p_app"], f"{APP}.app", "com.apple.product-type.application") +
        native_target(IDS["t_widget"], WIDGET, IDS["cl_widget"],
                      [(IDS["w_src"], "Sources"), (IDS["w_fw"], "Frameworks"), (IDS["w_res"], "Resources")],
                      [], [(IDS["g_widget"], WIDGET), shared, shared_ios],
                      IDS["p_widget"], f"{WIDGET}.appex", "com.apple.product-type.app-extension") +
        native_target(IDS["t_tests"], TESTS, IDS["cl_tests"],
                      [(IDS["ut_src"], "Sources"), (IDS["ut_fw"], "Frameworks"), (IDS["ut_res"], "Resources")],
                      [IDS["dep_tests"]], [(IDS["g_tests"], TESTS)],
                      IDS["p_tests"], f"{TESTS}.xctest", "com.apple.product-type.bundle.unit-test") +
        native_target(IDS["t_uitests"], UITESTS, IDS["cl_uitests"],
                      [(IDS["ui_src"], "Sources"), (IDS["ui_fw"], "Frameworks"), (IDS["ui_res"], "Resources")],
                      [IDS["dep_uitests"]], [(IDS["g_uitests"], UITESTS)],
                      IDS["p_uitests"], f"{UITESTS}.xctest", "com.apple.product-type.bundle.ui-testing"))

    # Project registration.
    attrs = (f"\t\t\t\t\t{IDS['t_app']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n"
             f"\t\t\t\t\t{IDS['t_widget']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n"
             f"\t\t\t\t\t{IDS['t_tests']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t\tTestTargetID = {IDS['t_app']};\n\t\t\t\t\t}};\n"
             f"\t\t\t\t\t{IDS['t_uitests']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t\tTestTargetID = {IDS['t_app']};\n\t\t\t\t\t}};\n")
    src = once(src, f"\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST}",
               attrs + f"\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST}")
    src = once(src, f"\t\t\t\t{MCP_TARGET} /* openlist-mcp */,\n\t\t\t);\n\t\t}};\n/* End PBXProject section */",
               f"\t\t\t\t{MCP_TARGET} /* openlist-mcp */,\n\t\t\t\t{IDS['t_app']} /* {APP} */,\n"
               f"\t\t\t\t{IDS['t_widget']} /* {WIDGET} */,\n\t\t\t\t{IDS['t_tests']} /* {TESTS} */,\n"
               f"\t\t\t\t{IDS['t_uitests']} /* {UITESTS} */,\n\t\t\t);\n\t\t}};\n/* End PBXProject section */")

    # Build settings.
    configs = ""
    for name in CONFIGS:
        configs += config(CONFIG_IDS["app"][name], name, app_settings(name))
        configs += config(CONFIG_IDS["widget"][name], name, widget_settings(name))
        configs += config(CONFIG_IDS["tests"][name], name, test_settings(ui=False))
        configs += config(CONFIG_IDS["uitests"][name], name, test_settings(ui=True))
    src = before(src, "/* End XCBuildConfiguration section */", configs)
    src = before(src, "/* End XCConfigurationList section */",
                 config_list(IDS["cl_app"], APP, CONFIG_IDS["app"]) +
                 config_list(IDS["cl_widget"], WIDGET, CONFIG_IDS["widget"]) +
                 config_list(IDS["cl_tests"], TESTS, CONFIG_IDS["tests"]) +
                 config_list(IDS["cl_uitests"], UITESTS, CONFIG_IDS["uitests"]))
    return src


# MARK: - Membership (every run)

def exception_label(group, target):
    return f'Exceptions for "{group}" folder in "{target}" target'


def exception_object(ident, group, target, paths):
    items = "".join(f"\t\t\t\t{q(p)},\n" for p in sorted(paths))
    return (f"\t\t{ident} /* {exception_label(group, target)} */ = {{\n"
            f"\t\t\tisa = {EXCEPTION_SECTION};\n\t\t\tmembershipExceptions = (\n{items}\t\t\t);\n"
            f"\t\t\ttarget = {TARGET_IDS[target]} /* {target} */;\n\t\t}};\n")


def single(pattern, src, what):
    matches = pattern.findall(src)
    if len(matches) != 1:
        raise SystemExit(f"Expected one {what} in the project, found {len(matches)}")
    return matches[0]


def listed_exceptions(block):
    return re.search(r"\t\t\texceptions = \(\n(.*?)\t\t\t\);\n", block, re.S)


def project_membership(src):
    """{(group, target): {path, ...}} as the project's iOS exception sets say.

    Compared as sets, so Xcode re-sorting the lists when it saves the project
    is not a difference. A set the folder doesn't list (or the reverse) maps
    to None, which never equals the seed and so gets rewritten.
    """
    found = {}
    for group, group_id in LENDING_GROUPS.items():
        listed = listed_exceptions(single(object_pattern(group_id), src, f"{group} folder"))
        refs = set(re.findall(r"^\t\t\t\t([0-9A-F]{24}) ", listed.group(1), re.M)) if listed else set()
        for (owner, target), ident in EXCEPTION_IDS.items():
            if owner != group:
                continue
            objects = object_pattern(ident).findall(src)
            if ident in refs and len(objects) == 1:
                items = re.search(r"\tmembershipExceptions = \(\n(.*?)\t*\);", objects[0], re.S)
                found[(group, target)] = {line.strip().rstrip(",").strip('"') for line in
                                          (items.group(1).splitlines() if items else []) if line.strip()}
            elif ident in refs or objects:
                found[(group, target)] = None
    return found


def sync_membership(src, membership):
    """Rewrites the iOS exception sets (and only those) to match the seed."""
    begin, end = f"/* Begin {EXCEPTION_SECTION} section */\n", f"/* End {EXCEPTION_SECTION} section */\n"
    if begin not in src:
        src = before(src, "/* Begin PBXFileSystemSynchronizedRootGroup section */", begin + end + "\n")
    for (group, target), ident in EXCEPTION_IDS.items():
        paths = membership.get((group, target))
        wanted = exception_object(ident, group, target, paths) if paths else ""
        objects = object_pattern(ident).findall(src)
        if len(objects) > 1:
            raise SystemExit(f"Exception set {ident} appears {len(objects)} times")
        if objects:
            src = src.replace(objects[0], wanted, 1)
        elif wanted:
            src = before(src, end, wanted)

    # Each lending folder lists its exception sets: keep any Xcode made for
    # other reasons, then ours in a fixed order.
    ours = set(EXCEPTION_IDS.values())
    for group, group_id in LENDING_GROUPS.items():
        block = single(object_pattern(group_id), src, f"{group} folder")
        listed = listed_exceptions(block)
        kept = [line for line in (listed.group(1).splitlines(keepends=True) if listed else [])
                if line.strip()[:24] not in ours]
        refs = kept + [f"\t\t\t\t{ident} /* {exception_label(owner, target)} */,\n"
                       for (owner, target), ident in sorted(EXCEPTION_IDS.items(), key=lambda item: item[1])
                       if owner == group and membership.get((owner, target))]
        exceptions = f"\t\t\texceptions = (\n{''.join(refs)}\t\t\t);\n" if refs else ""
        if listed:
            updated = block.replace(listed.group(0), exceptions, 1)
        else:
            isa = "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
            updated = once(block, isa, isa + exceptions)
        src = src.replace(block, updated, 1)

    if begin + end in src:
        src = src.replace(begin + end + "\n", "", 1)
    return src


def lint(text):
    with tempfile.NamedTemporaryFile("w", suffix=".pbxproj", encoding="utf-8") as scratch:
        scratch.write(text)
        scratch.flush()
        result = subprocess.run(["plutil", "-lint", scratch.name], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"The generated project does not parse, so it was not written:\n{result.stdout}{result.stderr}")


def main():
    check = "--check" in sys.argv[1:]
    original = PROJECT.read_text()
    membership = read_manifest()
    wanted = {key: set(paths) for key, paths in membership.items()}
    has_targets = IDS["t_app"] in original
    if has_targets and project_membership(original) == wanted:
        print("iOS targets present; their shared-file membership matches Tools/iOS/shared-sources.txt.")
        return 0
    if check:
        if not has_targets:
            print("The iOS targets are missing from the project. Run: python3 Tools/add-ios-targets.py", file=sys.stderr)
        else:
            current = project_membership(original)
            for key in sorted(set(current) | set(wanted)):
                have, want = current.get(key) or set(), wanted.get(key, set())
                for path in sorted(want - have):
                    print(f"  seed only:    {key[1]} {key[0]} {path}", file=sys.stderr)
                for path in sorted(have - want):
                    print(f"  project only: {key[1]} {key[0]} {path}", file=sys.stderr)
            print("openlist.xcodeproj's iOS membership differs from Tools/iOS/shared-sources.txt. Edit the seed "
                  "(not the File inspector's target membership) and run: python3 Tools/add-ios-targets.py",
                  file=sys.stderr)
        return 1
    src = original if has_targets else add_targets(original)
    src = sync_membership(src, membership)
    lint(src)
    PROJECT.write_text(src)
    count = sum(len(paths) for paths in membership.values())
    if has_targets:
        print(f"Updated the iOS exception sets to the {count} files in Tools/iOS/shared-sources.txt.")
    else:
        print(f"Added the iOS app, widget, unit-test and UI-test targets, sharing {count} files from the Mac folders.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
