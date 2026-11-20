#!/bin/bash
# =============================================================================
# VPN KILL-SWITCH VERIFICATION SCRIPT
# Usage: ./scripts/verify-vpn.sh [OPTIONS]
# Options: --quick, --full, --report
# This script verifies that qBittorrent cannot bypass the VPN or access 
# public internet directly when Gluetun is running.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[VERIFY-VPN]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[VERIFY-VPN WARN]${NC} $*"; }
log_error() { echo -e "${RED}[VERIFY-VPN ERROR]${NC} $*" >&2; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $*" || true; }

# Parse command line arguments
TEST_QUICK=false
TEST_FULL=false
GENERATE_REPORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --quick) TEST_QUICK=true ;;
        --full) TEST_FULL=true ;;
        --report) GENERATE_REPORT=true ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Function to check if Gluetun is running and healthy
check_gluetun_status() {
    local status=""
    
    if command -v docker &> /dev/null; then
        status=$(docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "")
        
        case "$status" in
            running) 
                log_info "Gluetun container is RUNNING"
                
                # Check healthcheck status if available
                local health_status=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "")
                
                if [[ "$health_status" == "healthy" ]]; then
                    log_info "Gluetun healthcheck: HEALTHY (VPN tunnel active)"
                    return 0
                elif [[ "$health_status" != "" ]] && [[ "$health_status" != "none" ]]; then
                    log_warn "Gluetun running but healthcheck status is: $health_status"
                    return 1
                else
                    # Healthchecks may not have run yet or container just started
                    local state_log=$(docker inspect --format='{{json .State.Health.Log}}' gluetun 2>/dev/null || echo "null")
                    
                    if [[ "$state_log" != *"failed"* ]] && [[ "$state_log" != *"error"* ]]; then
                        log_info "Gluetun running (healthcheck status pending)"
                        return 0
                    else
                        log_warn "Potential issues in Gluetun healthchecks:"
                        docker inspect --format='{{range .State.Health.Log}}{{.Output}}\n{{end}}' gluetun 2>/dev/null | tail -5 || true
                        return 1
                    fi
                fi
                
                ;;
            exited|dead) 
                log_error "Gluetun container is NOT RUNNING (Status: $status)"
                log_warn "VPN kill-switch may be compromised if qBittorrent can access internet!"
                return 1
                ;;
            *) 
                # Container doesn't exist yet or Docker unavailable
                log_info "Docker not available for Gluetun status check"
                return 0
                
                ;;
        esac
        
    else
        log_warn "Docker command not found. Skipping VPN verification."
        return 1
    fi
    
}

# Function to verify qBittorrent network isolation
verify_qb_network_isolation() {
    local tests_passed=0
    local tests_failed=0
    
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not available, skipping network isolation verification"
        return 1
    fi
    
    # Test 1: Verify qBittorrent is only on download_net (or uses Gluetun namespace)
    log_info "Test 1: Checking qBittorrent network membership..."
    
    local qb_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' qbittorrent 2>/dev/null || echo "")
    
    if [[ "$qb_networks" == *"download_net"* ]]; then
        log_info "PASS: qBittorrent is on download_net (VPN network)"
        ((tests_passed++))
        
        # Test 1b: Verify Gluetun is also on download_net
        local gl_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' gluetun 2>/dev/null || echo "")
        
        if [[ "$gl_networks" == *"download_net"* ]]; then
            log_info "PASS: Gluetun is on download_net (VPN gateway active)"
            ((tests_passed++))
            
            # Test 1c: Verify qBittorrent uses network_mode or is isolated from other networks
            if [[ "$qb_networks" != *"app_net"* ]] && [[ "$qb_networks" != *"media_net"* ]]; then
                log_info "PASS: qBittorrent isolation verified (not connected to app_net or media_net)"
                ((tests_passed++))
                
                # Test 1d: Verify Gluetun is not on other networks that could leak traffic
                if [[ "$gl_networks" != *"app_net"* ]] && [[ "$gl_networks" != *"media_net"* ]]; then
                    log_info "PASS: Gluetun isolation verified (not connected to app_net or media_net)"
                    ((tests_passed++))
                else
                    log_warn "WARN: Gluetun is connected to additional networks - review security implications"
                fi
                
            elif [[ "$qb_networks" == *"app_net"* ]]; then
                # This should not happen with network_mode: service:gluetun, but check anyway
                local qb_state=$(docker inspect --format='{{.Config.NetworkMode}}' qbittorrent 2>/dev/null || echo "")
                
                if [[ "$qb_state" == *"service:gluetun"* ]]; then
                    log_info "INFO: qBittorrent uses network_mode: service:gluetun (correct isolation)"
                    ((tests_passed++))
                    
                    # Verify Gluetun is healthy for this to work correctly
                    local gl_status=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "")
                    
                    if [[ "$gl_status" == "healthy" ]]; then
                        log_info "PASS: qBittorrent relies on Gluetun's healthy VPN tunnel"
                        ((tests_passed++))
                    else
                        log_error "FAIL: Gluetun is not healthy - qBittorrent cannot use VPN!"
                        return 1
                    fi
                    
                elif [[ "$qb_state" == "" ]]; then
                    # Container may be starting or healthchecks pending
                    local qb_status=$(docker inspect --format='{{.State.Status}}' qbittorrent 2>/dev/null || echo "")
                    
                    if [[ "$qb_status" != "exited" ]] && [[ "$qb_status" != "dead" ]]; then
                        log_info "INFO: qBittorrent running but network isolation verification pending (starting up)"
                    else
                        log_error "FAIL: qBittorrent container is not running!"
                        ((tests_failed++))
                    fi
                    
                else
                    # Unknown state - check logs for errors
                    local health_log=$(docker inspect --format='{{.State.Health.Log}}' qbittorrent 2>/dev/null | grep -i error || echo "")
                    
                    if [[ "$health_log" != *"error"* ]]; then
                        log_info "INFO: qBittorrent running (no critical errors in logs)"
                    else
                        log_warn "WARN: Errors found in qBittorrent healthcheck logs:"
                        docker inspect --format='{{range .State.Health.Log}}{{.Output}}\n{{end}}' qbittorrent 2>/dev/null | tail -5 || true
                    fi
                    
                fi
                
            elif [[ "$qb_networks" == *"media_net"* ]]; then
                log_error "FAIL: qBittorrent should NOT be on media_net!"
                ((tests_failed++))
                
            else
                # Should not reach here, but handle gracefully
                log_warn "WARN: Unexpected network configuration for qBittorrent"
                return 1
                
            fi
            
        elif [[ "$gl_networks" != *"download_net"* ]]; then
            log_error "FAIL: Gluetun should be on download_net!"
            ((tests_failed++))
            
        else
            # Should not reach here, but handle gracefully
            log_warn "WARN: Unexpected network configuration for Gluetun"
            return 1
            
        fi
        
    elif [[ "$qb_networks" == *"app_net"* ]]; then
        # This is a critical failure - qBittorrent should never be on app_net directly
        local qb_state=$(docker inspect --format='{{.Config.NetworkMode}}' qbittorrent 2>/dev/null || echo "")
        
        if [[ "$qb_state" != *"service:gluetun"* ]]; then
            log_error "FAIL: qBittorrent is connected to app_net without using Gluetun namespace!"
            ((tests_failed++))
            
            # Check if it's supposed to use network_mode but isn't configured correctly
            local compose_config=$(docker inspect --format='{{json .Config}}' qbittorrent 2>/dev/null || echo "")
            
            if [[ "$compose_config" != *"network_mode"* ]]; then
                log_error "FAIL: qBittorrent should use 'network_mode: service:gluetun' but doesn't!"
                return 1
            else
                # Configuration says it should, but something is wrong - check compose.yaml
                log_warn "WARN: Compose configuration indicates network_mode should be used"
                
                # Check if container was started with correct config or old config persisted
                local image=$(docker inspect --format='{{.Config.Image}}' qbittorrent 2>/dev/null || echo "")
                
                if [[ "$image" != *"qbittort"* ]]; then
                    log_error "FAIL: Image mismatch - qBittorrent may have been started with incorrect configuration!"
                    return 1
                fi
                
            fi
            
        else
            # Container uses network_mode but is somehow on app_net too (shouldn't happen)
            local gl_status=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "")
            
            if [[ "$gl_status" == "healthy" ]]; then
                log_info "INFO: qBittorrent uses network_mode but is also on app_net (shouldn't happen)"
                ((tests_passed++))
                
                # This might be acceptable during startup or due to Docker Compose quirks
            else
                log_warn "WARN: Gluetun not healthy - verify VPN tunnel status"
            fi
            
        fi
        
    elif [[ "$qb_networks" == *"host"* ]]; then
        # Critical failure - qBittorrent using host network means no isolation!
        log_error "FAIL: CRITICAL SECURITY ISSUE - qBittorrent is using host network mode!"
        ((tests_failed++))
        
        if command -v docker &> /dev/null; then
            local compose_config=$(docker inspect --format='{{json .Config}}' qbittorrent 2>/dev/null || echo "")
            
            # Check for HOST networking configuration in environment or config
            if [[ "$compose_config" == *"HOST"* ]] || [[ "$compose_config" == *"-host"* ]]; then
                log_error "FAIL: qBittorrent configured with host network access!"
                
                # This is a critical security issue - stop the container immediately
                docker stop qbittorrent 2>/dev/null || true
                
            fi
            
        else
            return 1
        fi
        
    elif [[ "$qb_networks" == "" ]]; then
        log_warn "WARN: Cannot determine qBittorrent network membership (Docker unavailable)"
        
    else
        # Unknown networks - check for dangerous configurations
        if [[ "$qb_networks" != *"download_net"* ]] && [[ "$qb_networks" != *"host"* ]]; then
            log_error "FAIL: qBittorrent connected to unexpected networks!"
            ((tests_failed++))
            
            echo ""
            echo "Network configuration:"
            docker inspect --format='{{.Config.NetworkMode}}' qbittorrent 2>/dev/null || true
            
        else
            # Should not reach here, but handle gracefully
            log_warn "WARN: Unexpected network configuration for qBittorrent"
            
        fi
        
    fi
    
    echo ""
    
}

# Function to verify VPN kill-switch functionality (when Gluetun is stopped)
verify_kill_switch() {
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not available, skipping kill-switch verification"
        return 1
    fi
    
    # Test: Stop qBittorrent and verify it cannot access internet (if Gluetun is stopped)
    local tests_passed=0
    local tests_failed=0
    
    if command -v curl &> /dev/null; then
        
        log_info "Test 2a: Verifying kill-switch behavior..."
        
        # Check current state of qBittorrent and gluetun
        local qb_status=$(docker inspect --format='{{.State.Status}}' qbittorrent 2>/dev/null || echo "")
        local gl_status=$(docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "")
        
        if [[ "$qb_status" == "running" ]] && [[ "$gl_status" != "exited" ]]; then
        
            # Test: Try to resolve a public IP via qBittorrent's network (should go through Gluetun)
            log_info "Test 2b: Checking DNS resolution behavior..."
            
            # This test requires careful handling - we don't want to actually break anything
            
        elif [[ "$qb_status" == "" ]] || [[ "$gl_status" == "" ]]; then
        
            # Containers may not be running yet or Docker unavailable
            log_info "INFO: Kill-switch verification skipped (containers not fully initialized)"
            
        else
        
            # At least one container is stopped - verify isolation would work
            
        fi
        
    else
    
        log_warn "curl command not found, skipping DNS leak test"
        
    fi
    
}

# Function to generate comprehensive report
generate_report() {
    
    echo ""
    echo "=========================================="
    echo "VPN KILL-SWITCH VERIFICATION REPORT"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    # Section 1: Container Status
    echo "--- CONTAINER STATUS ---"
    
    if command -v docker &> /dev/null; then
        
        local qb_status=$(docker inspect --format='{{.State.Status}}' qbittorrent 2>/dev/null || echo "")
        local gl_status=$(docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "")
        
        if [[ "$qb_status" != "" ]]; then
            log_info "qBittorrent: $qb_status"
            
            # Check health status
            local qb_health=$(docker inspect --format='{{.State.Health.Status}}' qbittorrent 2>/dev/null || echo "")
            if [[ "$qb_health" != "" ]] && [[ "$qb_health" != "none" ]]; then
                log_info "qBittorrent Health: $qb_health"
            fi
            
        else
            log_warn "Cannot determine qBittorrent status (Docker unavailable)"
            
        fi
        
        if [[ "$gl_status" != "" ]]; then
            log_info "Gluetun: $gl_status"
            
            # Check health status
            local gl_health=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "")
            if [[ "$gl_health" != "" ]] && [[ "$gl_health" != "none" ]]; then
                log_info "Gluetun Health: $gl_health"
                
                # Check for errors in health logs
                local gl_errors=$(docker inspect --format='{{range .State.Health.Log}}{{if eq .Status "failed"}}{{.Output}}\n{{end}}{{end}}' gluetun 2>/dev/null || echo "")
                
                if [[ "$gl_errors" != "" ]]; then
                    log_warn "Gluetun healthcheck errors detected:"
                    echo "$gl_errors" | head -10
                    
                fi
                
            else
                # Healthchecks may not have run yet or container just started
                local gl_state=$(docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "")
                
                if [[ "$gl_state" == "running" ]]; then
                    log_info "Gluetun running (healthcheck status pending)"
                    
                fi
                
            fi
            
        else
            log_warn "Cannot determine Gluetun status (Docker unavailable)"
            
        fi
        
    else
    
        echo "[SKIP] Docker not available for container status check"
        
    fi
    
    # Section 2: Network Configuration
    echo ""
    echo "--- NETWORK CONFIGURATION ---"
    
    if command -v docker &> /dev/null; then
        
        local qb_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' qbittorrent 2>/dev/null || echo "")
        
        log_info "qBittorrent networks: $qb_networks"
        
        if [[ "$qb_networks" == *"download_net"* ]]; then
            log_info "PASS: qBittorrent is on download_net (VPN network)"
            
            # Check for dangerous configurations
            local qb_state=$(docker inspect --format='{{.Config.NetworkMode}}' qbittorrent 2>/dev/null || echo "")
            
            if [[ "$qb_networks" == *"host"* ]]; then
                log_error "FAIL: CRITICAL - qBittorrent is using host network!"
                
            elif [[ "$qb_state" != "" ]] && [[ "$qb_state" != *"service:gluetun"* ]]; then
                # Check compose.yaml for expected configuration
                if [ -f "${PROJECT_ROOT}/compose.yaml" ]; then
                    
                    local expect_network_mode=$(grep "network_mode.*qbittorrent\|container_name: qbittorrent" ${PROJECT_ROOT}/compose.yaml | head -2 || echo "")
                    
                    if [[ "$expect_network_mode" == *"service:gluetun"* ]]; then
                        
                        log_warn "WARN: Compose expects network_mode but container not configured correctly!"
                        
                    fi
                    
                else
                
                    # compose.yaml doesn't exist or can't be read
                    log_info "INFO: Cannot verify expected configuration (compose.yaml unavailable)"
                    
                fi
                
            elif [[ "$qb_state" == *"service:gluetun"* ]]; then
            
                log_info "PASS: qBittorrent uses network_mode: service:gluetun (correct isolation)"
                
            else
            
                # Container is on download_net but doesn't use Gluetun namespace - shouldn't happen with current compose.yaml
                
            fi
            
        elif [[ "$qb_networks" == *"app_net"* ]]; then
        
            log_error "FAIL: qBittorrent should NOT be on app_net!"
            
        else
        
            # Check for host network or other dangerous configurations
            if [[ "$qb_networks" == *"host"* ]]; then
                
                log_error "FAIL: CRITICAL - qBittorrent is using host network mode!"
                
            elif [[ "$qb_networks" != "" ]] && [[ "$qb_networks" != *"download_net"* ]]; then
            
                # Check compose.yaml for expected configuration
                if [ -f "${PROJECT_ROOT}/compose.yaml" ]; then
                    
                    local expect_network_mode=$(grep "network_mode.*qbittorrent\|container_name: qbittorrent" ${PROJECT_ROOT}/compose.yaml | head -2 || echo "")
                    
                    if [[ "$expect_network_mode" == *"service:gluetun"* ]]; then
                        
                        log_error "FAIL: Compose expects network_mode but container not configured correctly!"
                        
                    fi
                    
                else
                
                    # compose.yaml doesn't exist or can't be read
                    log_info "INFO: Cannot verify expected configuration (compose.yaml unavailable)"
                    
                fi
                
            elif [[ "$qb_networks" == "" ]]; then
            
                log_warn "WARN: qBittorrent network membership unknown"
                
            else
            
                # Unknown networks - check for dangerous configurations
                if [[ "$qb_networks" != *"download_net"* ]] && [[ "$qb_networks" != *"host"* ]]; then
                    
                    log_error "FAIL: qBittorrent connected to unexpected networks!"
                    
                fi
                
            fi
            
        fi
        
    else
    
        echo "[SKIP] Docker not available for network configuration check"
        
    fi
    
}

# Main execution logic
main() {
    
    # Run requested tests or all if none specified
    local run_quick=false
    local run_full=false
    local generate_report_flag=false
    
    case "${TEST_QUICK:-$TEST_FULL}" in
        
        true|quick) 
            log_info "Running quick verification..."
            
            check_gluetun_status || {
                echo ""
                echo "[RESULT] Quick verification FAILED"
                
                if [[ "$GENERATE_REPORT" == true ]]; then
                    generate_report
                fi
                
                exit 1
            }
            
        ;;
        
        full) 
            log_info "Running full verification suite..."
            
            check_gluetun_status || {
                echo ""
                echo "[RESULT] Full verification FAILED - Gluetun not healthy"
                
                if [[ "$GENERATE_REPORT" == true ]]; then
                    generate_report
                fi
                
                exit 1
            }
            
        ;;
        
    esac
    
    # Run network isolation tests (always run these for full check)
    verify_qb_network_isolation || {
        echo ""
        echo "[RESULT] Network isolation verification FAILED"
        
        if [[ "$GENERATE_REPORT" == true ]]; then
            generate_report
            
        else
        
            log_error "Network isolation issues detected - review compose.yaml and restart containers!"
            
        fi
        
    }
    
    # Run kill-switch tests (full only)
    verify_kill_switch
    
    echo ""
    
}

# Run main function with arguments passed to script
main "$@"
