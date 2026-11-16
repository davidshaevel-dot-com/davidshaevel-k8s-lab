# Namespace guardrails controller (scenario 4). Run every target from this directory.
# The repository's top-level Makefile does not call these, so `make test` and
# `make check` there never need Go.
SHELL := /bin/bash

# setup-envtest, from the controller-runtime release this module uses (Kubernetes 1.36).
ENVTEST_VERSION := v0.24.1
# Kubernetes version of the envtest binaries (kube-apiserver, etcd). The lab cluster
# runs 1.36.5, but no envtest build of 1.36.5 is published; 1.36.2 is the newest 1.36.
ENVTEST_K8S_VERSION := 1.36.2

BIN_DIR := $(CURDIR)/bin
# `go run module@version` builds the tool into Go's module cache and runs it: nothing
# is installed on your PATH. The binaries it downloads go to bin/k8s/ (gitignored).
SETUP_ENVTEST := go run sigs.k8s.io/controller-runtime/tools/setup-envtest@$(ENVTEST_VERSION)
ENVTEST_ASSETS := $(SETUP_ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(BIN_DIR)/k8s -p path

.PHONY: help build vet envtest test-smoke test-contract run clean

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

build: ## Compile the controller to bin/namespace-guardrails
	go build -o $(BIN_DIR)/namespace-guardrails .

vet: ## go vet, contract tests included
	go vet -tags contract ./...

envtest: ## Download the pinned envtest binaries to bin/k8s/ and print their path
	@$(ENVTEST_ASSETS)

test-smoke: ## Smoke tests: pass on the scaffold
	@assets=$$($(ENVTEST_ASSETS)) && \
	  KUBEBUILDER_ASSETS="$$assets" go test -count=1 -v -run '^TestSmoke' ./...

test-contract: ## Contract tests: fail until the reconcile logic exists
	@assets=$$($(ENVTEST_ASSETS)) && \
	  KUBEBUILDER_ASSETS="$$assets" go test -tags contract -count=1 -v -run '^TestContract' ./...

run: ## Run the controller against your current kube context: make run KUBE_CONTEXT=<name>
	@current=$$(kubectl config current-context 2>/dev/null); \
	if [ -z "$(KUBE_CONTEXT)" ] || [ "$(KUBE_CONTEXT)" != "$$current" ]; then \
	  echo "make run changes every namespace in the cluster of your current kube context."; \
	  echo "Name that context to confirm: make run KUBE_CONTEXT=$${current:-<name>}"; \
	  echo "Current context: $${current:-none}"; \
	  exit 1; \
	fi; \
	go run .

clean: ## Remove bin/ (the built controller and the envtest binaries)
	@if [ -d $(BIN_DIR) ]; then chmod -R u+w $(BIN_DIR) && rm -rf $(BIN_DIR); fi
