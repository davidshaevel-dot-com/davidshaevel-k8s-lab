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
# is installed on your PATH. The binaries it downloads (kube-apiserver, etcd, kubectl)
# go to bin/k8s/k8s/<version>-<os>-<arch>/ (gitignored).
SETUP_ENVTEST := go run sigs.k8s.io/controller-runtime/tools/setup-envtest@$(ENVTEST_VERSION)
ENVTEST_ASSETS := $(SETUP_ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir "$(BIN_DIR)/k8s" -p path
# Matches the command line of a process started from those binaries. The [k] keeps the
# pattern from matching the shell that runs pgrep or pkill with it.
ENVTEST_PROCESS_PATTERN := $(BIN_DIR)/k8s/[k]8s/

.PHONY: help build vet envtest test-smoke test-contract test-contract-optional run stop-envtest clean

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-24s %s\n", $$1, $$2}'

build: ## Compile the controller to bin/namespace-guardrails
	go build -o "$(BIN_DIR)/namespace-guardrails" .

vet: ## go vet, both contract groups included
	go vet -tags "contract contract_optional" ./...

envtest: ## Download the pinned envtest binaries under bin/k8s/ and print their path
	@$(ENVTEST_ASSETS)

test-smoke: ## Smoke tests: pass on the scaffold
	@assets=$$($(ENVTEST_ASSETS)) && \
	  KUBEBUILDER_ASSETS="$$assets" go test -count=1 -v -run '^TestSmoke' ./...

test-contract: ## Core contract tests: fail until the reconcile logic exists; green = done
	@assets=$$($(ENVTEST_ASSETS)) && \
	  KUBEBUILDER_ASSETS="$$assets" go test -tags contract -count=1 -v -run '^TestContract' ./...

test-contract-optional: ## Optional contract tests: hand-edited guardrails are restored
	@assets=$$($(ENVTEST_ASSETS)) && \
	  KUBEBUILDER_ASSETS="$$assets" go test -tags "contract contract_optional" -count=1 -v -run '^TestOptional' ./...

# The context check lives here only: `go run .` and the built binary use the current
# context without asking, and a KUBE_CONTEXT exported in the shell satisfies it.
run: ## Run the controller against your current kube context: make run KUBE_CONTEXT=<name>
	@current=$$(kubectl config current-context 2>/dev/null); \
	if [ -z "$(KUBE_CONTEXT)" ] || [ "$(KUBE_CONTEXT)" != "$$current" ]; then \
	  echo "make run changes every namespace in the cluster of your current kube context."; \
	  echo "Current context: $${current:-none}"; \
	  echo "If that is the cluster you mean (a local kind cluster, not a shared one), name it:"; \
	  echo "  make run KUBE_CONTEXT=<current context>"; \
	  exit 1; \
	fi; \
	go run .

stop-envtest: ## Stop etcd and kube-apiserver left running by a test run that was killed
	@if ! pgrep -f "$(ENVTEST_PROCESS_PATTERN)" >/dev/null; then \
	  echo "No envtest processes from bin/k8s/ are running."; exit 0; \
	fi; \
	echo "Stopping the envtest processes started from bin/k8s/ (up to 10s)..."; \
	pkill -f "$(ENVTEST_PROCESS_PATTERN)"; \
	for i in $$(seq 10); do pgrep -f "$(ENVTEST_PROCESS_PATTERN)" >/dev/null || break; sleep 1; done; \
	if pgrep -f "$(ENVTEST_PROCESS_PATTERN)" >/dev/null; then \
	  echo "Still running after 10s; killing them."; pkill -KILL -f "$(ENVTEST_PROCESS_PATTERN)"; sleep 1; \
	fi; \
	if pgrep -f "$(ENVTEST_PROCESS_PATTERN)" >/dev/null; then \
	  echo "Could not stop:"; pgrep -fl "$(ENVTEST_PROCESS_PATTERN)"; exit 1; \
	fi; \
	echo "Stopped."

clean: stop-envtest ## Stop leftover envtest processes, then remove bin/
	@if [ -d "$(BIN_DIR)" ]; then chmod -R u+w "$(BIN_DIR)" && rm -rf "$(BIN_DIR)"; fi
