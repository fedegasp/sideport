APP_NAME      := Sideport
SCHEME        := $(APP_NAME)
PROJECT       := $(APP_NAME).xcodeproj
CONFIGURATION := Release
BUILD_DIR     := build
APP_PATH      := $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
INSTALL_DIR   := $(HOME)/Applications

XCODEGEN ?= xcodegen

.DEFAULT_GOAL := help
.PHONY: help install-xcodegen generate edit build install uninstall clean

help: ## Mostra questo aiuto
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install-xcodegen: ## Installa XcodeGen (via mise o Homebrew) se manca
	@if command -v $(XCODEGEN) >/dev/null 2>&1; then \
		echo "XcodeGen gia' installato: $$($(XCODEGEN) --version)"; \
	elif command -v mise >/dev/null 2>&1; then \
		mise use --global xcodegen@latest; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install xcodegen; \
	else \
		echo "Ne' mise ne' Homebrew trovati: vedi https://github.com/yonaskolb/XcodeGen#installing" >&2; \
		exit 1; \
	fi

generate: ## Rigenera Sideport.xcodeproj da project.yml con XcodeGen
	$(XCODEGEN) generate

edit: ## Apre project.yml, la sorgente del progetto Xcode
	open project.yml

build: generate ## Compila la configurazione Release dentro ./build
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination 'platform=macOS' \
		-derivedDataPath $(BUILD_DIR) \
		build
	@echo "App compilata: $(APP_PATH)"

install: build ## Installa l'app Release in ~/Applications
	@if pgrep -x $(APP_NAME) >/dev/null; then \
		echo "$(APP_NAME) e' in esecuzione: chiudila prima di installare." >&2; \
		exit 1; \
	fi
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	ditto "$(APP_PATH)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installata in $(INSTALL_DIR)/$(APP_NAME).app"

uninstall: ## Rimuove l'app da ~/Applications
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"

clean: ## Rimuove i prodotti di build
	rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj dist .build Helpers/sideport-icon/target
