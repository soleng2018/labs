#!/bin/bash

# Test Script for Custom Ubuntu ISO Build
# This script performs basic validation of the custom ISO build setup

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[TEST-INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[TEST-SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[TEST-WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[TEST-ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PASSED=0
TEST_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "✓ $test_name"
        ((TEST_PASSED++))
        return 0
    else
        log_error "✗ $test_name"
        ((TEST_FAILED++))
        return 1
    fi
}

# Test 1: Check required files exist
test_required_files() {
    local required_files=(
        "build-custom-iso.sh"
        "custom-iso/user-data"
        "custom-iso/meta-data"
        "custom-iso/grub.cfg"
        "custom-iso/wifi-roam/parameters.txt"
        "custom-iso/wifi-roam/roam_script.sh"
        "custom-iso/wifi-roam/speedtest_script.sh"
        "custom-iso/wifi-roam/wifi_roam_setup.sh"
        "custom-iso/wifi-roam/wpa_supplicant.conf"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$file" ]; then
            log_error "Missing required file: $file"
            return 1
        fi
    done
    
    return 0
}

# Test 2: Check scripts are executable
test_executable_scripts() {
    local scripts=(
        "build-custom-iso.sh"
        "custom-iso/wifi-roam/roam_script.sh"
        "custom-iso/wifi-roam/speedtest_script.sh"
        "custom-iso/wifi-roam/wifi_roam_setup.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -x "$SCRIPT_DIR/$script" ]; then
            log_error "Script not executable: $script"
            return 1
        fi
    done
    
    return 0
}

# Test 3: Validate parameters.txt configuration
test_parameters_config() {
    local params_file="$SCRIPT_DIR/custom-iso/wifi-roam/parameters.txt"
    
    if ! grep -q "SSID=" "$params_file"; then
        log_error "SSID not found in parameters.txt"
        return 1
    fi
    
    if ! grep -q "USERNAME=" "$params_file"; then
        log_error "USERNAME not found in parameters.txt"
        return 1
    fi
    
    if ! grep -q "PASSWORD=" "$params_file"; then
        log_error "PASSWORD not found in parameters.txt"
        return 1
    fi
    
    return 0
}

# Test 4: Check wpa_supplicant template has placeholders
test_wpa_supplicant_template() {
    local wpa_file="$SCRIPT_DIR/custom-iso/wifi-roam/wpa_supplicant.conf"
    
    if ! grep -q "SSID_PLACEHOLDER" "$wpa_file"; then
        log_error "SSID_PLACEHOLDER not found in wpa_supplicant.conf"
        return 1
    fi
    
    if ! grep -q "USERNAME_PLACEHOLDER" "$wpa_file"; then
        log_error "USERNAME_PLACEHOLDER not found in wpa_supplicant.conf"
        return 1
    fi
    
    if ! grep -q "PASSWORD_PLACEHOLDER" "$wpa_file"; then
        log_error "PASSWORD_PLACEHOLDER not found in wpa_supplicant.conf"
        return 1
    fi
    
    return 0
}

# Test 5: Validate modified setup script
test_modified_setup_script() {
    local setup_script="$SCRIPT_DIR/custom-iso/wifi-roam/wifi_roam_setup.sh"
    
    # Check that the install_packages function has been modified for offline handling
    if ! grep -q "packages_missing" "$setup_script"; then
        log_error "Setup script doesn't appear to have offline handling modifications"
        return 1
    fi
    
    if ! grep -q "return 0.*Don't fail the entire setup" "$setup_script"; then
        log_error "Setup script doesn't gracefully handle package installation failures"
        return 1
    fi
    
    return 0
}

# Test 6: Validate modified speedtest script
test_modified_speedtest_script() {
    local speedtest_script="$SCRIPT_DIR/custom-iso/wifi-roam/speedtest_script.sh"
    
    # Check for offline handling
    if ! grep -q "Creating dummy speedtest-cli" "$speedtest_script"; then
        log_error "Speedtest script doesn't have offline handling"
        return 1
    fi
    
    if ! grep -q "return 0.*Don't fail the entire script" "$speedtest_script"; then
        log_error "Speedtest script doesn't gracefully handle installation failures"
        return 1
    fi
    
    return 0
}

# Test 7: Check user-data autoinstall configuration
test_autoinstall_config() {
    local user_data="$SCRIPT_DIR/custom-iso/user-data"
    
    if ! grep -q "autoinstall:" "$user_data"; then
        log_error "user-data doesn't contain autoinstall configuration"
        return 1
    fi
    
    if ! grep -q "wpasupplicant" "$user_data"; then
        log_error "user-data doesn't include wpasupplicant package"
        return 1
    fi
    
    if ! grep -q "dhcpcd5" "$user_data"; then
        log_error "user-data doesn't include dhcpcd5 package"
        return 1
    fi
    
    if ! grep -q "speedtest-cli" "$user_data"; then
        log_error "user-data doesn't include speedtest-cli package"
        return 1
    fi
    
    return 0
}

# Test 8: Check GRUB configuration
test_grub_config() {
    local grub_cfg="$SCRIPT_DIR/custom-iso/grub.cfg"
    
    if ! grep -q "autoinstall" "$grub_cfg"; then
        log_error "GRUB config doesn't contain autoinstall option"
        return 1
    fi
    
    if ! grep -q "WiFi Roaming Ubuntu" "$grub_cfg"; then
        log_error "GRUB config doesn't have custom menu entries"
        return 1
    fi
    
    return 0
}

# Test 9: Syntax check on shell scripts
test_script_syntax() {
    local scripts=(
        "build-custom-iso.sh"
        "custom-iso/wifi-roam/roam_script.sh"
        "custom-iso/wifi-roam/speedtest_script.sh"
        "custom-iso/wifi-roam/wifi_roam_setup.sh"
    )
    
    for script in "${scripts[@]}"; do
        if ! bash -n "$SCRIPT_DIR/$script"; then
            log_error "Syntax error in script: $script"
            return 1
        fi
    done
    
    return 0
}

# Test 10: Check build script prerequisites function
test_build_prerequisites() {
    local build_script="$SCRIPT_DIR/build-custom-iso.sh"
    
    if ! grep -q "check_prerequisites" "$build_script"; then
        log_error "Build script missing prerequisites check function"
        return 1
    fi
    
    if ! grep -q "xorriso.*wget.*unsquashfs" "$build_script"; then
        log_error "Build script missing required tool checks"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting Custom Ubuntu ISO Build Test Suite"
    log_info "============================================"
    
    cd "$SCRIPT_DIR"
    
    # Run all tests
    run_test "Required files exist" "test_required_files"
    run_test "Scripts are executable" "test_executable_scripts"
    run_test "Parameters configuration valid" "test_parameters_config"
    run_test "WPA supplicant template valid" "test_wpa_supplicant_template"
    run_test "Setup script has offline handling" "test_modified_setup_script"
    run_test "Speedtest script has offline handling" "test_modified_speedtest_script"
    run_test "Autoinstall configuration valid" "test_autoinstall_config"
    run_test "GRUB configuration valid" "test_grub_config"
    run_test "Shell script syntax valid" "test_script_syntax"
    run_test "Build script prerequisites check" "test_build_prerequisites"
    
    # Summary
    echo ""
    log_info "============================================"
    log_info "Test Results Summary"
    log_info "============================================"
    
    if [ $TEST_FAILED -eq 0 ]; then
        log_success "All tests passed! ($TEST_PASSED/$((TEST_PASSED + TEST_FAILED)))"
        log_success "Your custom ISO build setup is ready!"
        echo ""
        log_info "Next steps:"
        log_info "1. Review and customize parameters.txt if needed"
        log_info "2. Run: sudo ./build-custom-iso.sh"
        log_info "3. Wait for the build to complete"
        log_info "4. Test the resulting ISO file"
        echo ""
        exit 0
    else
        log_error "$TEST_FAILED test(s) failed out of $((TEST_PASSED + TEST_FAILED)) total"
        log_error "Please fix the issues above before building the ISO"
        echo ""
        exit 1
    fi
}

# Handle help option
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Custom Ubuntu ISO Build Test Suite"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "This script validates the custom ISO build setup by checking:"
    echo "  ✓ Required files are present"
    echo "  ✓ Scripts are executable"
    echo "  ✓ Configuration files are valid"
    echo "  ✓ Scripts have offline installation handling"
    echo "  ✓ Autoinstall configuration is correct"
    echo "  ✓ Shell script syntax is valid"
    echo ""
    echo "Run this test before attempting to build the custom ISO."
    exit 0
fi

# Run main function
main "$@"
