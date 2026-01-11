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

# Optional: Save to file
echo "💾 Save this output to a file? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    output_file="$HOME/mac-mini-audit-$(date +%Y%m%d-%H%M%S).txt"
    $0 2>&1 | grep -v "Save this output" > "$output_file"
    echo "✓ Saved to: $output_file"
fi

