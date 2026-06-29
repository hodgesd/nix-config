#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Removed -e temporarily to allow debug prints after potential errors
# set -euo pipefail
set -uo pipefail

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "Error: jq is not installed."
    echo "Please install it (e.g., with Homebrew: brew install jq) and run the script again."
    exit 1
fi

# Command to find all installed applications in common locations
FIND_APPS_COMMAND='find /Applications ~/Applications "/Applications/Nix Apps" -maxdepth 2 -name "*.app" 2>/dev/null | sort'

# Apps to always ignore: cask sub-bundles and known name-mismatch false
# positives that aren't really unmanaged. Match is on the app's basename with
# the .app extension stripped.
IGNORE_APPS=(
    "Karabiner-EventViewer"             # bundled with the karabiner-elements cask
    "Karabiner-VirtualHIDDevice-Manager"
    "Ice"                               # managed via jordanbaird-ice cask
    "Mona 6"                            # managed via masApps "Mona"
)

# --- Functions ---

# Function to normalize an app name for comparison
# Removes .app extension, converts to lowercase, and removes spaces and hyphens
normalize_name() {
    local name="$1"
    # Get the last component of the path, just get the base name
    name=$(basename "$name")

    # Remove .app extension first (case-insensitive)
    local name_no_ext=$(echo "$name" | sed 's/\.app$//i')

    # Convert to lowercase and remove spaces and hyphens
    local normalized=$(echo "$name_no_ext" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]-')

    # echo "DEBUG: Normalized '$name' to '$normalized'" >&2 # Optional: add this for even more detailed tracing
    echo "$normalized"
}

# Function to detect built-in macOS system apps (Safari, Feedback Assistant, etc.)
# These are signed with "macOS Software Signing". Apple App Store apps (Keynote,
# Numbers, ...) use "Apple Mac OS Application Signing" and are NOT matched here,
# so apps you manage via masApps still get reported if missing from your config.
is_system_app() {
    local app="$1"
    # Capture first, then grep: piping codesign directly into `grep -q` lets grep
    # close the pipe early, giving codesign SIGPIPE — and under `pipefail` that
    # makes the whole check spuriously report non-system.
    local sig
    sig=$(codesign -dvv "$app" 2>&1)
    grep -q '^Authority=macOS Software Signing' <<< "$sig"
}

# --- Main Script ---

echo "Finding all installed applications..."
# Use a while loop with process substitution for portability to read lines into array
installed_apps=()
while IFS= read -r line; do
    installed_apps+=("$line")
done < <(eval "$FIND_APPS_COMMAND")


if [ ${#installed_apps[@]} -eq 0 ]; then
    echo "No installed applications (.app bundles) found in the specified directories."
    exit 0
fi

echo "Evaluating Nix darwin configuration..."
# Get managed cask and masApp names from the Nix darwin configuration using jq
# This reads the actual darwin configuration, not the nix daemon settings
# Note: Replace 'mini' with your hostname if different
HOSTNAME=$(hostname -s)
# Note: homebrew.casks entries are submodule objects ({name, args, ...}) in
# current nix-darwin, but were plain strings in older versions. Handle both:
# `objects | .name` for the new form, `strings` for the old.
managed_names_raw=$(nix eval .#darwinConfigurations.${HOSTNAME}.config.homebrew --json 2>/dev/null | jq -r '(.casks[]? | objects | .name), (.casks[]? | strings), ((.masApps? // {}) | keys[]? // empty)')

# Create a temporary file to store normalized managed names
# Use a trap to ensure the temp file is removed even if the script errors
managed_names_file=$(mktemp)
trap 'rm -f "$managed_names_file"' EXIT # Ensure cleanup on exit

echo "Normalizing and collecting managed app names..."
# Normalize managed names and store them in the temporary file, one per line
# Sort the list for slightly faster lookups with grep later
echo "$managed_names_raw" | while IFS= read -r name; do
    # Check if name is not empty (jq might output empty lines)
    if [[ -n "$name" ]]; then
        normalized_managed=$(normalize_name "$name")
        # Uncomment for debug: echo "DEBUG: Managed raw '$name' normalized to '$normalized_managed'" >&2
        echo "$normalized_managed" >> "$managed_names_file"
    fi
done
sort -u "$managed_names_file" -o "$managed_names_file"

# Uncomment for debug output:
# echo "DEBUG: Contents of normalized managed names file ($managed_names_file):" >&2
# cat "$managed_names_file" >&2
# echo "---" >&2


echo "Comparing installed apps against managed list..."
unmanaged_apps=()
for app_path in "${installed_apps[@]}"; do
    # Normalize the installed app name
    normalized_installed_name=$(normalize_name "$app_path")

    # echo "DEBUG: Checking installed app '$app_path' normalized to '$normalized_installed_name'" >&2 # Optional: very verbose debug

    app_base=$(basename "$app_path")

    # Skip hidden apps (dot-prefixed): always internal helper bundles
    if [[ "$app_base" == .* ]]; then
        continue
    fi

    # Skip explicitly-ignored apps (cask sub-bundles, known false positives)
    app_name_no_ext="${app_base%.app}"
    skip=false
    for ignore in "${IGNORE_APPS[@]}"; do
        if [[ "$app_name_no_ext" == "$ignore" ]]; then
            skip=true
            break
        fi
    done
    if [[ "$skip" == true ]]; then
        continue
    fi

    # Skip built-in macOS system apps (e.g. Safari, Feedback Assistant)
    if is_system_app "$app_path"; then
        continue
    fi

    # Check if the normalized installed name exists in the temporary file of managed names
    # Use grep -Fqx for fixed string, quiet, exact line match
    if ! grep -Fqx "$normalized_installed_name" "$managed_names_file"; then
        # App name not found in the managed list, add the original path
        # echo "DEBUG: '$normalized_installed_name' NOT found." >&2 # Optional debug
        unmanaged_apps+=("$app_path")
    else
        # echo "DEBUG: '$normalized_installed_name' FOUND." >&2 # Optional debug
        : # Do nothing if found
    fi
done

echo -e "\n--- Unmanaged Applications ---"

if [ ${#unmanaged_apps[@]} -eq 0 ]; then
    echo "All found applications appear to be managed by your Nix configuration (via homebrew.casks or homebrew.masApps)."
else
    echo "The following installed applications are not listed in your Nix config's homebrew.casks or homebrew.masApps:"
    # Print each unmanaged app path
    for app in "${unmanaged_apps[@]}"; do
        echo "$app"
    done
fi

# The trap will handle removing the temporary file
