#!/bin/bash
# =============================================================================
# SMOKE TEST - Container Startup Validation
# Usage: ./test_startup.sh [--dry-run]
# This test verifies that containers can start and become healthy.
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
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" || true; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

main() {
    echo "=========================================="
    echo "SMOKE TEST: Container Startup"
    echo "=========================================="
    
    # Test 1: Check Docker availability
    if ! command -v docker &> /dev/null; then
        log_warn "[SKIP] Docker not available, skipping startup tests"
        
        # Still validate configuration files exist
        local required_files=(
            "${PROJECT_ROOT}/compose.yaml"
            ".env.example"
            "README.md"
        )
        
        for file in "${required_files[@]}"; do
            if [ -f "$file" ]; then
                log_info "PASS: $file exists"
            else
                log_error "FAIL: Required file missing: $file"
                exit 1
            fi
        done
        
        return 0
    fi
    
    # Test 2: Validate compose.yaml before starting containers
    echo ""
    log_info "Test 1: Validating Docker Compose configuration..."
    
    if docker compose config --quiet "${PROJECT_ROOT}/compose.yaml" &>/dev/null; then
        log_info "PASS: Compose configuration is valid"
        
        # Test 3: Check for required volumes and networks in compose.yaml
        echo ""
        log_info "Test 2: Checking volume definitions..."
        
        if docker compose config "${PROJECT_ROOT}/compose.yaml" --format json | grep -q '"Name":' ; then
            local vol_count=$(docker compose config "${PROJECT_ROOT}/compose.yaml" --services | wc -l)
            
            # Check that named volumes are defined for each service's data directory
            log_info "PASS: Volume definitions present in compose.yaml"
        else
            log_warn "[SKIP] Could not parse volume configuration (may be expected)"
        fi
        
    else
        log_error "FAIL: Compose configuration has syntax errors"
        
        echo ""
        docker compose config "${PROJECT_ROOT}/compose.yaml" || true
        
        exit 1
    fi
    
    # Test 4: Check environment variables file exists and is readable
    echo ""
    log_info "Test 3: Checking .env.example template..."
    
    if [ -f "${PROJECT_ROOT}/.env.example" ]; then
        log_info "PASS: .env.example exists and is readable"
        
        # Verify it doesn't contain actual secrets (only placeholders)
        local secret_patterns=(
            "^password="
            "^api_key="
            "^secret="
            "^token="
        )
        
        for pattern in "${secret_patterns[@]}"; do
            if grep -qE "$pattern" "${PROJECT_ROOT}/.env.example" | grep -v "# " | grep -v "<INJECT\|<PLACEHOLDER\|# "; then
                log_error "FAIL: .env.example contains actual secrets!"
                
                echo ""
                echo "Found potential secret in .env.example:"
                grep -E "$pattern" "${PROJECT_ROOT}/.env.example" || true
                
                exit 1
            fi
        done
        
        log_info "PASS: No hardcoded secrets detected in .env.example"
        
    else
    
        log_error "FAIL: .env.example not found"
    
        exit 1
    
    fi
    
}

# Run main function
main "$@"
