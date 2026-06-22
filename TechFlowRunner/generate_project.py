#!/usr/bin/env python3
"""Generate TechFlowRunner.xcodeproj (project.pbxproj + scheme).

Run from the TechFlowRunner/ directory:  python3 generate_project.py

This project uses Xcode 16's **file-system-synchronized root group**
(`PBXFileSystemSynchronizedRootGroup`): the whole `TechFlowRunner/` folder is
referenced as one synchronized group, so Xcode automatically includes any file
added to it on disk — `.swift` compiled as Sources, `.xcassets`/`.mp3` copied
as Resources — with NO edits to project.pbxproj. Adding or removing source
files therefore requires neither this script nor any pbxproj change.

Because the file list no longer lives in the project, this generator emits a
fully static project with fixed identifiers, so re-running it is idempotent
(byte-for-byte stable) and never churns UIDs. It exists only to reproduce the
project file from scratch if it is ever lost.

Requires Xcode 16 or later to open (objectVersion 77).
"""
import os

ROOT = os.path.dirname(os.path.abspath(__file__))

# ---- Fixed identifiers ----------------------------------------------------
# Stable 24-char hex IDs so regeneration never changes the file.
PRODUCT_ID        = "AABBCCDD000000000000A001"  # TechFlowRunner.app
SYNC_GROUP_ID     = "AABBCCDD000000000000A002"  # TechFlowRunner (synchronized)
FRAMEWORKS_ID     = "AABBCCDD000000000000A003"
MAIN_GROUP_ID     = "AABBCCDD000000000000A004"
PRODUCTS_GROUP_ID = "AABBCCDD000000000000A005"
TARGET_ID         = "AABBCCDD000000000000A006"
TARGET_CFG_LIST   = "AABBCCDD000000000000A007"
SOURCES_ID        = "AABBCCDD000000000000A008"
RESOURCES_ID      = "AABBCCDD000000000000A009"
PROJECT_ID        = "AABBCCDD000000000000A00A"
PROJECT_CFG_LIST  = "AABBCCDD000000000000A00B"
PROJ_DEBUG_ID     = "AABBCCDD000000000000A00C"
PROJ_RELEASE_ID   = "AABBCCDD000000000000A00D"
TGT_DEBUG_ID      = "AABBCCDD000000000000A00E"
TGT_RELEASE_ID    = "AABBCCDD000000000000A00F"

entitlements = "TechFlowRunner.entitlements"

# ---- Build settings -------------------------------------------------------
COMMON_SETTINGS = f"""\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "TechFlowRunner/{entitlements}";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Tech Flow Runner";
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.games";
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIStatusBarHidden = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\t"INFOPLIST_KEY_UISupportedInterfaceOrientations~ipad" = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.whahn1983.techflowrunner;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""

PROJ_DEBUG = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSDKROOT = iphoneos;"""

PROJ_RELEASE = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tVALIDATE_PRODUCT = YES;"""

def xcbuildconfig(cfg_id, name, settings):
    return f"""\t\t{cfg_id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings}
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""

CONFIGS = "\n".join([
    xcbuildconfig(PROJ_DEBUG_ID, "Debug", PROJ_DEBUG),
    xcbuildconfig(PROJ_RELEASE_ID, "Release", PROJ_RELEASE),
    xcbuildconfig(TGT_DEBUG_ID, "Debug", COMMON_SETTINGS),
    xcbuildconfig(TGT_RELEASE_ID, "Release", COMMON_SETTINGS),
])

# ---- Assemble pbxproj -----------------------------------------------------
pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXFileReference section */
\t\t{PRODUCT_ID} /* TechFlowRunner.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TechFlowRunner.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{SYNC_GROUP_ID} /* TechFlowRunner */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = TechFlowRunner; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORKS_ID} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{MAIN_GROUP_ID} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{SYNC_GROUP_ID} /* TechFlowRunner */,
\t\t\t\t{PRODUCTS_GROUP_ID} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PRODUCTS_GROUP_ID} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{PRODUCT_ID} /* TechFlowRunner.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET_ID} /* TechFlowRunner */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TARGET_CFG_LIST} /* Build configuration list for PBXNativeTarget "TechFlowRunner" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_ID} /* Sources */,
\t\t\t\t{FRAMEWORKS_ID} /* Frameworks */,
\t\t\t\t{RESOURCES_ID} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{SYNC_GROUP_ID} /* TechFlowRunner */,
\t\t\t);
\t\t\tname = TechFlowRunner;
\t\t\tproductName = TechFlowRunner;
\t\t\tproductReference = {PRODUCT_ID} /* TechFlowRunner.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJECT_ID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET_ID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJECT_CFG_LIST} /* Build configuration list for PBXProject "TechFlowRunner" */;
\t\t\tcompatibilityVersion = "Xcode 15.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP_ID};
\t\t\tproductRefGroup = {PRODUCTS_GROUP_ID} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET_ID} /* TechFlowRunner */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_ID} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_ID} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{CONFIGS}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{PROJECT_CFG_LIST} /* Build configuration list for PBXProject "TechFlowRunner" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{PROJ_DEBUG_ID} /* Debug */,
\t\t\t\t{PROJ_RELEASE_ID} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{TARGET_CFG_LIST} /* Build configuration list for PBXNativeTarget "TechFlowRunner" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{TGT_DEBUG_ID} /* Debug */,
\t\t\t\t{TGT_RELEASE_ID} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {PROJECT_ID} /* Project object */;
}}
"""

proj_dir = os.path.join(ROOT, "TechFlowRunner.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write(pbx)

# ---- Shared scheme --------------------------------------------------------
scheme_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET_ID}"
               BuildableName = "TechFlowRunner.app"
               BlueprintName = "TechFlowRunner"
               ReferencedContainer = "container:TechFlowRunner.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_ID}"
            BuildableName = "TechFlowRunner.app"
            BlueprintName = "TechFlowRunner"
            ReferencedContainer = "container:TechFlowRunner.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_ID}"
            BuildableName = "TechFlowRunner.app"
            BlueprintName = "TechFlowRunner"
            ReferencedContainer = "container:TechFlowRunner.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""
with open(os.path.join(scheme_dir, "TechFlowRunner.xcscheme"), "w") as f:
    f.write(scheme)

print("Generated synchronized-folder project (objectVersion 77, Xcode 16+).")
print("All files under TechFlowRunner/ are auto-included; no per-file refs.")
