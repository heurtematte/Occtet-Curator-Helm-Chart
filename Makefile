# Makefile for Occtet Curator Helm Chart

.PHONY: help install upgrade uninstall lint test template clean namespace check-helm list logs port-forward deps secrets
.PHONY: secrets-check secrets-view secrets-get secrets-delete secrets-backup
.PHONY: upgrade-nowait watch-pods pods-status pods-not-ready describe-pods
.PHONY: logs-frontend logs-backend logs-postgresql logs-nats logs-vulnerability

# Ensure we use bash for commands that need it
SHELL := /bin/bash

# Variables
CHART_NAME := occtet-curator
RELEASE_NAME := occtet-curator
NAMESPACE := curator
CHART_PATH := ./occtet-curator
VALUES_FILE := values.yaml

# Secret names
SECRET_NAME := occtet-curator-secrets

# Colors for output
GREEN := $(shell printf '\033[0;32m')
YELLOW := $(shell printf '\033[1;33m')
RED := $(shell printf '\033[0;31m')
NC := $(shell printf '\033[0m')

help: ## Display help
	@echo "$(GREEN)Occtet Curator Helm Chart - Available commands:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

check-helm: ## Check if Helm is installed
	@which helm > /dev/null || (echo "$(RED)Helm is not installed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Helm is installed (version: $$(helm version --short))$(NC)"

namespace: check-helm ## Create the namespace
	@kubectl get namespace $(NAMESPACE) > /dev/null 2>&1 || kubectl create namespace $(NAMESPACE)
	@kubectl label namespace $(NAMESPACE) app.kubernetes.io/managed-by=Helm --overwrite > /dev/null 2>&1 || true
	@kubectl annotate namespace $(NAMESPACE) meta.helm.sh/release-name=$(RELEASE_NAME) meta.helm.sh/release-namespace=$(NAMESPACE) --overwrite > /dev/null 2>&1 || true
	@echo "$(GREEN)✓ Namespace $(NAMESPACE) is ready$(NC)"

secrets-check: ## Check the unified secret (database + frontend credentials)
	@echo "$(YELLOW)Checking secrets...$(NC)"
	@if kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) > /dev/null 2>&1; then \
		echo "$(GREEN)✓ $(SECRET_NAME)$(NC)"; \
		kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data}' | jq -r 'keys[]' | sed 's/^/  - /'; \
	else \
		echo "$(RED)✗ $(SECRET_NAME) not found$(NC)"; \
		echo "$(YELLOW)Run 'make secrets-create' to create it$(NC)"; \
		exit 1; \
	fi

secrets-view: ## Display secret keys (not values)
	@kubectl describe secret $(SECRET_NAME) -n $(NAMESPACE) 2>/dev/null || echo "$(RED)Secret $(SECRET_NAME) not found$(NC)"

secrets-get: ## Get all secret values (CAUTION: displays passwords)
	@echo "$(RED)⚠ WARNING: This will display passwords in clear text!$(NC)"
	@echo "$(YELLOW)=== $(SECRET_NAME) ===$(NC)"
	@echo "  DB User:            $$(kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo 'N/A')"
	@echo "  DB Password:        $$(kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.postgres-password}' | base64 -d 2>/dev/null || echo 'N/A')"
	@echo "  Database:           $$(kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.database}' | base64 -d 2>/dev/null || echo 'N/A')"
	@echo "  ORT Username:       $$(kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.ort-username}' | base64 -d 2>/dev/null || echo 'N/A')"
	@echo "  ORT Password:       $$(kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.ort-password}' | base64 -d 2>/dev/null || echo 'N/A')"
	@echo "  Keycloak Client ID: $$(kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.keycloak-client-id}' | base64 -d 2>/dev/null || echo 'N/A')"
	@echo "  Keycloak Secret:    $$(kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.keycloak-client-secret}' | base64 -d 2>/dev/null || echo 'N/A')"

secrets-delete: ## Delete the unified secret
	@echo "$(RED)⚠ WARNING: This will delete all secrets!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		kubectl delete secret $(SECRET_NAME) -n $(NAMESPACE) 2>/dev/null && echo "$(GREEN)✓ $(SECRET_NAME) deleted$(NC)" || echo "$(YELLOW)  $(SECRET_NAME) not found$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

secrets-backup: ## Backup the unified secret to file (CAUTION: contains passwords in base64)
	@echo "$(RED)⚠ WARNING: This file will contain passwords in base64!$(NC)"
	@kubectl get secret $(SECRET_NAME) -n $(NAMESPACE) -o yaml > secrets-backup.yaml 2>/dev/null || echo "$(YELLOW)  $(SECRET_NAME) not found$(NC)"
	@echo "$(GREEN)✓ Backup created: secrets-backup.yaml$(NC)"
	@echo "$(YELLOW)Keep this file secure! It is already in .gitignore$(NC)"

deps: check-helm ## Install Helm dependencies (PostgreSQL, etc.)
	@echo "$(YELLOW)Installing Helm dependencies (OCI)...$(NC)"
	@helm dependency update $(CHART_PATH)
	@echo "$(GREEN)✓ Dependencies installed successfully$(NC)"

deps-list: check-helm ## List current dependencies
	@echo "$(YELLOW)=== Chart Dependencies ===$(NC)"
	@helm dependency list $(CHART_PATH)

deps-update: check-helm ## Update dependencies to latest versions
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	@helm dependency update $(CHART_PATH) --skip-refresh
	@echo "$(GREEN)✓ Dependencies updated$(NC)"
	@$(MAKE) deps-list

lint: check-helm ## Validate the Helm chart
	@echo "$(YELLOW)Validating chart...$(NC)"
	@helm lint $(CHART_PATH)
	@echo "$(GREEN)✓ Chart validated successfully$(NC)"

template: check-helm ## Generate manifests without installing
	@echo "$(YELLOW)Generating manifests...$(NC)"
	@helm template $(RELEASE_NAME) $(CHART_PATH) --namespace $(NAMESPACE)

template-debug: check-helm ## Generate manifests with debug
	@echo "$(YELLOW)Generating manifests in debug mode...$(NC)"
	@helm template $(RELEASE_NAME) $(CHART_PATH) --namespace $(NAMESPACE) --debug

dry-run: check-helm namespace ## Installation simulation
	@echo "$(YELLOW)Simulating installation...$(NC)"
	@helm install $(RELEASE_NAME) $(CHART_PATH) \
		--namespace $(NAMESPACE) \
		--dry-run --debug

install: check-helm namespace deps lint ## Install the chart
	@echo "$(YELLOW)Installing chart $(CHART_NAME)...$(NC)"
	@helm install $(RELEASE_NAME) $(CHART_PATH) \
		--namespace $(NAMESPACE) \
		--wait \
		--timeout 20m
	@echo "$(GREEN)✓ Chart installed successfully$(NC)"
	@echo "$(YELLOW)=== Deployment Status ===$(NC)"
	@helm status $(RELEASE_NAME) -n $(NAMESPACE) 2>/dev/null || echo "$(RED)Chart not installed$(NC)"

install-custom: check-helm namespace ## Install with custom values file (usage: make install-custom VALUES=custom-values.yaml)
	@if [ -z "$(VALUES)" ]; then \
		echo "$(RED)Error: Specify VALUES=your-file.yaml$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Installing with $(VALUES)...$(NC)"
	@helm install $(RELEASE_NAME) $(CHART_PATH) \
		--namespace $(NAMESPACE) \
		--values $(VALUES) \
		--wait \
		--timeout 20m
	@echo "$(GREEN)✓ Chart installed successfully$(NC)"

upgrade: check-helm ## Upgrade the chart (or install if not present)
	@echo "$(YELLOW)Upgrading chart...$(NC)"
	@helm upgrade $(RELEASE_NAME) $(CHART_PATH) \
		--install \
		--namespace $(NAMESPACE) \
		--values $(VALUES_FILE)
	@echo "$(GREEN)✓ Chart upgraded successfully$(NC)"
	@echo "$(YELLOW)=== Deployment Status ===$(NC)"
	@helm status $(RELEASE_NAME) -n $(NAMESPACE) 2>/dev/null || echo "$(RED)Chart not installed$(NC)"


rollback: check-helm ## Rollback to previous release version
	@echo "$(YELLOW)Rolling back to previous version...$(NC)"
	@helm rollback $(RELEASE_NAME) -n $(NAMESPACE)
	@echo "$(GREEN)✓ Rollback completed$(NC)"
	@helm status $(RELEASE_NAME) -n $(NAMESPACE)

rollback-version: check-helm ## Rollback to specific version (usage: make rollback-version VERSION=3)
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)Error: Specify VERSION=number$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Rolling back to version $(VERSION)...$(NC)"
	@helm rollback $(RELEASE_NAME) $(VERSION) -n $(NAMESPACE)
	@echo "$(GREEN)✓ Rollback to version $(VERSION) completed$(NC)"

history: check-helm ## Display release history
	@echo "$(YELLOW)=== Release History ===$(NC)"
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)

uninstall: check-helm ## Uninstall the chart
	@echo "$(YELLOW)Uninstalling chart...$(NC)"
	@helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)
	@echo "$(GREEN)✓ Chart uninstalled successfully$(NC)"
	@echo "$(YELLOW)Note: PVCs and secrets are not automatically deleted$(NC)"
	@echo "To delete PVCs: make clean-pvcs"
	@echo "To delete secrets: make secrets-delete"

clean-all: uninstall clean-pvcs secrets-delete ## Uninstall and delete all data and secrets
	@echo "$(GREEN)✓ Complete cleanup done$(NC)"

status: ## Display deployment status
	@echo "$(YELLOW)=== Deployment Status ===$(NC)"
	@helm status $(RELEASE_NAME) -n $(NAMESPACE) 2>/dev/null || echo "$(RED)Chart not installed$(NC)"

list: check-helm ## List Helm releases
	@echo "$(YELLOW)=== Helm Releases ===$(NC)"
	@helm list -n $(NAMESPACE)

list-all: check-helm ## List all Helm releases
	@echo "$(YELLOW)=== All Helm Releases ===$(NC)"
	@helm list --all-namespaces

pods: ## Display all pods
	@echo "$(YELLOW)=== Pods in namespace $(NAMESPACE) ===$(NC)"
	@kubectl get pods -n $(NAMESPACE) -o wide

watch-pods: ## Watch pods in real-time
	@echo "$(YELLOW)Watching pods in $(NAMESPACE) (Ctrl+C to exit)...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -w

pods-status: ## Display detailed pod status with restarts
	@echo "$(YELLOW)=== Detailed Pod Status ===$(NC)"
	@kubectl get pods -n $(NAMESPACE) -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
READY:.status.conditions[?(@.type==\"Ready\")].status,\
RESTARTS:.status.containerStatuses[0].restartCount,\
AGE:.metadata.creationTimestamp

pods-not-ready: ## Show only pods that are not ready
	@echo "$(YELLOW)=== Pods Not Ready ===$(NC)"
	@kubectl get pods -n $(NAMESPACE) --field-selector=status.phase!=Running,status.phase!=Succeeded

describe-pods: ## Describe all pods (useful for debugging)
	@echo "$(YELLOW)=== Describing all pods ===$(NC)"
	@kubectl describe pods -n $(NAMESPACE)

logs-frontend: ## Get frontend logs
	@echo "$(YELLOW)=== Frontend Logs ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/component=frontend --tail=100

logs-backend: ## Get backend services logs (all)
	@echo "$(YELLOW)=== Backend Services Logs ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/component=backend --tail=50 --prefix=true

logs-postgresql: ## Get PostgreSQL logs
	@echo "$(YELLOW)=== PostgreSQL Logs ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=postgresql --tail=100

logs-nats: ## Get NATS logs
	@echo "$(YELLOW)=== NATS Logs ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/component=nats --tail=100

services: ## Display all services
	@echo "$(YELLOW)=== Services in namespace $(NAMESPACE) ===$(NC)"
	@kubectl get svc -n $(NAMESPACE) -o wide

pvcs: ## Display all PVCs
	@echo "$(YELLOW)=== PVCs in namespace $(NAMESPACE) ===$(NC)"
	@kubectl get pvc -n $(NAMESPACE)

all-resources: ## Display all resources
	@echo "$(YELLOW)=== All resources in namespace $(NAMESPACE) ===$(NC)"
	@kubectl get all,pvc,cm,secret -n $(NAMESPACE)

clean-pvcs: ## Delete all PVCs
	@echo "$(RED)⚠ WARNING: This will delete all persistent data!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		kubectl delete pvc -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME); \
		echo "$(GREEN)✓ PVCs deleted$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

describe-frontend: ## Describe frontend pod
	@kubectl describe pod -n $(NAMESPACE) -l app.kubernetes.io/component=frontend

describe-postgresql: ## Describe PostgreSQL pod
	@kubectl describe pod -n $(NAMESPACE) -l app.kubernetes.io/name=postgresql

logs-vulnerability: ## Display vulnerability service logs
	@echo "$(YELLOW)=== Vulnerability Service Logs ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/service=vulnerability-service --tail=100 -f

port-forward-frontend: ## Port-forward to frontend (localhost:8090)
	@echo "$(GREEN)Port-forwarding frontend to http://localhost:8090$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-frontend 8090:8090

port-forward-postgresql: ## Port-forward to PostgreSQL (localhost:5432)
	@echo "$(GREEN)Port-forwarding PostgreSQL to localhost:5432$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-postgresql 5432:5432

port-forward-nats: ## Port-forward to NATS (localhost:4222)
	@echo "$(GREEN)Port-forwarding NATS to localhost:4222$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-nats 4222:4222

shell-frontend: ## Open a shell in the frontend pod
	@kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/component=frontend -o jsonpath='{.items[0].metadata.name}') -- /bin/bash

shell-postgresql: ## Open a psql shell in PostgreSQL
	@kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}') -- psql -U occtetuser -d occtet_boc

restart-frontend: ## Restart the frontend
	@echo "$(YELLOW)Restarting frontend...$(NC)"
	@kubectl rollout restart deployment -n $(NAMESPACE) $(RELEASE_NAME)-frontend
	@kubectl rollout status deployment -n $(NAMESPACE) $(RELEASE_NAME)-frontend
	@echo "$(GREEN)✓ Frontend restarted$(NC)"

restart-backend: ## Restart all backend services
	@echo "$(YELLOW)Restarting backend services...$(NC)"
	@kubectl rollout restart deployment -n $(NAMESPACE) -l app.kubernetes.io/component=backend
	@echo "$(GREEN)✓ Backend services restarted$(NC)"

restart-all: ## Restart all deployments
	@echo "$(YELLOW)Restarting all deployments...$(NC)"
	@kubectl rollout restart deployment -n $(NAMESPACE)
	@echo "$(GREEN)✓ All deployments restarted$(NC)"

scale-frontend: ## Scale the frontend (usage: make scale-frontend REPLICAS=3)
	@if [ -z "$(REPLICAS)" ]; then \
		echo "$(RED)Error: Specify REPLICAS=number$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Scaling frontend to $(REPLICAS) replicas...$(NC)"
	@kubectl scale deployment -n $(NAMESPACE) $(RELEASE_NAME)-frontend --replicas=$(REPLICAS)
	@echo "$(GREEN)✓ Frontend scaled$(NC)"

watch: ## Watch pods in real-time
	@watch -n 2 kubectl get pods -n $(NAMESPACE)

events: ## Display recent events
	@echo "$(YELLOW)=== Recent Events ===$(NC)"
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | tail -20

test: lint template ## Test the chart
	@echo "$(YELLOW)Testing chart...$(NC)"
	@helm template $(RELEASE_NAME) $(CHART_PATH) --namespace $(NAMESPACE) > /dev/null
	@echo "$(GREEN)✓ Tests passed$(NC)"

package: check-helm lint ## Package the chart
	@echo "$(YELLOW)Packaging chart...$(NC)"
	@helm package $(CHART_PATH)
	@echo "$(GREEN)✓ Chart packaged$(NC)"

values: ## Display default values
	@cat $(VALUES_FILE)

info: ## Display chart information
	@echo "$(YELLOW)=== Chart Information ===$(NC)"
	@helm show chart $(CHART_PATH)

clean: ## Clean temporary files
	@echo "$(YELLOW)Cleaning temporary files...$(NC)"
	@rm -f *.tgz
	@echo "$(GREEN)✓ Cleanup done$(NC)"

.DEFAULT_GOAL := help
