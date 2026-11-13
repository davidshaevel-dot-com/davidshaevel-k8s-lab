# Kubernetes lab. Every target is a thin wrapper over scripts/; see README.md.
SHELL := /bin/bash
SCENARIO ?=

.PHONY: help up down kind-up kind-down deploy plant reveal heal status test check

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

up: ## Create the AKS lab cluster (terraform apply) and fetch Entra ID credentials
	@scripts/up.sh

down: ## Destroy the AKS lab cluster (terraform destroy)
	@scripts/down.sh

kind-up: ## Create the local kind cluster
	@scripts/kind-up.sh

kind-down: ## Delete the local kind cluster
	@scripts/kind-down.sh

deploy: ## Build the app image and deploy the app to the current lab cluster
	@scripts/deploy.sh

plant: ## Plant a random fault: make plant SCENARIO=2 (or 3)
	@scripts/plant.sh "$(SCENARIO)"

reveal: ## Show which fault is planted
	@scripts/reveal.sh

heal: ## Undo the planted fault and restore the healthy state
	@scripts/heal.sh

status: ## Check the app end to end
	@scripts/status.sh

test: ## Run the tests that need no cluster
	@test -x .venv/bin/pytest || (python3 -m venv .venv && .venv/bin/pip install -q -r app/requirements-dev.txt)
	@cd app && ../.venv/bin/pytest -q
	@bash tests/test_faults.sh

check: test ## test + terraform fmt/validate
	@terraform -chdir=terraform fmt -check -recursive
	@terraform -chdir=terraform init -backend=false -input=false >/dev/null
	@terraform -chdir=terraform validate
