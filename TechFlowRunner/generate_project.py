#!/usr/bin/env python3
"""Generate TechFlowRunner.xcodeproj (project.pbxproj + scheme).

Run from the TechFlowRunner/ directory:  python3 generate_project.py
This keeps the Xcode project in sync with the on-disk source tree.
"""
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "TechFlowRunner")

_counter = [0]
def uid():
    _counter[0] += 1
    return "AABBCCDD" + f"{_counter[0]:016X}"

# ---- Collect source files grouped by subdirectory -------------------------
GROUP_DIRS = ["Game", "Models", "Services", "UI"]
root_swift = []     # swift files directly in TechFlowRunner/
group_files = {g: [] for g in GROUP_DIRS}

for name in sorted(os.listdir(SRC)):
    if name.endswith(".swift"):
        root_swift.append(name)
for g in GROUP_DIRS:
    d = os.path.join(SRC, g)
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            if name.endswith(".swift"):
                group_files[g].append(name)

# Resources
assets = "Assets.xcassets"
entitlements = "TechFlowRunner.entitlements"
music = "Tech Flow.mp3"  # lives in Resources/

# ---- Assign ids -----------------------------------------------------------
file_refs = {}   # key -> (id, name, path, fileType, sourceTree)
build_files = {} # key -> (id, fileRefId, phase)

def add_ref(key, name, path, ftype, tree="<group>"):
    file_refs[key] = (uid(), name, path, ftype, tree)

def add_build(key, ref_key, phase):
    build_files[key] = (uid(), file_refs[ref_key][0], phase)

# Swift source refs + build files
for name in root_swift:
    k = "src/" + name
    add_ref(k, name, name, "sourcecode.swift")
    add_build(k, k, "sources")
for g in GROUP_DIRS:
    for name in group_files[g]:
        k = f"src/{g}/{name}"
        add_ref(k, name, name, "sourcecode.swift")
        add_build(k, k, "sources")

# Assets
add_ref("assets", assets, assets, "folder.assetcatalog")
add_build("assets", "assets", "resources")
# Entitlements (reference only; not in a build phase)
add_ref("entitlements", entitlements, entitlements, "text.plist.entitlements")
# Music
add_ref("music", music, music, "audio.mp3")
add_build("music", "music", "resources")

# Product
product_id = uid()

# ---- Groups ---------------------------------------------------------------
group_ids = {g: uid() for g in GROUP_DIRS}
resources_group_id = uid()
techflow_group_id = uid()
main_group_id = uid()
products_group_id = uid()

def children_list(ids):
    return "\n".join(f"\t\t\t\t{i} /* {n} */," for i, n in ids)

# ---- Phase / config ids ---------------------------------------------------
target_id = uid()
project_id = uid()
sources_phase_id = uid()
resources_phase_id = uid()
frameworks_phase_id = uid()
target_cfg_list_id = uid()
project_cfg_list_id = uid()
proj_debug_id = uid()
proj_release_id = uid()
tgt_debug_id = uid()
tgt_release_id = uid()

def file_ref_section():
    lines = []
    for key, (i, name, path, ftype, tree) in file_refs.items():
        attrs = f'isa = PBXFileReference; lastKnownFileType = {ftype}; path = "{path}"; sourceTree = "{tree}";'
        if ftype == "sourcecode.swift":
            attrs = f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = "{tree}";'
        lines.append(f"\t\t{i} /* {name} */ = {{{attrs}}};")
    # product
    lines.append(f'\t\t{product_id} /* TechFlowRunner.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TechFlowRunner.app; sourceTree = BUILT_PRODUCTS_DIR;}};')
    return "\n".join(lines)

def build_file_section():
    lines = []
    for key, (i, ref_id, phase) in build_files.items():
        name = file_refs[key][1]
        lines.append(f"\t\t{i} /* {name} in {phase} */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */;}};")
    return "\n".join(lines)

def phase_files(phase):
    return [ (i, file_refs[key][1]) for key,(i,ref,p) in build_files.items() if p == phase ]

def phase_block(phase_id, phase_isa, phase_label, files, extra=""):
    flist = "\n".join(f"\t\t\t\t{i} /* {n} in {phase_label} */," for i,n in files)
    return f"""\t\t{phase_id} /* {phase_label} */ = {{
\t\t\tisa = {phase_isa};
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{flist}
\t\t\t);
{extra}\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""

# Group blocks
def group_block(gid, name, path, child_ids, with_path=True):
    kids = "\n".join(f"\t\t\t\t{i} /* {n} */," for i,n in child_ids)
    path_line = f'\t\t\tpath = {path};\n' if with_path else ''
    return f"""\t\t{gid} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{kids}
\t\t\t);
{path_line}\t\t\tsourceTree = "<group>";
\t\t}};"""

# Build children id/name lists for groups
def refs_for(keys):
    return [(file_refs[k][0], file_refs[k][1]) for k in keys]

game_keys = [f"src/Game/{n}" for n in group_files["Game"]]
models_keys = [f"src/Models/{n}" for n in group_files["Models"]]
services_keys = [f"src/Services/{n}" for n in group_files["Services"]]
ui_keys = [f"src/UI/{n}" for n in group_files["UI"]]
root_keys = [f"src/{n}" for n in root_swift]

groups_text = []
groups_text.append(group_block(group_ids["Game"], "Game", "Game", refs_for(game_keys)))
groups_text.append(group_block(group_ids["Models"], "Models", "Models", refs_for(models_keys)))
groups_text.append(group_block(group_ids["Services"], "Services", "Services", refs_for(services_keys)))
groups_text.append(group_block(group_ids["UI"], "UI", "UI", refs_for(ui_keys)))
groups_text.append(group_block(resources_group_id, "Resources", "Resources", refs_for(["music"])))

# TechFlowRunner group: root swift + groups + assets + entitlements
techflow_children = refs_for(root_keys) + [
    (group_ids["Game"], "Game"),
    (group_ids["Models"], "Models"),
    (group_ids["Services"], "Services"),
    (group_ids["UI"], "UI"),
    (resources_group_id, "Resources"),
    (file_refs["assets"][0], assets),
    (file_refs["entitlements"][0], entitlements),
]
groups_text.append(group_block(techflow_group_id, "TechFlowRunner", "TechFlowRunner", techflow_children))
groups_text.append(group_block(products_group_id, "Products", None, [(product_id, "TechFlowRunner.app")], with_path=False))
# main group (no path)
main_children = [(techflow_group_id, "TechFlowRunner"), (products_group_id, "Products")]
groups_text.append(group_block(main_group_id, "MainGroup", None, main_children, with_path=False))

GROUPS = "\n".join(groups_text)

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

configs = []
configs.append(xcbuildconfig(proj_debug_id, "Debug", PROJ_DEBUG))
configs.append(xcbuildconfig(proj_release_id, "Release", PROJ_RELEASE))
configs.append(xcbuildconfig(tgt_debug_id, "Debug", COMMON_SETTINGS))
configs.append(xcbuildconfig(tgt_release_id, "Release", COMMON_SETTINGS))
CONFIGS = "\n".join(configs)

# ---- Assemble pbxproj -----------------------------------------------------
pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_file_section()}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_ref_section()}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
{phase_block(frameworks_phase_id, "PBXFrameworksBuildPhase", "Frameworks", [])}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{GROUPS}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* TechFlowRunner */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_cfg_list_id} /* Build configuration list for PBXNativeTarget "TechFlowRunner" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase_id} /* Sources */,
\t\t\t\t{frameworks_phase_id} /* Frameworks */,
\t\t\t\t{resources_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = TechFlowRunner;
\t\t\tproductName = TechFlowRunner;
\t\t\tproductReference = {product_id} /* TechFlowRunner.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_cfg_list_id} /* Build configuration list for PBXProject "TechFlowRunner" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_id};
\t\t\tproductRefGroup = {products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id} /* TechFlowRunner */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase_block(resources_phase_id, "PBXResourcesBuildPhase", "Resources", phase_files("resources"))}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase_block(sources_phase_id, "PBXSourcesBuildPhase", "Sources", phase_files("sources"))}
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{CONFIGS}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_cfg_list_id} /* Build configuration list for PBXProject "TechFlowRunner" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{proj_debug_id} /* Debug */,
\t\t\t\t{proj_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_cfg_list_id} /* Build configuration list for PBXNativeTarget "TechFlowRunner" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{tgt_debug_id} /* Debug */,
\t\t\t\t{tgt_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_id} /* Project object */;
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
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
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
            BlueprintIdentifier = "{target_id}"
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
            BlueprintIdentifier = "{target_id}"
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

print("Generated project with %d source files." % (len(root_swift) + sum(len(v) for v in group_files.values())))
print("Groups:", {g: len(v) for g, v in group_files.items()}, "root:", len(root_swift))
"""marker"""
