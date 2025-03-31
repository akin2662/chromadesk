#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
# Exit on unset variables to catch potential typos.
# Inherit shell options to functions.
set -euo pipefail

# --- Configuration ---
# Project specific names and paths
readonly PROJECT_NAME="ChromaDesk"
readonly PACKAGE_NAME="chromadesk" # Python package name
readonly EXECUTABLE_NAME="chromadesk" # Name of the final executable
readonly DESKTOP_FILE_ID="io.github.anantdark.chromadesk" # Reverse domain name ID
readonly SOURCE_ICON_PATH="data/icons/${DESKTOP_FILE_ID}.png"
readonly SOURCE_DESKTOP_PATH="data/${DESKTOP_FILE_ID}.desktop"

# Directories
readonly VENV_DIR=".venv"
readonly BUILD_OUTPUT_DIR="build" # PyInstaller build work directory
readonly APPDIR_BASE="dist"       # Base directory for AppDir contents

# Colors for better readability (optional)
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# --- Functions ---

# Display usage information
show_help() {
    # Usage info prints to stdout by default, which is fine here
    echo -e "${GREEN}${PROJECT_NAME} Build Script${NC}"
    echo -e "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h             Display this help message"
    echo "  --version-update VER   Update version to specified version (e.g., 0.3.0)"
    echo "  --build-only           Only build, don't update version (requires --version-update)"
    echo "  --appimage             Create an AppImage after building the executable"
    echo "  --debug                Enable verbose command tracing output"
    echo ""
    echo "Examples:"
    echo "  $0                      Build the executable using current version"
    echo "  $0 --version-update 0.3.0 Build with version 0.3.0 (updates files)"
    echo "  $0 --appimage           Build and create an AppImage"
    echo "  $0 --version-update 0.3.0 --build-only  Only update version files"
}

# Log messages with color (Redirect to stderr)
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2 # Redirect info messages to stderr
}
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2 # Redirect warn messages to stderr
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2 # Redirect error messages to stderr
}

# Update version string in relevant project files
update_version_files() {
    local new_version="$1"

    # Validate version format (simple semantic version check)
    if ! [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format '$new_version'. Please use semantic versioning (e.g., 1.2.3)."
        exit 1
    fi

    log_info "Updating project version to ${YELLOW}${new_version}${NC}"

    # Check if files exist before attempting to modify
    local init_file="${PACKAGE_NAME}/__init__.py"
    local pyproject_file="pyproject.toml"

    if [[ ! -f "$init_file" ]]; then
        log_error "Version file not found: $init_file"
        exit 1
    fi
     if [[ ! -f "$pyproject_file" ]]; then
        log_error "Project file not found: $pyproject_file"
        exit 1
    fi

    # Use simpler sed patterns, assuming standard formats
    # Update version in __init__.py (match '__version__ = "..."')
    sed -i -E "s/^__version__\s*=\s*\"[^\"]*\"/__version__ = \"$new_version\"/" "$init_file"
    log_info "Updated $init_file"

    # Update version in pyproject.toml (match 'version = "..."')
    # Handles both [project] and [tool.poetry] sections if they follow the pattern
    sed -i -E "s/^version\s*=\s*\"[^\"]*\"/version = \"$new_version\"/" "$pyproject_file"
    log_info "Updated $pyproject_file"

    log_info "${GREEN}Version update complete.${NC}"
}

# Set up and activate the Python virtual environment
setup_venv() {
    if [[ ! -d "$VENV_DIR" ]]; then
        log_info "Virtual environment not found. Creating one at '$VENV_DIR'..."
        # Use python3 explicitly if available and preferred
        if command -v python3 &>/dev/null; then
            python3 -m venv "$VENV_DIR"
        else
            python -m venv "$VENV_DIR"
        fi
        if [ $? -ne 0 ]; then
            log_error "Failed to create virtual environment."
            exit 1
        fi
    fi

    log_info "Activating virtual environment..."
    # Use 'source' which is POSIX compliant
    # shellcheck source=/dev/null # Ignore SC1091 for dynamic source
    source "${VENV_DIR}/bin/activate"

    # Verify python activation
    log_info "Checking Python environment..."
    local python_path
    python_path=$(command -v python)
    if [[ "$python_path" != "$PWD/$VENV_DIR/bin/python" ]]; then
        log_error "Virtual environment activation failed or Python path mismatch."
        log_error "Expected: $PWD/$VENV_DIR/bin/python"
        log_error "Found: $python_path"
        exit 1
    fi
    log_info "Using Python from: $(python --version 2>&1) at $python_path"
}

# Install project dependencies using pip
install_dependencies() {
    log_info "Upgrading pip and installing build tools..."
    python -m pip install --upgrade pip build setuptools wheel pyinstaller
    if [ $? -ne 0 ]; then log_error "Failed installing build tools."; exit 1; fi

    log_info "Installing project core dependencies..."
    # Installs dependencies listed in pyproject.toml
    python -m pip install .
    if [ $? -ne 0 ]; then log_error "Failed installing core dependencies."; exit 1; fi

    # Install optional dependencies if AppImage is being created
    if [ "$CREATE_APPIMAGE" = true ]; then
        log_info "Installing optional dependencies for AppImage build ([notifications])..."
        # Ensure extras_require [notifications] is defined in pyproject.toml
        python -m pip install ".[notifications]"
        if [ $? -ne 0 ]; then log_error "Failed installing optional dependencies."; exit 1; fi
    fi
}

# Prepare the AppDir structure and copy necessary files
prepare_appdir() {
    local appdir_path="$1"
    local project_version="$2"

    log_info "Preparing AppDir structure at '${appdir_path}'..."
    # Clean previous AppDir and create structure
    rm -rf "$appdir_path"
    mkdir -p "${appdir_path}/usr/bin"
    mkdir -p "${appdir_path}/usr/share/applications"
    mkdir -p "${appdir_path}/usr/share/icons/hicolor/128x128/apps"

    # --- Desktop File ---
    # Define path for the standard ID-named desktop file
    local id_desktop_file="${appdir_path}/${DESKTOP_FILE_ID}.desktop"
    # Define path for the simpler named desktop file in the root (needed by appimagetool)
    local root_desktop_file="${appdir_path}/${EXECUTABLE_NAME}.desktop"

    log_info "Creating AppDir desktop file: ${id_desktop_file}"
    # Create the standard ID-named file first
    cat > "$id_desktop_file" << EOF
[Desktop Entry]
Version=1.0
Name=${PROJECT_NAME}
GenericName=Wallpaper Changer
Comment=Daily Bing/Custom Wallpaper Changer for GNOME
Exec=AppRun
Icon=${EXECUTABLE_NAME}
Terminal=false
Type=Application
Categories=Utility;GTK;GNOME;
Keywords=wallpaper;background;bing;daily;desktop;image;
StartupNotify=true
StartupWMClass=${PROJECT_NAME}
X-AppImage-Version=${project_version}
EOF
    # Copy the ID-named file to the standard freedesktop location within AppDir
    cp "$id_desktop_file" "${appdir_path}/usr/share/applications/"

    # **FIX:** Copy the ID-named file to the root with the executable name for appimagetool
    log_info "Copying desktop file to root for appimagetool: ${root_desktop_file}"
    cp "$id_desktop_file" "$root_desktop_file"

    # --- Icon Files ---
    # Check if source icon exists
    if [[ ! -f "$SOURCE_ICON_PATH" ]]; then
        log_error "Source icon file not found: $SOURCE_ICON_PATH"
        exit 1
    fi
    # AppImage requires the icon file in the root with the name referenced by 'Icon=' in the .desktop file
    local appdir_root_icon="${appdir_path}/${EXECUTABLE_NAME}.png"
    log_info "Copying icon to AppDir root: ${appdir_root_icon}"
    cp "$SOURCE_ICON_PATH" "$appdir_root_icon"

    # Also copy to the standard freedesktop location within AppDir (using full ID)
    local appdir_hicolor_icon="${appdir_path}/usr/share/icons/hicolor/128x128/apps/${DESKTOP_FILE_ID}.png"
    cp "$SOURCE_ICON_PATH" "$appdir_hicolor_icon"

    # Create .DirIcon symlink for some AppImage environments/tools
    ln -sf "${EXECUTABLE_NAME}.png" "${appdir_path}/.DirIcon"

    log_info "AppDir preparation complete."
}

# Build the executable using PyInstaller
build_executable() {
    local appdir_path="$1"

    log_info "Building executable with PyInstaller..."
    log_warn "Note: 'Ignoring icon' warnings from PyInstaller are expected on Linux."

    # Run PyInstaller
    # --distpath places the final executable directly into AppDir/usr/bin
    # --workpath places intermediate files in BUILD_OUTPUT_DIR
    # --specpath places the .spec file in the current directory (can be ignored or cleaned)
    pyinstaller --noconfirm --clean \
                --name="${EXECUTABLE_NAME}" \
                --windowed \
                --onefile \
                --add-data="${SOURCE_ICON_PATH}:data/icons" \
                --add-data="data:data" \
                --add-data="${PACKAGE_NAME}/services/templates:templates" \
                --icon="$SOURCE_ICON_PATH" \
                --distpath="${appdir_path}/usr/bin" \
                --workpath="${BUILD_OUTPUT_DIR}" \
                "${PACKAGE_NAME}/main.py" # Main script entry point

    # Check if PyInstaller succeeded and the executable exists
    local final_executable="${appdir_path}/usr/bin/${EXECUTABLE_NAME}"
    if [[ ! -f "$final_executable" ]]; then
        log_error "PyInstaller build failed or executable not found at: ${final_executable}"
        exit 1
    fi
    # Ensure it's executable (PyInstaller usually does this, but verify)
    chmod +x "$final_executable"
    log_info "${GREEN}PyInstaller build successful. Executable at: ${final_executable}${NC}"
}

# Create the AppRun script for the AppImage
create_apprun() {
    local appdir_path="$1"
    local apprun_script="${appdir_path}/AppRun"

    log_info "Creating AppRun script at: ${apprun_script}"
    cat > "$apprun_script" << EOF
#!/bin/bash
# AppRun script for ${PROJECT_NAME}

# Find the location of this script
HERE="\$(dirname "\$(readlink -f "\${0}")")"

# Set up environment variables relative to the AppDir
export PATH="\${HERE}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="\${HERE}/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
# Add library path potentially needed by PySide/Qt plugins if bundled under usr/plugins or usr/qt5/plugins etc.
# export QT_PLUGIN_PATH="\${HERE}/usr/plugins:\${HERE}/usr/qt5/plugins:\${QT_PLUGIN_PATH}"

# Optional: Wayland/X11 specific environment tweaks (keep simple unless needed)
# if [ "\$XDG_SESSION_TYPE" = "wayland" ]; then
#     echo "AppRun: Wayland session detected. Applying Wayland flags." >&2 # Log to stderr
#     # Uncomment these if needed and tested
#     # export QT_QPA_PLATFORM=wayland
#     # export GDK_BACKEND=wayland
# fi

# Launch the main executable located within the AppDir structure
# Use exec to replace the shell process with the application process
exec "\${HERE}/usr/bin/${EXECUTABLE_NAME}" "\$@"

# Exit with the application's exit code (exec handles this implicitly)
exit \$?
EOF

    # Make the AppRun script executable
    chmod +x "$apprun_script"
    log_info "AppRun script created and made executable."
}

# Find or download the appimagetool utility
# Returns the command/path via stdout, logs info/errors to stderr
find_or_download_appimagetool() {
    # Use command -v for POSIX compliance and better error handling
    local tool_path
    tool_path=$(command -v appimagetool)

    if [[ $? -eq 0 && -x "$tool_path" ]]; then
        log_info "Using system appimagetool: $tool_path"
        echo "$tool_path" # Echo ONLY the path/command to stdout
        return 0
    fi

    log_warn "appimagetool not found in PATH or not executable. Attempting to download..." >&2 # Log to stderr
    local temp_tool_path
    # Create a temporary file securely
    temp_tool_path=$(mktemp --suffix=-appimagetool.AppImage)
    # Ensure cleanup on script exit or error IF the temp file still exists
    # The trap is removed if the function succeeds and returns the path
    trap 'rm -f "$temp_tool_path"' EXIT TERM INT HUP

    local appimagetool_url="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    # Use wget flags for better feedback in CI, while still being quiet on success
    if wget --quiet --show-progress -O "$temp_tool_path" "$appimagetool_url"; then
        chmod +x "$temp_tool_path"
        log_info "Downloaded appimagetool to: ${temp_tool_path}" >&2 # Log to stderr
        echo "$temp_tool_path" # Echo ONLY the path to stdout
        # Remove the trap specific to this temp file as we're returning its path successfully
        trap - EXIT TERM INT HUP
        return 0
    else
        log_error "Failed to download appimagetool from $appimagetool_url" >&2 # Log to stderr
        # Cleanup is handled by the trap
        return 1
    fi
}


# Create the final AppImage file
create_appimage_file() {
    local appdir_path="$1"
    local project_version="$2"

    log_info "Attempting to create AppImage..."

    local appimagetool_cmd
    # Capture ONLY stdout (the path) into the variable
    appimagetool_cmd=$(find_or_download_appimagetool)
    if [ $? -ne 0 ]; then
        log_error "Cannot proceed without appimagetool."
        # No need to exit here, error already logged, and function returned non-zero
        return 1 # Return failure status
    fi

    # Define the output AppImage filename (placed in the current directory)
    local output_filename="${EXECUTABLE_NAME}-${project_version}-x86_64.AppImage"

    log_info "Generating AppImage from '${appdir_path}' -> '${output_filename}'"

    # Run appimagetool
    # Set ARCH explicitly for some versions of the tool
    # Capture stderr from appimagetool to check for errors if needed
    local appimagetool_stderr
    # Redirect stderr to stdout and capture it, while checking the command's exit status
    if ! appimagetool_stderr=$(ARCH=x86_64 "$appimagetool_cmd" "$appdir_path" "$output_filename" 2>&1); then
         log_error "AppImage creation failed using '$appimagetool_cmd'."
         log_error "appimagetool output: $appimagetool_stderr"
         # Clean up downloaded tool if it was temporary
         if [[ "$appimagetool_cmd" == /tmp/* ]]; then
             rm -f "$appimagetool_cmd"
         fi
         return 1 # Return failure
    fi

    log_info "${GREEN}AppImage created successfully: ${output_filename}${NC}"
    chmod +x "$output_filename"


    # Clean up downloaded tool if it was temporary
    if [[ "$appimagetool_cmd" == /tmp/* ]]; then
        rm -f "$appimagetool_cmd"
    fi
    return 0 # Return success
}

# --- Main Script Logic ---

# Default values
VERSION_UPDATE=""
BUILD_ONLY=false
CREATE_APPIMAGE=false
DEBUG_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) show_help; exit 0 ;;
        --version-update) VERSION_UPDATE="$2"; shift 2 ;;
        --build-only) BUILD_ONLY=true; shift ;;
        --appimage) CREATE_APPIMAGE=true; shift ;;
        --debug) DEBUG_MODE=true; set -x; shift ;; # Enable command tracing
        *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# --- Pre-checks ---
log_info "=== ${PROJECT_NAME} Builder ==="
# Check if running from project root
if [[ ! -f "pyproject.toml" || ! -d "$PACKAGE_NAME" ]]; then
    log_error "This script must be run from the project root directory containing 'pyproject.toml' and the '${PACKAGE_NAME}/' directory."
    exit 1
fi
# Check source files exist early
if [[ ! -f "$SOURCE_ICON_PATH" ]]; then
    log_error "Source icon file not found: $SOURCE_ICON_PATH"
    exit 1
fi
 # Check for source desktop file (Warn only, as we generate one anyway)
 if [[ ! -f "$SOURCE_DESKTOP_PATH" ]]; then
    log_warn "Source desktop file not found: $SOURCE_DESKTOP_PATH (Using generated one for AppDir)"
fi


# --- Version Handling ---
if [[ -n "$VERSION_UPDATE" ]]; then
    update_version_files "$VERSION_UPDATE"
    if [[ "$BUILD_ONLY" = true ]]; then
        log_info "Version updated. Skipping build as requested (--build-only)."
        exit 0
    fi
fi

# --- Build Process ---
setup_venv
install_dependencies

# Get the current version AFTER potential update and installation
CURRENT_VERSION=$(python -c "import $PACKAGE_NAME; print($PACKAGE_NAME.__version__)")
log_info "Building project version: ${YELLOW}${CURRENT_VERSION}${NC}"

# Define the AppDir path based on the base directory
APPDIR_PATH="${APPDIR_BASE}/${PROJECT_NAME}.AppDir"

prepare_appdir "$APPDIR_PATH" "$CURRENT_VERSION"
build_executable "$APPDIR_PATH" # Fails internally if needed
create_apprun "$APPDIR_PATH"

# --- AppImage Creation (Optional) ---
if [[ "$CREATE_APPIMAGE" = true ]]; then
    # create_appimage_file returns non-zero on failure
    if ! create_appimage_file "$APPDIR_PATH" "$CURRENT_VERSION"; then
         log_error "AppImage creation step failed. See errors above."
         # Decide if failure to create AppImage should fail the whole script
         exit 1
    fi
else
    log_warn "Skipping AppImage creation. Use --appimage flag to create one."
fi

# --- Cleanup and Final Message ---
log_info "Cleaning up intermediate build files..."
rm -rf "$BUILD_OUTPUT_DIR" # Remove PyInstaller work directory
rm -f "${EXECUTABLE_NAME}.spec" # Remove PyInstaller spec file

# Optional: Deactivate venv if needed, though script exit usually handles this
# deactivate

log_info "${GREEN}=== Build process completed ===${NC}"
log_info "AppDir contents located in: '${APPDIR_PATH}'"
if [[ "$CREATE_APPIMAGE" = true ]]; then
    log_info "Final AppImage created in the current directory."
fi

# Explicitly exit with success code
exit 0