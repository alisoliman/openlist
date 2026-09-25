#!/usr/bin/env python3
"""Adds the OpenlistWidget extension target to the Xcode project.

The project uses objectVersion 77 file-system-synchronized groups, so source
files never need individual entries: the Shared folder is attached to both
targets, and the OpenlistWidget folder to the extension alone.

Idempotent — running it twice leaves the project unchanged.
"""

import re
import sys

PROJECT = "openlist.xcodeproj/project.pbxproj"

# Stable object ids in the same style as the ones Xcode generated.
IDS = {
    "shared_group":     "41362FF0304B659900C93862",
    "widget_group":     "41362FF1304B659900C93862",
    "widget_target":    "41362FF2304B659900C93862",
    "widget_product":   "41362FF3304B659900C93862",
    "widget_sources":   "41362FF4304B659900C93862",
    "widget_frameworks":"41362FF5304B659900C93862",
    "widget_resources": "41362FF6304B659900C93862",
    "widget_configs":   "41362FF7304B659900C93862",
    "widget_debug":     "41362FF8304B659900C93862",
    "widget_release":   "41362FF9304B659900C93862",
    "embed_phase":      "41362FFA304B659900C93862",
    "embed_buildfile":  "41362FFB304B659900C93862",
    "dependency":       "41362FFC304B659900C93862",
    "proxy":            "41362FFD304B659900C93862",
}

APP_TARGET = "41362FD4304B659900C93862"
APP_SOURCES = "41362FD1304B659900C93862"
APP_FRAMEWORKS = "41362FD2304B659900C93862"
APP_RESOURCES = "41362FD3304B659900C93862"
APP_SYNC_GROUP = "41362FD7304B659900C93862"
PRODUCTS_GROUP = "41362FD6304B659900C93862"
MAIN_GROUP = "41362FCC304B659900C93862"
PROJECT_OBJ = "41362FCD304B659900C93862"

WIDGET_NAME = "OpenlistWidget"
BUNDLE_ID = "solimanali.openlist.OpenlistWidget"


def insert_before(text, marker, addition):
    if marker not in text:
        raise SystemExit(f"marker not found: {marker}")
    return text.replace(marker, addition + marker, 1)


def main():
    src = open(PROJECT).read()

    if IDS["widget_target"] in src:
        print("Widget target already present — nothing to do.")
        return 0

    # 1. Product reference + the build file that embeds it in the app.
    src = insert_before(
        src,
        "/* End PBXFileReference section */",
        f'\t\t{IDS["widget_product"]} /* {WIDGET_NAME}.appex */ = '
        f'{{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; '
        f'includeInIndex = 0; path = {WIDGET_NAME}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n',
    )

    src = (
        "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n"
        "/* Begin PBXBuildFile section */\n"
        f'\t\t{IDS["embed_buildfile"]} /* {WIDGET_NAME}.appex in Embed Foundation Extensions */ = '
        f'{{isa = PBXBuildFile; fileRef = {IDS["widget_product"]} /* {WIDGET_NAME}.appex */; '
        f'settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n'
        "/* End PBXBuildFile section */\n\n"
        + src.split("objects = {\n\n", 1)[1]
    )

    # 2. Synchronized folders: Shared is shared by both targets.
    src = insert_before(
        src,
        "/* End PBXFileSystemSynchronizedRootGroup section */",
        f'\t\t{IDS["shared_group"]} /* Shared */ = {{\n'
        f'\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n'
        f'\t\t\tpath = Shared;\n'
        f'\t\t\tsourceTree = "<group>";\n'
        f'\t\t}};\n'
        f'\t\t{IDS["widget_group"]} /* {WIDGET_NAME} */ = {{\n'
        f'\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n'
        f'\t\t\tpath = {WIDGET_NAME};\n'
        f'\t\t\tsourceTree = "<group>";\n'
        f'\t\t}};\n',
    )

    # 3. Build phases for the extension, plus the app's embed phase.
    src = insert_before(
        src,
        "/* End PBXFrameworksBuildPhase section */",
        f'\t\t{IDS["widget_frameworks"]} /* Frameworks */ = {{\n'
        f'\t\t\tisa = PBXFrameworksBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n',
    )

    src = insert_before(
        src,
        "/* Begin PBXFileReference section */",
        "/* Begin PBXCopyFilesBuildPhase section */\n"
        f'\t\t{IDS["embed_phase"]} /* Embed Foundation Extensions */ = {{\n'
        f'\t\t\tisa = PBXCopyFilesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tdstPath = "";\n'
        f'\t\t\tdstSubfolderSpec = 13;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t\t{IDS["embed_buildfile"]} /* {WIDGET_NAME}.appex in Embed Foundation Extensions */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = "Embed Foundation Extensions";\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n'
        "/* End PBXCopyFilesBuildPhase section */\n\n",
    )

    src = insert_before(
        src,
        "/* End PBXSourcesBuildPhase section */",
        f'\t\t{IDS["widget_sources"]} /* Sources */ = {{\n'
        f'\t\t\tisa = PBXSourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n',
    )

    src = insert_before(
        src,
        "/* End PBXResourcesBuildPhase section */",
        f'\t\t{IDS["widget_resources"]} /* Resources */ = {{\n'
        f'\t\t\tisa = PBXResourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n',
    )

    # 4. The extension target itself.
    src = insert_before(
        src,
        "/* End PBXNativeTarget section */",
        f'\t\t{IDS["widget_target"]} /* {WIDGET_NAME} */ = {{\n'
        f'\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {IDS["widget_configs"]} /* Build configuration list for PBXNativeTarget "{WIDGET_NAME}" */;\n'
        f'\t\t\tbuildPhases = (\n'
        f'\t\t\t\t{IDS["widget_sources"]} /* Sources */,\n'
        f'\t\t\t\t{IDS["widget_frameworks"]} /* Frameworks */,\n'
        f'\t\t\t\t{IDS["widget_resources"]} /* Resources */,\n'
        f'\t\t\t);\n'
        f'\t\t\tbuildRules = (\n\t\t\t);\n'
        f'\t\t\tdependencies = (\n\t\t\t);\n'
        f'\t\t\tfileSystemSynchronizedGroups = (\n'
        f'\t\t\t\t{IDS["widget_group"]} /* {WIDGET_NAME} */,\n'
        f'\t\t\t\t{IDS["shared_group"]} /* Shared */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = {WIDGET_NAME};\n'
        f'\t\t\tpackageProductDependencies = (\n\t\t\t);\n'
        f'\t\t\tproductName = {WIDGET_NAME};\n'
        f'\t\t\tproductReference = {IDS["widget_product"]} /* {WIDGET_NAME}.appex */;\n'
        f'\t\t\tproductType = "com.apple.product-type.app-extension";\n'
        f'\t\t}};\n',
    )

    # 5. Dependency so the app always builds the extension first.
    src = insert_before(
        src,
        "/* Begin PBXProject section */",
        "/* Begin PBXContainerItemProxy section */\n"
        f'\t\t{IDS["proxy"]} /* PBXContainerItemProxy */ = {{\n'
        f'\t\t\tisa = PBXContainerItemProxy;\n'
        f'\t\t\tcontainerPortal = {PROJECT_OBJ} /* Project object */;\n'
        f'\t\t\tproxyType = 1;\n'
        f'\t\t\tremoteGlobalIDString = {IDS["widget_target"]};\n'
        f'\t\t\tremoteInfo = {WIDGET_NAME};\n'
        f'\t\t}};\n'
        "/* End PBXContainerItemProxy section */\n\n",
    )

    src = insert_before(
        src,
        "/* Begin PBXResourcesBuildPhase section */",
        "/* Begin PBXTargetDependency section */\n"
        f'\t\t{IDS["dependency"]} /* PBXTargetDependency */ = {{\n'
        f'\t\t\tisa = PBXTargetDependency;\n'
        f'\t\t\ttarget = {IDS["widget_target"]} /* {WIDGET_NAME} */;\n'
        f'\t\t\ttargetProxy = {IDS["proxy"]} /* PBXContainerItemProxy */;\n'
        f'\t\t}};\n'
        "/* End PBXTargetDependency section */\n\n",
    )

    # 6. Wire the new pieces into the app target.
    src = src.replace(
        f'\t\t\t\t{APP_RESOURCES} /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (',
        f'\t\t\t\t{APP_RESOURCES} /* Resources */,\n'
        f'\t\t\t\t{IDS["embed_phase"]} /* Embed Foundation Extensions */,\n'
        f'\t\t\t);\n\t\t\tbuildRules = (',
        1,
    )
    src = src.replace(
        f'\t\t\tdependencies = (\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{APP_SYNC_GROUP} /* openlist */,\n\t\t\t);',
        f'\t\t\tdependencies = (\n'
        f'\t\t\t\t{IDS["dependency"]} /* PBXTargetDependency */,\n'
        f'\t\t\t);\n'
        f'\t\t\tfileSystemSynchronizedGroups = (\n'
        f'\t\t\t\t{APP_SYNC_GROUP} /* openlist */,\n'
        f'\t\t\t\t{IDS["shared_group"]} /* Shared */,\n'
        f'\t\t\t);',
        1,
    )

    # 7. Groups: show the new folders in the navigator.
    src = src.replace(
        f'\t\t\t\t{APP_SYNC_GROUP} /* openlist */,\n\t\t\t\t{PRODUCTS_GROUP} /* Products */,',
        f'\t\t\t\t{APP_SYNC_GROUP} /* openlist */,\n'
        f'\t\t\t\t{IDS["shared_group"]} /* Shared */,\n'
        f'\t\t\t\t{IDS["widget_group"]} /* {WIDGET_NAME} */,\n'
        f'\t\t\t\t{PRODUCTS_GROUP} /* Products */,',
        1,
    )
    src = src.replace(
        f'\t\t\t\t41362FD5304B659900C93862 /* openlist.app */,\n\t\t\t);\n\t\t\tname = Products;',
        f'\t\t\t\t41362FD5304B659900C93862 /* openlist.app */,\n'
        f'\t\t\t\t{IDS["widget_product"]} /* {WIDGET_NAME}.appex */,\n'
        f'\t\t\t);\n\t\t\tname = Products;',
        1,
    )

    # 8. Project registration.
    src = src.replace(
        f'\t\t\t\t\t{APP_TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.6;\n\t\t\t\t\t}};',
        f'\t\t\t\t\t{APP_TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.6;\n\t\t\t\t\t}};\n'
        f'\t\t\t\t\t{IDS["widget_target"]} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.6;\n\t\t\t\t\t}};',
        1,
    )
    src = src.replace(
        f'\t\t\ttargets = (\n\t\t\t\t{APP_TARGET} /* openlist */,\n\t\t\t);',
        f'\t\t\ttargets = (\n'
        f'\t\t\t\t{APP_TARGET} /* openlist */,\n'
        f'\t\t\t\t{IDS["widget_target"]} /* {WIDGET_NAME} */,\n'
        f'\t\t\t);',
        1,
    )

    # 9. Build settings for the extension.
    def widget_config(name, debug):
        extra = (
            "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";\n"
            "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n"
            if debug
            else "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"
        )
        return (
            f'\t\t{IDS["widget_debug"] if debug else IDS["widget_release"]} /* {name} */ = {{\n'
            f'\t\t\tisa = XCBuildConfiguration;\n'
            f'\t\t\tbuildSettings = {{\n'
            f'\t\t\t\tCODE_SIGN_ENTITLEMENTS = Config/{WIDGET_NAME}.entitlements;\n'
            f'\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
            f'\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n'
            f'\t\t\t\tDEVELOPMENT_TEAM = Y5UE64R7TQ;\n'
            f'\t\t\t\tENABLE_APP_SANDBOX = YES;\n'
            f'\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n'
            f'\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
            f'\t\t\t\tINFOPLIST_FILE = "Config/{WIDGET_NAME}-Info.plist";\n'
            f'\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Openlist;\n'
            f'\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";\n'
            f'\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n'
            f'\t\t\t\t\t"$(inherited)",\n'
            f'\t\t\t\t\t"@executable_path/../Frameworks",\n'
            f'\t\t\t\t\t"@executable_path/../../../../Frameworks",\n'
            f'\t\t\t\t);\n'
            f'\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 27.0;\n'
            f'\t\t\t\tMARKETING_VERSION = 1.0;\n'
            f'\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};\n'
            f'\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
            f'\t\t\t\tREGISTER_APP_GROUPS = YES;\n'
            f'\t\t\t\tSKIP_INSTALL = YES;\n'
            f'\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;\n'
            f'\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;\n'
            f'\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n'
            f'\t\t\t\tSWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;\n'
            f'\t\t\t\tSWIFT_VERSION = 6.0;\n'
            + extra
            + f'\t\t\t}};\n'
            f'\t\t\tname = {name};\n'
            f'\t\t}};\n'
        )

    src = insert_before(
        src,
        "/* End XCBuildConfiguration section */",
        widget_config("Debug", True) + widget_config("Release", False),
    )

    src = insert_before(
        src,
        "/* End XCConfigurationList section */",
        f'\t\t{IDS["widget_configs"]} /* Build configuration list for PBXNativeTarget "{WIDGET_NAME}" */ = {{\n'
        f'\t\t\tisa = XCConfigurationList;\n'
        f'\t\t\tbuildConfigurations = (\n'
        f'\t\t\t\t{IDS["widget_debug"]} /* Debug */,\n'
        f'\t\t\t\t{IDS["widget_release"]} /* Release */,\n'
        f'\t\t\t);\n'
        f'\t\t\tdefaultConfigurationIsVisible = 0;\n'
        f'\t\t\tdefaultConfigurationName = Release;\n'
        f'\t\t}};\n',
    )

    open(PROJECT, "w").write(src)
    print("Added the OpenlistWidget target.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
