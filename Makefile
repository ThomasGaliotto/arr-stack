# ARR Media Stack - Build and Deployment Targets
# =============================================================================
# Usage: make <target> [OPTIONS]
# Examples:
#   make deploy              # Deploy the stack with current .env settings
#   make backup              # Create configuration backup  
#   make test-all            # Run all automated tests
#   make status              # Check container health status

.PHONY: help deploy stop reboot clean config validate env-check secrets-status \
        backup verify-backup restore status logs test smoke network security integration \
        dev test deployment verification final-review docs generate-configs

SHELL := /bin/bash

# =============================================================================
# DEFAULT TARGETS
# =============================================================================

help: ## Show this help message
	@echo "ARR Media Stack - Available Targets:"
	@echo ""
	@grep -E '^[a-zA-Z][^#:]+?:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

deploy: validate env-check config ## Deploy the stack
	@echo "[DEPLOY] Starting ARR Media Stack..."
	docker compose up -d --wait
	@./scripts/healthcheck.sh --all-services || (echo "[ERROR] Healthchecks failed" && exit 1)
	@echo "[SUCCESS] Stack deployed successfully!"

stop: ## Stop all containers
	@docker compose down

reboot: stop deploy ## Restart the entire stack (preserves data and configs)
	@echo "[REBOOT] Stopping and restarting stack..."
	docker compose up -d --wait
	@./scripts/healthcheck.sh --all-services || exit 1
	@echo "[SUCCESS] Stack rebooted successfully!"

clean: stop ## Stop containers without removing volumes (use clean-volumes to remove data)
	@docker compose down

clean-volumes: stop ## Remove all volumes and restart from scratch (WARNING: destroys media!)
	docker compose down -v --rmi local
	docker compose up -d --wait
	@echo "[SUCCESS] Stack restarted with fresh volumes!"

config: ## Validate Docker Compose configuration syntax
	@docker compose config || exit 1
	@echo "[CONFIG] Configuration is valid"

validate: config ## Full validation including environment variables and secrets check
	@./scripts/bootstrap.sh --dry-run || (echo "[ERROR] Validation failed" && exit 1)
	docker compose config | grep -q "secrets:" || echo "[WARN] No Docker secrets configured yet"
	@echo "[VALIDATE] All checks passed!"

env-check: ## Check if .env file exists and has required variables
ifeq ($(wildcard ./.env),)
	@echo "[ERROR] Missing .env file. Copy from .env.example first:"
	@cp .env.example .env && echo "Created .env - edit with your values"
else
	@grep -E "^VPN_|^HOST_UID|^HOST_GID|^(ENABLE_)" ./.env > /dev/null || \
		echo "[WARN] Some environment variables may be missing. Review .env file."
endif

secrets-status: ## Show status of secrets (should only show placeholders)
ifeq ($(wildcard secrets/gluetun.key),)
	@echo "[OK] No secret files in repository"
else
	@grep -l "password\|key\|secret\|token" secrets/* 2>/dev/null | head -1 || \
		echo "[WARN] Check that no sensitive data was committed to Git!"
endif

# =============================================================================
# BACKUP TARGETS  
# =============================================================================

backup: ## Create configuration backup with checksums
ifeq ($(wildcard backups),)
	mkdir -p backups
endif
	@./scripts/backup.sh || exit 1

verify-backup: ## Verify integrity of latest backup
ifeq ($(wildcard backups/*.sha256),)
	@echo "[WARN] No backups found to verify"
else
	cd backups && sha256sum -c *.sha256 || (echo "[ERROR] Backup verification failed!" && exit 1)
endif

restore: ## Restore from backup file
ifeq ($(BACKUP_FILE),)
	@echo "[ERROR] BACKUP_FILE not specified. Usage: make restore BACKUP_FILE=/path/to/backup.tar.gz"
else
	@if [ ! -f "$(BACKUP_FILE)" ]; then \
		echo "[ERROR] Backup file not found: $(BACKUP_FILE)"; exit 1; \
	fi
	docker compose down || true
	@./scripts/restore.sh $(BACKUP_FILE) /srv/media-stack/config || (echo "[ERROR] Restore failed" && exit 1)
	docker compose up -d --wait
endif

# =============================================================================
# TESTING TARGETS  
# =============================================================================

test: ## Run all tests
	test-smoke test-network test-security test-integration

smoke: ## Smoke tests - basic container startup checks
	@echo "[SMOKE] Running smoke tests..."
	docker compose up -d --wait || (echo "[ERROR] Containers failed to start" && exit 1)
	./scripts/healthcheck.sh --all-services || (echo "[ERROR] Healthchecks failed in smoke test" && make stop && exit 1)
	make stop

network: ## Network isolation tests  
ifeq ($(wildcard .env),)
	@echo "[SKIP] Skipping network tests - no .env file found"
else
	docker compose up -d --wait || (make stop && echo "[ERROR] Containers failed to start for network test")
	./scripts/healthcheck.sh --network-isolation || (make stop && exit 1)
endif

security: ## Security checks  
ifeq ($(wildcard .env),)
	@echo "[SKIP] Skipping security tests - no .env file found"
else
	docker compose up -d --wait || make stop
	./scripts/healthcheck.sh --all-services || (make stop && exit 1)
endif

integration: ## Integration tests  
ifeq ($(wildcard .env),)
	@echo "[SKIP] Skipping integration tests - no .env file found"
else
	docker compose up -d --wait || make stop
	./scripts/healthcheck.sh --all-services || (make stop && exit 1)
endif

test-all: test ## Alias for running all tests

# =============================================================================
# MONITORING TARGETS  
# =============================================================================

status: ## Show container health status
	docker compose ps

logs: service=## Follow logs for specified services or all if no argument
ifeq ($(service),)
	@docker compose logs -f || echo "[ERROR] Failed to show logs"
else
	@docker compose logs -f $(service) || (echo "[ERROR] Service not found" && exit 1)
endif

# =============================================================================
# DEVELOPMENT TARGETS  
# =============================================================================

dev: ## Start development stack with debug settings
	docker compose -f compose.yaml -f compose.dev.yaml up -d --wait
	@./scripts/healthcheck.sh --all-services || (echo "[ERROR] Dev healthchecks failed" && exit 1)

test-dev: dev test-smoke ## Run smoke tests on dev environment

# =============================================================================
# DOCUMENTATION TARGETS  
# =============================================================================

docs: ## Generate or update documentation files
	@mkdir -p docs
ifeq ($(wildcard docs/architecture.md),)
	echo "# Architecture Documentation" > docs/architecture.md
endif
ifeq ($(wildcard docs/networking.md),)
	echo "# Networking Documentation" > docs/networking.md  
endif

generate-configs: ## Generate default configuration files for all services
	@for dir in gluetun qbittorrent sonarr radarr lidarr prowlarr bazarr jellyfin jellyseerr recyclarr; do \
		if [ ! -f "config/$$dir/.gitkeep" ]; then \
			echo "# Configuration for $$dir service (managed by compose.yaml)" > "config/$$dir/.gitkeep"; \
		fi; \
	done

# =============================================================================
# VERIFICATION TARGETS  
# =============================================================================

verification: ## Run verification checks before final review
ifeq ($(wildcard .env),)
	@echo "[SKIP] Verification requires .env file"
else
	docker compose up -d --wait || (make stop && exit 1)
	./scripts/healthcheck.sh --all-services || (make stop && echo "[ERROR] Healthchecks failed in verification")
endif

final-review: ## Run final review checks  
ifeq ($(wildcard .env),)
	@echo "[SKIP] Final review requires .env file"
else
	docker compose up -d --wait || make stop
	./scripts/healthcheck.sh --all-services || (make stop && exit 1)
	@echo "[FINAL-REVIEW] All checks passed!"
endif

# =============================================================================
# UTILITIES  
# =============================================================================

generate-secrets: ## Generate placeholder secrets for testing (DO NOT USE IN PRODUCTION!)
ifeq ($(wildcard .env),)
	@cp .env.example .env && echo "Created .env - edit with your values"
else
	echo "[INFO] Using existing .env file"
endif

# =============================================================================
# DEFAULT TARGET  
# =============================================================================

.DEFAULT_GOAL := help
