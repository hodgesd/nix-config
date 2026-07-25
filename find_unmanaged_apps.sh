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
cask_map_file=$(mktemp)
mas_map_file=$(mktemp)
trap 'rm -f "$managed_names_file" "$cask_map_file" "$mas_map_file"' EXIT # Ensure cleanup on exit

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

# Build a Homebrew cask lookup mapping each cask's installed .app bundle name to
# its token (e.g. "Rectangle.app<TAB>rectangle"). Sourced from the Homebrew API.
# If the fetch fails (offline, etc.) the map stays empty and cask detection is
# skipped gracefully. `|| true` keeps pipefail from aborting the script.
cask_lookup_available=false
echo "Fetching Homebrew cask catalog..."
if curl -fsS https://formulae.brew.sh/api/cask.json 2>/dev/null \
    | jq -r '.[] | .token as $t | (.artifacts[]? | .app[]? | strings) | "\(.)\t\($t)"' \
    > "$cask_map_file" 2>/dev/null \
    && [[ -s "$cask_map_file" ]]; then
    cask_lookup_available=true
else
    echo "Warning: could not reach the Homebrew API — skipping cask availability lookup." >&2
fi

# Build a Mac App Store lookup mapping each installed App Store app's name to its
# numeric id (e.g. "Affinity Photo<TAB>824183456"), from `mas list`.
mas_lookup_available=false
if command -v mas &> /dev/null; then
    # `mas list` prints "<id>  <name>            (<version>)". Strip the id and the
    # trailing (version), then any padding, so the name matches the .app basename.
    if mas list 2>/dev/null \
        | awk '{
            id=$1; line=$0
            sub(/^ *[0-9]+[ ]+/, "", line)        # drop leading id
            sub(/[ ]+\([^)]*\)[ ]*$/, "", line)   # drop trailing (version)
            sub(/[ ]+$/, "", line)                # drop any residual padding
            print line "\t" id
          }' \
        > "$mas_map_file"; then
        mas_lookup_available=true
    fi
else
    echo "Note: 'mas' not installed — skipping Mac App Store lookup." >&2
fi

echo "Comparing installed apps against managed list..."
cask_tokens=()      # unmanaged apps available as a Homebrew cask (token list)
mas_entries=()      # unmanaged App Store apps, as "Name|id" (id may be empty)
unmatched_apps=()   # unmanaged apps that are neither cask nor App Store
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
    if grep -Fqx "$normalized_installed_name" "$managed_names_file"; then
        # echo "DEBUG: '$normalized_installed_name' FOUND." >&2 # Optional debug
        continue # Already managed, nothing to do
    fi

    # Unmanaged. Classify it (cask-first, then App Store, then neither).
    # 1) Is there a cask whose .app bundle matches this app's basename?
    token=""
    if [[ "$cask_lookup_available" == true ]]; then
        token=$(awk -F'\t' -v a="$app_base" '$1==a{print $2; exit}' "$cask_map_file")
    fi
    if [[ -n "$token" ]]; then
        cask_tokens+=("$token")
    # 2) Was it installed from the Mac App Store? (authoritative: receipt file)
    elif [[ -e "$app_path/Contents/_MASReceipt/receipt" ]]; then
        id=""
        if [[ "$mas_lookup_available" == true ]]; then
            id=$(awk -F'\t' -v n="$app_name_no_ext" '$1==n{print $2; exit}' "$mas_map_file")
        fi
        mas_entries+=("$app_name_no_ext|$id")
    # 3) Neither a cask nor an App Store install.
    else
        unmatched_apps+=("$app_path")
    fi
done

echo -e "\n--- Unmanaged Applications ---"

if [ ${#cask_tokens[@]} -eq 0 ] && [ ${#mas_entries[@]} -eq 0 ] && [ ${#unmatched_apps[@]} -eq 0 ]; then
    echo "All found applications appear to be managed by your Nix configuration (via homebrew.casks or homebrew.masApps)."
fi

# --- Bucket 1: available as a Homebrew cask ---
if [ ${#cask_tokens[@]} -gt 0 ]; then
    # Sort + dedupe tokens.
    sorted_tokens=()
    while IFS= read -r t; do
        sorted_tokens+=("$t")
    done < <(printf '%s\n' "${cask_tokens[@]}" | sort -u)

    echo -e "\nAvailable as Homebrew cask (${sorted_tokens[*]}):"
    echo
    echo "  1) Adopt existing apps:"
    echo "     brew install --cask --adopt ${sorted_tokens[*]}"
    echo
    echo "  2) Add to homebrew.nix casks (sorted + indented to match):"
    for t in "${sorted_tokens[@]}"; do
        echo "      \"$t\""
    done
fi

# --- Bucket 2: installed from the Mac App Store ---
if [ ${#mas_entries[@]} -gt 0 ]; then
    echo -e "\nInstalled from Mac App Store — add to homebrew.nix masApps:"
    while IFS= read -r entry; do
        name="${entry%|*}"
        id="${entry##*|}"
        if [[ -n "$id" ]]; then
            echo "      \"$name\" = $id;"
        else
            echo "      \"$name\" = ; # run: mas search \"$name\""
        fi
    done < <(printf '%s\n' "${mas_entries[@]}" | sort -u)
fi

# --- Bucket 3: neither cask nor App Store ---
if [ ${#unmatched_apps[@]} -gt 0 ]; then
    echo -e "\nNot found as cask or App Store (manual install / candidate to remove):"
    for app in "${unmatched_apps[@]}"; do
        echo "  $app"
    done
fi

# The trap will handle removing the temporary files
