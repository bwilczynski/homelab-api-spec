# Makefile for homelab-api-spec
#
# Requires: node (npx), docker. No global installs; every tool runs
# via `npx` so CI and local match. Pinned versions keep output stable.

SPECTRAL_VERSION ?= 6.15.0
REDOCLY_VERSION  ?= 1.25.15
OASDIFF_VERSION  ?= v1.11.7

SPEC        := openapi/openapi.yaml
BUNDLE_DIR  := dist
BUNDLE_YAML := $(BUNDLE_DIR)/openapi.bundled.yaml
BUNDLE_JSON := $(BUNDLE_DIR)/openapi.bundled.json
DOCS_HTML   := $(BUNDLE_DIR)/index.html

DOCKER_IMAGE ?= homelab-api-docs
DOCKER_TAG   ?= dev

.PHONY: help lint lint-spectral lint-spectral-bundled lint-redocly bundle \
        build preview docs-image breaking clean

help:
	@echo "Targets:"
	@echo "  lint          Run spectral + redocly lint (source and bundled)"
	@echo "  bundle        Produce $(BUNDLE_YAML) and $(BUNDLE_JSON)"
	@echo "  build         Build static docs site at $(DOCS_HTML)"
	@echo "  preview       Live-reload docs preview on http://localhost:8080"
	@echo "  docs-image    Build docs container image ($(DOCKER_IMAGE):$(DOCKER_TAG))"
	@echo "  breaking BASE=<ref>  Run oasdiff breaking-change check against BASE"
	@echo "  clean         Remove $(BUNDLE_DIR)"

# `lint` runs the source-level check first (fast feedback) and then a
# second pass over the bundled file. Some Spectral rules (notably
# `oas3-operation-security-defined`) can't follow external `$ref`s to
# security schemes and only resolve correctly after bundling.
lint: lint-spectral lint-redocly lint-spectral-bundled

lint-spectral:
	npx --yes @stoplight/spectral-cli@$(SPECTRAL_VERSION) lint $(SPEC)

lint-spectral-bundled: bundle
	npx --yes @stoplight/spectral-cli@$(SPECTRAL_VERSION) lint $(BUNDLE_YAML)

lint-redocly:
	npx --yes @redocly/cli@$(REDOCLY_VERSION) lint $(SPEC)

$(BUNDLE_DIR):
	mkdir -p $(BUNDLE_DIR)

bundle: $(BUNDLE_DIR)
	npx --yes @redocly/cli@$(REDOCLY_VERSION) bundle $(SPEC) -o $(BUNDLE_YAML)
	npx --yes @redocly/cli@$(REDOCLY_VERSION) bundle $(SPEC) -o $(BUNDLE_JSON)

build: $(BUNDLE_DIR)
	npx --yes @redocly/cli@$(REDOCLY_VERSION) build-docs $(SPEC) -o $(DOCS_HTML)

preview:
	npx --yes @redocly/cli@$(REDOCLY_VERSION) preview-docs $(SPEC) --port 8080

docs-image:
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

# Breaking-change detection against a git ref. Usage:
#   make breaking BASE=origin/main
BASE ?= origin/main
breaking: bundle
	@echo "Comparing bundled spec against $(BASE)..."
	@git show $(BASE):$(SPEC) > $(BUNDLE_DIR)/base.yaml 2>/dev/null || \
	  (echo "Could not read $(SPEC) from $(BASE); skipping." && exit 0)
	docker run --rm -v $(PWD)/$(BUNDLE_DIR):/specs tufin/oasdiff:$(OASDIFF_VERSION) \
	  breaking /specs/base.yaml /specs/openapi.bundled.yaml

clean:
	rm -rf $(BUNDLE_DIR)
