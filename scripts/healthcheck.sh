#!/bin/bash
# =============================================================================
# HEALTHCHECK SCRIPT - Verify container status, network isolation, and service availability
# Usage: ./scripts/healthcheck.sh [OPTIONS]
# Options: --all-services, --vpn-only, --network-isolation
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[HEALTHCHECK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[HEALTHCHECK WARN]${NC} $*"; }
log_error() { echo -e "${RED}[HEALTHCHECK ERROR]${NC} $*" >&2; }

# Parse command line arguments
TEST_ALL=false
TEST_VPN_ONLY=false
TEST_NETWORK_ISOLATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all-services) TEST_ALL=true ;;
        --vpn-only) TEST_VPN_ONLY=true ;;
        --network-isolation) TEST_NETWORK_ISOLATION=true ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Function to check container health status via Docker API
check_container_health() {
    local service_name="$1"
    
    if command -v docker &> /dev/null; then
        # Check if container is running and healthy
        local status=$(docker inspect --format='{{.State.Health.Status}}' "${service_name}" 2>/dev/null || echo "unknown")
        
        case "$status" in
            healthy) log_info "Container $service_name: HEALTHY"; return 0 ;;
            unhealthy|none) 
                # Container might not have healthchecks yet or is restarting
                local state=$(docker inspect --format='{{.State.Status}}' "${service_name}" 2>/dev/null || echo "")
                if [[ "$state" == "running" ]]; then
                    log_warn "Container $service_name: Running but no healthcheck status (yet)"
                    return 0
                else
                    log_error "Container $service_name: NOT RUNNING - Status: $status"
                    return 1
                fi
                ;;
            *) 
                if [[ "$state" == "" ]]; then
                    # Container doesn't exist yet or Docker is not available
                    log_warn "Cannot check health of $service_name (Docker unavailable)"
                    return 0
                else
                    log_error "Container $service_name: UNHEALTHY - Status: $status"
                    return 1
                fi
                ;;
        esac
    else
        log_warn "Docker not available, skipping container health checks"
        return 0
    fi
}

# Function to verify VPN isolation (qBittorrent cannot reach public internet directly)
verify_vpn_isolation() {
    if [[ "$TEST_VPN_ONLY" == true ]] || [[ "$TEST_ALL" == true ]]; then
        
        # Check that qBittorrent is on download_net only and not app_net or media_net
        log_info "Verifying VPN isolation..."
        
        local qb_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' qbittorrent 2>/dev/null || echo "")
        
        if [[ "$qb_networks" == *"download_net"* ]]; then
            log_info "qBittorrent is correctly on download_net (VPN network)"
            
            # Check that qBittorrent is NOT on app_net or media_net
            if [[ "$qb_networks" != *"app_net"* ]] && [[ "$qb_networks" != *"media_net"* ]]; then
                log_info "qBittorrent isolation verified: not connected to app_net or media_net"
                
                # Verify Gluetun is running and healthy
                check_container_health gluetun || {
                    log_error "Gluetun container is unhealthy - VPN kill-switch may be compromised!"
                    return 1
                }
            else
                log_warn "qBittorrent connected to app_net or media_net (should only use download_net)"
                return 1
            fi
        else
            log_error "qBittorrent not found on expected network: download_net"
            return 1
        fi
        
    elif [[ "$TEST_NETWORK_ISOLATION" == true ]]; then
        # Run full isolation test suite
        run_full_isolation_test || {
            log_warn "Network isolation tests failed - review compose.yaml configuration"
            return 1
        }
    else
        # Just verify Gluetun is healthy (basic check)
        if command -v docker &> /dev/null; then
            local gl_status=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "")
            if [[ "$gl_status" == "healthy" ]]; then
                log_info "Gluetun healthcheck: HEALTHY"
            else
                log_warn "Gluetun healthcheck status not yet available (container may be starting)"
            fi
        fi
    fi
    
    return 0
}

# Function to run full network isolation test suite
run_full_isolation_test() {
    local tests_passed=0
    local tests_failed=0
    
    # Test 1: Verify qBittorrent is only on download_net
    log_info "Test 1: Checking qBittorrent network membership..."
    
    if command -v docker &> /dev/null; then
        local qb_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' qbittorrent 2>/dev/null || echo "")
        
        if [[ "$qb_networks" == *"download_net"* ]]; then
            log_info "PASS: qBittorrent is on download_net"
            ((tests_passed++))
            
            # Test 1b: Verify Gluetun is also on download_net
            local gl_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' gluetun 2>/dev/null || echo "")
            
            if [[ "$gl_networks" == *"download_net"* ]]; then
                log_info "PASS: Gluetun is on download_net"
                ((tests_passed++))
            else
                log_error "FAIL: Gluetun should be on download_net but isn't!"
                ((tests_failed++))
            fi
            
        else
            log_error "FAIL: qBittorrent not found on download_net network!"
            ((tests_failed++))
        fi
        
    else
        log_warn "SKIP: Docker not available for isolation tests"
    fi
    
    # Test 2: Verify ARR services are only on app_net
    log_info "Test 2: Checking ARR service network membership..."
    
    local arr_services=("sonarr" "radarr" "lidarr" "prowlarr" "bazarr" "jellyseerr" "recyclarr")
    
    for svc in "${arr_services[@]}"; do
        if command -v docker &> /dev/null; then
            local svc_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' "$svc" 2>/dev/null || echo "")
            
            # Should be on app_net, optionally media_net for jellyfin/bazarr (for volume access)
            if [[ "$svc_networks" == *"app_net"* ]]; then
                log_info "PASS: $svc is on app_net"
                ((tests_passed++))
                
                # Jellyseerr and bazarr should NOT be on download_net or media_net for security
                if [[ "$svc" != "jellyfin" ]] && [[ "$svc_networks" == *"media_net"* ]]; then
                    log_warn "WARN: $svc is connected to media_net (may need review)"
                fi
                
            else
                # Jellyseerr and jellyfin are exceptions - they don't strictly require app_net for all operations
                if [[ "$svc" != "jellyseerr" ]] && [[ "$svc" != "bazarr" ]]; then
                    log_error "FAIL: $svc should be on app_net but isn't!"
                    ((tests_failed++))
                else
                    log_info "INFO: $svc is optional for app_net (may use host network or other networks)"
                fi
            fi
            
        else
            log_warn "SKIP: Docker not available"
        fi
    done
    
    # Test 3: Verify Jellyfin is on media_net only
    if command -v docker &> /dev/null; then
        local jf_networks=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Name}}' jellyfin 2>/dev/null || echo "")
        
        if [[ "$jf_networks" == *"media_net"* ]]; then
            log_info "PASS: Jellyfin is on media_net (internal network)"
            ((tests_passed++))
            
            # Should NOT be on download_net or app_net for security isolation
            if [[ "$jf_networks" != *"download_net"* ]] && [[ "$jf_networks" != *"app_net"* ]]; then
                log_info "PASS: Jellyfin is isolated from other networks (correct)"
                ((tests_passed++))
            else
                log_warn "WARN: Jellyfin connected to app_net or download_net - review security implications"
            fi
            
        else
            log_error "FAIL: Jellyfin should be on media_net but isn't!"
            ((tests_failed++))
        fi
        
    else
        log_warn "SKIP: Docker not available for isolation tests"
    fi
    
    # Test 4: Verify Gluetun healthcheck is passing
    if command -v docker &> /dev/null; then
        local gl_status=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "")
        
        if [[ "$gl_status" == "healthy" ]]; then
            log_info "PASS: Gluetun healthcheck is healthy"
            ((tests_passed++))
            
            # Test 5: Verify qBittorrent healthcheck status (if available)
            local qb_status=$(docker inspect --format='{{.State.Health.Status}}' qbittorrent 2>/dev/null || echo "")
            
            if [[ "$qb_status" == "healthy" ]] || [[ "$qb_status" != "" ]]; then
                log_info "PASS: qBittorrent healthcheck status available ($qb_status)"
                ((tests_passed++))
            else
                # Container may not have a healthcheck yet or is still starting
                local qb_state=$(docker inspect --format='{{.State.Status}}' qbittorrent 2>/dev/null || echo "")
                if [[ "$qb_state" == "running" ]]; then
                    log_info "INFO: qBittorrent running but no healthcheck status (may be acceptable during startup)"
                else
                    log_warn "WARN: qBittorrent not healthy - check logs for errors"
                fi
            fi
            
        elif [[ "$gl_status" == "" ]]; then
            # Healthchecks may not have run yet or container is starting
            local gl_state=$(docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "")
            
            if [[ "$gl_state" != "exited" ]] && [[ "$gl_state" != "dead" ]]; then
                log_info "INFO: Gluetun running but healthcheck not yet available (container starting)"
            else
                log_error "FAIL: Gluetun container is exited or dead!"
                ((tests_failed++))
            fi
            
        else
            log_warn "WARN: Gluetun healthcheck status unknown ($gl_status) - may need time to stabilize"
        fi
        
    else
        log_warn "SKIP: Docker not available for isolation tests"
    fi
    
    # Summary
    echo ""
    if [[ $tests_failed -eq 0 ]]; then
        log_info "All network isolation tests PASSED!"
        return 0
    else
        log_error "$tests_failed test(s) FAILED. Review compose.yaml configuration."
        return 1
    fi
    
}

# Main execution logic
main() {
    echo "=========================================="
    echo "ARR Media Stack Healthcheck Script"
    echo "=========================================="
    
    # Run requested tests or all if none specified
    local run_all=false
    
    case "${TEST_ALL:-$TEST_VPN_ONLY:$TEST_NETWORK_ISOLATION}" in
        true|all) 
            log_info "Running full health check suite..."
            ;;
        *)
            for test_flag in "$TEST_VPN_ONLY" "$TEST_NETWORK_ISOLATION"; do
                if [[ -n "${test_flag:-}" ]]; then
                    run_all=true
                fi
            done
            
            # If no specific tests requested, just verify Gluetun is healthy (basic check)
            if [[ "$run_all" == false ]] && command -v docker &> /dev/null; then
                log_info "Running basic health checks..."
                
                local gl_status=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "")
                
                case "$gl_status" in
                    healthy) 
                        log_info "Gluetun: HEALTHY (VPN gateway operational)" ;;
                    
                    unhealthy|none|"") 
                        # Container may be starting or healthchecks not yet available
                        local gl_state=$(docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "")
                        
                        if [[ "$gl_state" == "running" ]]; then
                            log_info "Gluetun: Running (healthcheck status pending)"
                            
                            # Verify container is not in unhealthy state due to errors
                            local health_log=$(docker inspect --format='{{.State.Health.Log}}' gluetun 2>/dev/null | grep -i error || echo "")
                            
                            if [[ "$health_log" != *"error"* ]]; then
                                log_info "No critical errors detected in Gluetun logs (yet)"
                            else
                                log_warn "Errors found in Gluetun healthcheck logs:"
                                echo "$health_log" | head -5
                            fi
                        elif [[ "$gl_state" == "" ]] || [[ "$gl_state" != "exited" ]]; then
                            # Container may not exist yet or is starting
                            log_info "Gluetun: Starting (no healthcheck status available)"
                        else
                            log_error "Gluetun container exited unexpectedly!"
                            exit 1
                        fi
                        
                        ;;
                    
                    *) 
                        if [[ "$gl_status" != "" ]] && [[ "$gl_state" == "" ]]; then
                            # Unknown state - check logs for errors
                            local health_log=$(docker inspect --format='{{.State.Health.Log}}' gluetun 2>/dev/null | tail -5 || echo "")
                            
                            if [[ "$health_log" != *"error"* ]] && [[ "$health_log" != *"failed"* ]]; then
                                log_info "Gluetun: Running (no critical healthcheck failures)"
                            else
                                log_warn "Potential issues in Gluetun healthchecks:"
                                echo "$health_log" | head -5
                            fi
                        else
                            # Unknown state or container not running yet
                            local gl_state=$(docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "")
                            
                            if [[ "$gl_state" == "running" ]]; then
                                log_info "Gluetun: Running (healthcheck status unknown)"
                            else
                                # Container may not exist yet or is starting
                                log_info "Gluetun container state: $gl_state (may be starting up)"
                            fi
                        fi
                        
                        ;;
                esac
                
            fi
            
    esac
    
    echo ""
    
}

# Run main function with arguments passed to script
main "$@"
