#!/bin/bash
# pre_install_audit.sh - Run BEFORE installing nix-darwin
# This script audits your current system to help you preserve important apps

echo "=== Mac Mini Pre-Install Audit ==="
echo "Run this before installing nix-darwin to inventory your current setup"
echo ""

echo "=== Current Hostname ==="
hostname -s
echo ""

echo "=== Homebrew Status ==="
if command -v brew &> /dev/null; then
    echo "✓ Homebrew is installed"
    echo "Version: $(brew --version | head -n1)"
else
    echo "✗ Homebrew not installed"
fi
echo ""

echo "=== Homebrew Casks (GUI Applications) ==="
if command -v brew &> /dev/null; then
    cask_count=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
    echo "Found $cask_count casks:"
    brew list --cask 2>/dev/null || echo "No casks installed"
else
    echo "Homebrew not installed - skipping"
fi
echo ""

echo "=== Homebrew Formulas (CLI Tools) ==="
if command -v brew &> /dev/null; then
    formula_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    echo "Found $formula_count formulas:"
    brew list --formula 2>/dev/null || echo "No formulas installed"
else
    echo "Homebrew not installed - skipping"
fi
echo ""

echo "=== All Applications in /Applications ==="
app_count=$(find /Applications -maxdepth 2 -name "*.app" 2>/dev/null | wc -l | tr -d ' ')
echo "Found $app_count applications:"
find /Applications -maxdepth 2 -name "*.app" 2>/dev/null | sed 's|.*/||' | sed 's/.app$//' | sort
echo ""

echo "=== All Applications in ~/Applications ==="
if [ -d ~/Applications ]; then
    user_app_count=$(find ~/Applications -maxdepth 2 -name "*.app" 2>/dev/null | wc -l | tr -d ' ')
    echo "Found $user_app_count applications:"
    find ~/Applications -maxdepth 2 -name "*.app" 2>/dev/null | sed 's|.*/||' | sed 's/.app$//' | sort
else
    echo "~/Applications directory does not exist"
fi
echo ""

echo "=== Xcode Command Line Tools ==="
if xcode-select -p &> /dev/null; then
    echo "✓ Installed at: $(xcode-select -p)"
else
    echo "✗ Not installed"
fi
echo ""

echo "=== Nix Status ==="
if command -v nix &> /dev/null; then
    echo "✓ Nix is installed"
    echo "Version: $(nix --version)"
else
    echo "✗ Nix not installed"
fi
echo ""

echo "=== Identifying Non-Homebrew Apps ==="
if command -v brew &> /dev/null; then
    echo "Comparing installed apps with Homebrew casks..."
    
    # Get list of apps managed by Homebrew
    homebrew_apps=$(brew list --cask 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' -')
    
    # Get all installed apps
    all_apps=$(find /Applications ~/Applications -maxdepth 2 -name "*.app" 2>/dev/null)
    
    non_homebrew_apps=()
    while IFS= read -r app_path; do
        if [ -n "$app_path" ]; then
            app_name=$(basename "$app_path" .app)
            app_normalized=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr -d ' -')
            
            # Check if this app is NOT in Homebrew list
            if ! echo "$homebrew_apps" | grep -q "^${app_normalized}$"; then
                non_homebrew_apps+=("$app_name")
            fi
        fi
    done <<< "$all_apps"
    
    if [ ${#non_homebrew_apps[@]} -gt 0 ]; then
        echo "Found ${#non_homebrew_apps[@]} apps not installed via Homebrew:"
        printf '%s\n' "${non_homebrew_apps[@]}" | sort
    else
        echo "All apps appear to be managed by Homebrew"
    fi
else
    echo "Homebrew not installed - cannot compare"
fi
echo ""

echo "=== Next Steps ==="
echo "1. Review the lists above"
echo "2. Compare against hosts/common/darwin/homebrew.nix in the nix-config"
echo "3. Add any important apps to homebrew.nix:"
echo "   - GUI apps → homebrew.casks"
echo "   - CLI tools → homebrew.brews"
echo "   - App Store apps → homebrew.masApps (need app ID)"
echo ""
echo "4. To find App Store app IDs:"
echo "   mas list  # (if mas is installed)"
echo "   # Or search: https://apps.apple.com/"
echo ""
echo "5. After updating homebrew.nix, proceed with nix-darwin installation"
echo ""

# Optional: Generate manual install list
echo "📝 Generate a list of apps to manually install? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    manual_apps_file="$HOME/manual-apps-$(date +%Y%m%d-%H%M%S).md"
    
    echo "# Manually Installed Apps" > "$manual_apps_file"
    echo "" >> "$manual_apps_file"
    echo "Apps that need to be installed manually (not available via Homebrew/MAS):" >> "$manual_apps_file"
    echo "" >> "$manual_apps_file"
    
    if command -v brew &> /dev/null && [ ${#non_homebrew_apps[@]} -gt 0 ]; then
        echo "Select apps to track as manual installs (space-separated numbers, or 'all', or 'done'):"
        echo ""
        
        # Display numbered list
        i=1
        for app in "${non_homebrew_apps[@]}"; do
            echo "$i) $app"
            ((i++))
        done
        echo ""
        echo "Enter selection (e.g., '1 3 5' or 'all' or 'done' to skip):"
        read -r selection
        
        selected_apps=()
        if [[ "$selection" == "all" ]]; then
            selected_apps=("${non_homebrew_apps[@]}")
        elif [[ "$selection" != "done" ]] && [[ -n "$selection" ]]; then
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#non_homebrew_apps[@]} ]; then
                    idx=$((num - 1))
                    selected_apps+=("${non_homebrew_apps[$idx]}")
                fi
            done
        fi
        
        if [ ${#selected_apps[@]} -gt 0 ]; then
            for app in "${selected_apps[@]}"; do
                echo "- [ ] **$app**" >> "$manual_apps_file"
                echo "  - Download: [Add URL]" >> "$manual_apps_file"
                echo "  - Notes: " >> "$manual_apps_file"
                echo "" >> "$manual_apps_file"
            done
            echo "✓ Manual apps list saved to: $manual_apps_file"
            echo ""
            echo "You can add this to your README or keep it as a reference."
        else
            echo "No apps selected."
            rm "$manual_apps_file"
        fi
    else
        echo "No non-Homebrew apps to track."
        rm "$manual_apps_file"
    fi
fi
echo ""

# Optional: Save full audit to file
echo "💾 Save full audit output to a file? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    output_file="$HOME/mac-mini-audit-$(date +%Y%m%d-%H%M%S).txt"
    
    # Re-run the script non-interactively and capture output
    echo "✓ Saving audit to: $output_file"
    
    # Create a temporary script that answers 'n' to all prompts
    {
        echo "=== Mac Mini Pre-Install Audit ==="
        echo "Run this before installing nix-darwin to inventory your current setup"
        echo ""
        
        echo "=== Current Hostname ==="
        hostname -s
        echo ""
        
        echo "=== Homebrew Status ==="
        if command -v brew &> /dev/null; then
            echo "✓ Homebrew is installed"
            echo "Version: $(brew --version | head -n1)"
        else
            echo "✗ Homebrew not installed"
        fi
        echo ""
        
        echo "=== Homebrew Casks (GUI Applications) ==="
        if command -v brew &> /dev/null; then
            cask_count=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
            echo "Found $cask_count casks:"
            brew list --cask 2>/dev/null || echo "No casks installed"
        else
            echo "Homebrew not installed - skipping"
        fi
        echo ""
        
        echo "=== Homebrew Formulas (CLI Tools) ==="
        if command -v brew &> /dev/null; then
            formula_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
            echo "Found $formula_count formulas:"
            brew list --formula 2>/dev/null || echo "No formulas installed"
        else
            echo "Homebrew not installed - skipping"
        fi
        echo ""
        
        echo "=== All Applications in /Applications ==="
        app_count=$(find /Applications -maxdepth 2 -name "*.app" 2>/dev/null | wc -l | tr -d ' ')
        echo "Found $app_count applications:"
        find /Applications -maxdepth 2 -name "*.app" 2>/dev/null | sed 's|.*/||' | sed 's/.app$//' | sort
        echo ""
        
        echo "=== All Applications in ~/Applications ==="
        if [ -d ~/Applications ]; then
            user_app_count=$(find ~/Applications -maxdepth 2 -name "*.app" 2>/dev/null | wc -l | tr -d ' ')
            echo "Found $user_app_count applications:"
            find ~/Applications -maxdepth 2 -name "*.app" 2>/dev/null | sed 's|.*/||' | sed 's/.app$//' | sort
        else
            echo "~/Applications directory does not exist"
        fi
        echo ""
        
        echo "=== Xcode Command Line Tools ==="
        if xcode-select -p &> /dev/null; then
            echo "✓ Installed at: $(xcode-select -p)"
        else
            echo "✗ Not installed"
        fi
        echo ""
        
        echo "=== Nix Status ==="
        if command -v nix &> /dev/null; then
            echo "✓ Nix is installed"
            echo "Version: $(nix --version)"
        else
            echo "✗ Nix not installed"
        fi
        echo ""
        
        echo "=== Identifying Non-Homebrew Apps ==="
        if command -v brew &> /dev/null; then
            echo "Comparing installed apps with Homebrew casks..."
            
            homebrew_apps=$(brew list --cask 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' -')
            all_apps=$(find /Applications ~/Applications -maxdepth 2 -name "*.app" 2>/dev/null)
            
            non_homebrew_apps_list=()
            while IFS= read -r app_path; do
                if [ -n "$app_path" ]; then
                    app_name=$(basename "$app_path" .app)
                    app_normalized=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr -d ' -')
                    
                    if ! echo "$homebrew_apps" | grep -q "^${app_normalized}$"; then
                        non_homebrew_apps_list+=("$app_name")
                    fi
                fi
            done <<< "$all_apps"
            
            if [ ${#non_homebrew_apps_list[@]} -gt 0 ]; then
                echo "Found ${#non_homebrew_apps_list[@]} apps not installed via Homebrew:"
                printf '%s\n' "${non_homebrew_apps_list[@]}" | sort
            else
                echo "All apps appear to be managed by Homebrew"
            fi
        else
            echo "Homebrew not installed - cannot compare"
        fi
        echo ""
        
        echo "=== Audit Complete ==="
        echo "Saved: $(date)"
    } > "$output_file"
    
    echo "✓ Saved to: $output_file"
fi

