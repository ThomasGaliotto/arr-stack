#!/bin/bash
# =============================================================================
# SMOKE TEST - Docker Compose Configuration Validation
# Usage: ./test_compose_config.sh [--dry-run]
# This test validates that compose.yaml is syntactically correct and all 
# required environment variables are defined.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[SMOKE]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $*" || true; }

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

main() {
    echo "=========================================="
    echo "SMOKE TEST: Compose Configuration"
    echo "=========================================="
    
    # Test 1: Check compose.yaml exists
    if [ ! -f "${PROJECT_ROOT}/compose.yaml" ]; then
        log_error "FAIL: compose.yaml not found at ${PROJECT_ROOT}"
        exit 1
    fi
    
    log_info "PASS: compose.yaml exists"
    
    # Test 2: Validate Docker Compose syntax (if docker is available)
    if command -v docker &> /dev/null; then
        echo ""
        log_info "Test 1: Validating Docker Compose YAML syntax..."
        
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would run: docker compose config --quiet"
            
            # Check for common issues without running full validation
            local has_issues=false
            
            # Check for invalid keys (basic check)
            if grep -q "restart_policy:" "${PROJECT_ROOT}/compose.yaml"; then
                log_error "[DRY-RUN] Found unsupported key: restart_policy"
                has_issues=true
            fi
            
            if [ "$has_issues" = false ]; then
                log_info "PASS: No obvious syntax issues detected in compose.yaml"
            else
                exit 1
            fi
        else
            # Run actual validation
            if docker compose config --quiet "${PROJECT_ROOT}/compose.yaml" &>/dev/null; then
                log_info "PASS: Docker Compose configuration is valid"
            else
                log_error "FAIL: Docker Compose configuration has syntax errors"
                
                echo ""
                echo "Running 'docker compose config' to see details:"
                docker compose config "${PROJECT_ROOT}/compose.yaml" || true
                
                exit 1
            fi
            
            # Test 3: Check for required environment variables in .env.example
            log_info "Test 2: Checking .env.example template..."
            
            if [ ! -f "${PROJECT_ROOT}/.env.example" ]; then
                log_error "FAIL: .env.example not found"
                exit 1
            fi
            
            # Verify key environment variables are defined as placeholders
            local required_vars=(
                "HOST_UID="
                "HOST_GID="
                "HOST_TIMEZONE="
                "VPN_PROVIDER="
                "VPN_PROTOCOL="
                "QBITTORRENT_VERSION="
                "SONARR_VERSION="
                "RADARR_VERSION="
                "LIDARR_VERSION="
            )
            
            local missing_vars=()
            for var in "${required_vars[@]}"; do
                if ! grep -q "^${var}" "${PROJECT_ROOT}/.env.example" && \
                   ! grep -q "# ${var}" "${PROJECT_ROOT}/.env.example"; then
                    missing_vars+=("$var")
                fi
            done
            
            if [ ${#missing_vars[@]} -eq 0 ]; then
                log_info "PASS: All required environment variables defined in .env.example"
            else
                log_error "FAIL: Missing or incomplete env vars:"
                for var in "${missing_vars[@]}"; do
                    echo "  - $var"
                done
                exit 1
            fi
            
        fi
        
    else
        # Docker not available, skip runtime validation but check file structure
        log_warn "[SKIP] Docker not available, skipping compose config validation"
        
        # Still validate YAML syntax with basic checks
        if command -v python3 &> /dev/null; then
            echo ""
            log_info "Test 1: Validating YAML syntax (basic)..."
            
            if python3 -c "import yaml; yaml.safe_load(open('${PROJECT_ROOT}/compose.yaml'))" 2>/dev/null; then
                log_info "PASS: compose.yaml is valid YAML"
            else
                log_error "FAIL: compose.yaml has invalid YAML syntax"
                
                echo ""
                echo "YAML validation failed:"
                python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/compose.yaml')))" 2>&1 || true
                
                exit 1
            fi
            
        else
            log_warn "[SKIP] Python not available, skipping YAML syntax check"
            
            # Basic file existence checks instead
            if [ -f "${PROJECT_ROOT}/compose.yaml" ]; then
                log_info "PASS: compose.yaml exists and is readable"
                
                # Check for basic structure markers
                local has_services=$(grep -c "^services:" "${PROJECT_ROOT}/compose.yaml")
                local has_networks=$(grep -c "^networks:" "${PROJECT_ROOT}/compose.yaml")
                local has_volumes=$(grep -c "^volumes:" "${PROJECT_ROOT}/compose.yaml")
                
                if [ "$has_services" -gt 0 ] && \
                   [ "$has_networks" -gt 0 ] && \
                   [ "$has_volumes" -gt 0 ]; then
                    
                    log_info "PASS: compose.yaml has required sections (services, networks, volumes)"
                    
                else
                    
                    log_error "FAIL: compose.yaml missing required sections"
                    exit 1
                    
                fi
                
            else
            
                log_error "FAIL: compose.yaml not found"
                
                exit 1
                
            fi
        
        fi
    
    fi
    
}

# Run main function
main "$@"
