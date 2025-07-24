# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

############################################################
# Top‑level helper variables                               #
############################################################

ALL_DOCS := $(shell find . -type f -name '*.md' -not -path './.github/*' -not -path '*/node_modules/*' -not -path '*/_build/*' -not -path '*/deps/*' -not -path */Pods/* -not -path */.expo/* | sort)

TOOLS_DIR            := ./internal/tools
MISSPELL_BINARY      := bin/misspell
MISSPELL             := $(TOOLS_DIR)/$(MISSPELL_BINARY)

DOCKER_COMPOSE_CMD   ?= docker compose

DOCKER_COMPOSE_ENV = \
  --env-file .env \
  --env-file .env.override \
  $(if $(ROUTER),--env-file .env_$(ROUTER))

DOCKER_COMPOSE_BUILD_ARGS=

# Ngrok defaults – override at CLI if you like
NGROK_CONFIG ?= $(HOME)/.config/ngrok/ngrok.yml
NGROK_LOG    ?= $(HOME)/ngrok.log

# Terraform sub‑projects (incident routers)
PROJECT_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# 2. Terraform sub‑projects
TF_DIR_PAGERDUTY := $(PROJECT_ROOT)terraform/pagerduty
TF_DIR_SQUADCAST := $(PROJECT_ROOT)terraform/squadcast

# Java Workaround for macOS 15.2+ and M4 chips
ifeq ($(shell uname -m),arm64)
	ifeq ($(shell uname -s),Darwin)
		DOCKER_COMPOSE_ENV   += --env-file .env.arm64
		DOCKER_COMPOSE_BUILD_ARGS += --build-arg=_JAVA_OPTIONS=-XX:UseSVE=0
	endif
endif

############################################################
# House‑keeping helpers                                    #
############################################################

.PHONY: run-tests run-tracetesting
run-tests:
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) -f docker-compose-tests.yml run frontendTests
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) -f docker-compose-tests.yml run traceBasedTests

run-tracetesting:
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) -f docker-compose-tests.yml run traceBasedTests ${SERVICES_TO_TEST}

############################################################
# Shared shell snippet – export everything from .env files  #
############################################################

define LOAD_ENV
	set -a; \
	[ -f .env ] && . ./.env; \
	[ -f .env.override ] && . .env.override || true; \
	[ -f .env_$(ROUTER) ] && . .env_$(ROUTER) || true; \
	set +a
endef

############################################################
# Core: spin‑up containers + ngrok (no incident router yet) #
############################################################

.PHONY: start-core
start-core:
	@$(LOAD_ENV) && \
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) up --force-recreate --remove-orphans --detach
	@echo "\nOpenTelemetry Demo is running.";
	@echo "  Demo UI  → http://localhost:8080";
	@echo "  Jaeger   → http://localhost:8080/jaeger/ui";
	@echo "  Grafana  → http://localhost:8080/grafana/";
	@echo "  LoadGen  → http://localhost:8080/loadgen/";
	@echo "  Feature  → http://localhost:8080/feature/";
	@echo "\nStarting ngrok tunnels …";
	@nohup ngrok start --config $(NGROK_CONFIG) --all > $(NGROK_LOG) 2>&1 &
	@echo "ngrok running → $(NGROK_LOG)"

# keep original simple target for existing docs/scripts
.PHONY: start
start: start-core


############################################################
############################################################
# Terraform helpers (per incident router)                  #
############################################################

.PHONY: tf-apply-pagerduty tf-apply-squadcast tf-apply-router
tf-apply-router:
	@if [ -z "$(ROUTER)" ]; then \
		echo "ROUTER not set — use ROUTER=pagerduty or squadcast"; \
		exit 1; \
	fi
	@$(LOAD_ENV) && terraform -chdir=$(TF_DIR_CURRENT) init &&  terraform -chdir=$(TF_DIR_CURRENT) apply

.PHONY: tf-destroy-pagerduty tf-destroy-squadcast tf-destroy-router
tf-destroy-router:
	@if [ -z "$(ROUTER)" ]; then \
		echo "ROUTER not set — use ROUTER=pagerduty or squadcast"; \
		exit 1; \
	fi
	@$(LOAD_ENV) && terraform -chdir=$(TF_DIR_CURRENT) init &&  terraform -chdir=$(TF_DIR_CURRENT) destroy

# Router‑specific wrappers

tf-apply-pagerduty: ROUTER = pagerduty
tf-apply-pagerduty: TF_DIR_CURRENT = $(TF_DIR_PAGERDUTY)
tf-apply-pagerduty: tf-apply-router

tf-apply-squadcast: ROUTER = squadcast
tf-apply-squadcast: TF_DIR_CURRENT = $(TF_DIR_SQUADCAST)
tf-apply-squadcast: tf-apply-router


tf-destroy-pagerduty: ROUTER = pagerduty
tf-destroy-pagerduty: TF_DIR_CURRENT = $(TF_DIR_PAGERDUTY)
tf-destroy-pagerduty: tf-destroy-router

tf-destroy-squadcast: ROUTER = squadcast
tf-destroy-squadcast: TF_DIR_CURRENT = $(TF_DIR_SQUADCAST)
tf-destroy-squadcast: tf-destroy-router

############################################################
# High‑level “start & configure” aliases                   # “start & configure” aliases                   #
############################################################

.PHONY: start-pagerduty start-squadcast
start-pagerduty:   ROUTER = pagerduty
start-pagerduty:
	$(MAKE) start-core ROUTER=$(ROUTER)
	$(MAKE) tf-apply-pagerduty ROUTER=$(ROUTER)

start-squadcast:   ROUTER = squadcast
start-squadcast:
	$(MAKE) start-core ROUTER=$(ROUTER)
	$(MAKE) tf-apply-squadcast ROUTER=$(ROUTER)

.PHONY: destroy-pagerduty destroy-squadcast
destroy-pagerduty:   ROUTER = pagerduty
destroy-pagerduty:
	$(MAKE) tf-destroy-pagerduty ROUTER=$(ROUTER)

destroy-squadcast:   ROUTER = squadcast
destroy-squadcast:
	$(MAKE) tf-destroy-squadcast ROUTER=$(ROUTER)

.PHONY: apply-terraform-only_pd pply-terraform-only_sc
apply-terraform-only_pd:  ROUTER = pagerduty
apply-terraform-only_pd: TF_DIR_CURRENT = $(TF_DIR_PAGERDUTY)
apply-terraform-only_pd:
	$(MAKE) tf-apply-router ROUTER=$(ROUTER)

apply-terraform-only_sc:  ROUTER = squadcast
apply-terraform-only_sc: TF_DIR_CURRENT = $(TF_DIR_SQUADCAST)
apply-terraform-only_sc:
	$(MAKE) tf-apply-router ROUTER=$(ROUTER)

############################################################
# Stop / restart helpers                                   #
############################################################

.PHONY: stop
stop:
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) down --remove-orphans --volumes
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) -f docker-compose-tests.yml down --remove-orphans --volumes
	@pkill -f "ngrok start" 2>/dev/null || true
	@echo "\nOpenTelemetry Demo is stopped."

.PHONY: restart redeploy
restart:\nifdef SERVICE
ifdef SERVICE
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) stop $(SERVICE)
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) rm --force $(SERVICE)
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) create $(SERVICE)
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) start $(SERVICE)
else
	@echo "Please provide a service name using SERVICE=<service>"
endif

redeploy:\nifdef SERVICE
ifdef SERVICE
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) build $(DOCKER_COMPOSE_BUILD_ARGS) $(SERVICE)
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) stop $(SERVICE)
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) rm --force $(SERVICE)
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) create $(SERVICE)
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) start $(SERVICE)
else
	@echo "Please provide a service name using SERVICE=<service>"
endif
	

############################################################
# Pytest suites inside the test‑runner container           #
############################################################

define RUN_PYTEST
	$(DOCKER_COMPOSE_CMD) $(DOCKER_COMPOSE_ENV) run --rm \
	-e ROUTER \
	-e PATH_TO_TESTS=/workspace/tests/$$ROUTER \
	test-runner pytest $(1)
endef


# common router‑independent tests
.PHONY: smoke-tests
smoke-tests: start-core
	@$(LOAD_ENV) && \
	$(call RUN_PYTEST,/workspace/tests/smoke)

.PHONY: basic-it
basic-it: start-core
	@$(LOAD_ENV) && \
	$(call RUN_PYTEST,/workspace/tests/$$ROUTER/basic)

.PHONY: advanced-it
advanced-it: start-core
	@$(LOAD_ENV) && \
	$(call RUN_PYTEST,/workspace/tests/$$ROUTER/advanced)
