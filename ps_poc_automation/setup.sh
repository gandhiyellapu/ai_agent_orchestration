#!/bin/bash
# ============================================================================
# TD POC Enabler - One-Click Setup Script
# ============================================================================
# This script sets up EVERYTHING needed on a fresh MacBook.
# It will install: Homebrew, Node.js, Python 3, Claude CLI, and all dependencies.
#
# Usage:
#   ./setup.sh              # Interactive setup
#   ./setup.sh --headless   # Non-interactive (requires .env to exist)
#   ./setup.sh --help       # Show help
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

show_help() {
    cat << 'EOF'
TD POC Enabler Setup Script
============================

This script sets up everything needed for TD POC automation with Claude.

USAGE:
    ./setup.sh              Interactive setup (recommended for first time)
    ./setup.sh --headless   Non-interactive setup (requires .env to exist)
    ./setup.sh --help       Show this help message

WHAT GETS INSTALLED:
    - Homebrew (macOS package manager)
    - Node.js 20+ (required for Claude CLI and MCP)
    - Python 3.11+ (required for POC tools)
    - Claude CLI (AI assistant)
    - TD Toolbelt (optional, for direct TD operations)
    - Git (for version control)
    - All Node.js and Python dependencies

REQUIREMENTS:
    - macOS (Apple Silicon or Intel)
    - Internet connection
    - ~2GB free disk space
    - Admin password (for Homebrew installation)

FILES CREATED:
    .env                    Your configuration (from .env.template)
    .poc-state/             POC state tracking
    tools/python/.venv/     Python virtual environment
    tools/node/node_modules/ Node.js dependencies
    reference/              Cloned workflow templates

AFTER SETUP:
    1. Run 'claude' to start the AI assistant
    2. Use '/poc-start' to begin a new POC
    3. Follow the interactive prompts

EOF
}

# ============================================================================
# System Detection
# ============================================================================

detect_system() {
    log_step "Detecting System"

    # Check if macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS. Detected: $(uname)"
        log_error "For Linux, please install dependencies manually."
        exit 1
    fi

    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        log_info "Detected: Apple Silicon Mac (M1/M2/M3)"
        HOMEBREW_PREFIX="/opt/homebrew"
    else
        log_info "Detected: Intel Mac"
        HOMEBREW_PREFIX="/usr/local"
    fi

    # Check macOS version
    MACOS_VERSION=$(sw_vers -productVersion)
    log_info "macOS version: $MACOS_VERSION"

    log_success "System detection complete"
}

# ============================================================================
# Install Xcode Command Line Tools
# ============================================================================

install_xcode_cli() {
    log_step "Checking Xcode Command Line Tools"

    if xcode-select -p &> /dev/null; then
        log_success "Xcode Command Line Tools already installed"
    else
        log_info "Installing Xcode Command Line Tools..."
        log_warn "A dialog may appear. Please click 'Install' and wait for completion."

        xcode-select --install 2>/dev/null || true

        # Wait for installation
        echo "Waiting for Xcode CLI Tools installation..."
        echo "Press Enter after the installation is complete."
        read -r

        if xcode-select -p &> /dev/null; then
            log_success "Xcode Command Line Tools installed"
        else
            log_error "Xcode CLI Tools installation may have failed. Please install manually."
            exit 1
        fi
    fi
}

# ============================================================================
# Install Homebrew
# ============================================================================

install_homebrew() {
    log_step "Checking Homebrew"

    if command -v brew &> /dev/null; then
        log_success "Homebrew already installed"
        log_info "Updating Homebrew..."
        brew update --quiet 2>/dev/null || true
    else
        log_info "Installing Homebrew..."
        log_info "You may be prompted for your password."

        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for Apple Silicon
        if [[ "$ARCH" == "arm64" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi

        if command -v brew &> /dev/null; then
            log_success "Homebrew installed"
        else
            log_error "Homebrew installation failed"
            exit 1
        fi
    fi
}

# ============================================================================
# Install Node.js
# ============================================================================

install_nodejs() {
    log_step "Checking Node.js"

    # TDX requires Node.js 22+, so we target that version
    REQUIRED_NODE_VERSION=22

    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$NODE_VERSION" -ge "$REQUIRED_NODE_VERSION" ]; then
            log_success "Node.js $(node -v) is installed and meets requirements (22+)"
        else
            log_warn "Node.js $(node -v) is too old. TDX requires Node.js 22+."
            log_info "Installing Node.js 22..."
            brew unlink node@20 2>/dev/null || true
            brew unlink node 2>/dev/null || true
            brew install node@22
            brew link node@22 --overwrite --force 2>/dev/null || true
            export PATH="$HOMEBREW_PREFIX/opt/node@22/bin:$PATH"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/node@22/bin:\$PATH\"" >> ~/.zshrc
        fi
    else
        log_info "Installing Node.js 22 (required for TDX)..."
        brew install node@22
        brew link node@22 --overwrite --force 2>/dev/null || true

        if command -v node &> /dev/null; then
            log_success "Node.js $(node -v) installed"
        else
            # Try adding to PATH manually
            export PATH="$HOMEBREW_PREFIX/opt/node@22/bin:$PATH"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/node@22/bin:\$PATH\"" >> ~/.zshrc

            if command -v node &> /dev/null; then
                log_success "Node.js $(node -v) installed"
            else
                log_error "Node.js installation failed"
                exit 1
            fi
        fi
    fi

    # Verify npm
    if command -v npm &> /dev/null; then
        log_success "npm $(npm -v) is available"
    else
        log_error "npm not found. Please restart your terminal and run setup again."
        exit 1
    fi
}

# ============================================================================
# Install Python 3
# ============================================================================

install_python() {
    log_step "Checking Python 3"

    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f2)

        if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 9 ]; then
            log_success "Python $(python3 --version) meets requirements"
        else
            log_warn "Python $(python3 --version) may be too old. Installing Python 3.11..."
            brew install python@3.11
            brew link python@3.11 --overwrite --force 2>/dev/null || true
        fi
    else
        log_info "Installing Python 3.11..."
        brew install python@3.11
        brew link python@3.11 --overwrite --force 2>/dev/null || true

        if command -v python3 &> /dev/null; then
            log_success "Python $(python3 --version) installed"
        else
            export PATH="$HOMEBREW_PREFIX/opt/python@3.11/bin:$PATH"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/python@3.11/bin:\$PATH\"" >> ~/.zshrc

            if command -v python3 &> /dev/null; then
                log_success "Python $(python3 --version) installed"
            else
                log_error "Python installation failed"
                exit 1
            fi
        fi
    fi

    # Verify pip
    if python3 -m pip --version &> /dev/null; then
        log_success "pip is available"
    else
        log_info "Installing pip..."
        python3 -m ensurepip --upgrade
    fi
}

# ============================================================================
# Install Git
# ============================================================================

install_git() {
    log_step "Checking Git"

    if command -v git &> /dev/null; then
        log_success "Git $(git --version | cut -d' ' -f3) is installed"
    else
        log_info "Installing Git..."
        brew install git

        if command -v git &> /dev/null; then
            log_success "Git installed"
        else
            log_error "Git installation failed"
            exit 1
        fi
    fi
}

# ============================================================================
# Install Claude CLI
# ============================================================================

install_claude_cli() {
    log_step "Checking Claude CLI"

    if command -v claude &> /dev/null; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 || echo "installed")
        log_success "Claude CLI is installed ($CLAUDE_VERSION)"
    else
        log_info "Installing Claude CLI using official installer..."
        log_info "Source: https://claude.ai/install.sh"

        # Use official Anthropic install script
        curl -fsSL https://claude.ai/install.sh | bash -s stable

        # Refresh PATH to pick up new installation
        export PATH="$HOME/.claude/bin:$PATH"

        if command -v claude &> /dev/null; then
            CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 || echo "installed")
            log_success "Claude CLI installed ($CLAUDE_VERSION)"

            # Add to shell profile if not already there
            if ! grep -q '.claude/bin' ~/.zshrc 2>/dev/null; then
                echo 'export PATH="$HOME/.claude/bin:$PATH"' >> ~/.zshrc
                log_info "Added Claude to PATH in ~/.zshrc"
            fi
        else
            log_error "Claude CLI installation failed"
            log_error "Please install manually: curl -fsSL https://claude.ai/install.sh | bash -s stable"
            return 1
        fi
    fi
}

# ============================================================================
# Install TDX (AI-Native CLI for Treasure Data)
# ============================================================================

install_tdx() {
    log_step "Checking TDX CLI (AI-Native TD CLI)"

    if command -v tdx &> /dev/null; then
        log_success "TDX CLI is already installed"
    else
        log_info "Installing TDX CLI..."
        log_info "TDX is the modern AI-native CLI for Treasure Data"

        # Check Node.js version (TDX requires Node 22+)
        NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$NODE_VERSION" -lt 22 ]; then
            log_warn "TDX requires Node.js 22+. You have $(node -v)"
            log_info "Upgrading Node.js to 22..."
            brew unlink node@20 2>/dev/null || true
            brew install node@22
            brew link node@22 --overwrite --force 2>/dev/null || true
            export PATH="$HOMEBREW_PREFIX/opt/node@22/bin:$PATH"
            echo "export PATH=\"$HOMEBREW_PREFIX/opt/node@22/bin:\$PATH\"" >> ~/.zshrc
        fi

        npm install -g @treasuredata/tdx

        if command -v tdx &> /dev/null; then
            log_success "TDX CLI installed"
            log_info "You can now use 'tdx claude' to launch Claude with TD integration"
        else
            log_warn "TDX installation may have failed. Continuing with TD MCP only."
        fi
    fi
}

# ============================================================================
# Install TD Toolbelt (Fallback)
# ============================================================================

install_td_toolbelt() {
    log_step "Checking TD Toolbelt (Fallback)"

    if command -v td &> /dev/null; then
        log_success "TD Toolbelt is installed"
    else
        log_info "TD Toolbelt not found."
        log_info "This is a fallback - TDX and TD MCP are the primary tools."

        if [ "${1:-}" != "--headless" ]; then
            read -p "Install TD Toolbelt as fallback? [y/N]: " install_td
            install_td=${install_td:-N}

            if [[ "$install_td" =~ ^[Yy]$ ]]; then
                log_info "Installing TD Toolbelt..."

                # Install Ruby if not present (required for td gem)
                if ! command -v gem &> /dev/null; then
                    brew install ruby
                fi

                gem install td --no-document

                if command -v td &> /dev/null; then
                    log_success "TD Toolbelt installed"
                else
                    log_warn "TD Toolbelt installation may have failed. Continuing without it."
                fi
            else
                log_info "Skipping TD Toolbelt installation"
            fi
        fi
    fi
}

# ============================================================================
# Environment Setup
# ============================================================================

setup_env() {
    log_step "Setting Up Environment"

    if [ ! -f ".env" ]; then
        if [ -f ".env.template" ]; then
            cp .env.template .env
            log_info "Created .env from template"

            # Interactive prompts for required values
            if [ "${1:-}" != "--headless" ]; then
                echo ""
                echo -e "${YELLOW}${BOLD}Please provide your Treasure Data credentials:${NC}"
                echo -e "${CYAN}Get your API key from: TD Console > Personal Settings > API Keys${NC}"
                echo ""

                read -p "TD API Key: " td_api_key
                if [ -n "$td_api_key" ]; then
                    # Use perl for cross-platform sed compatibility
                    # Delimiter is | not / because API keys contain /
                    perl -i -pe "s|^TD_API_KEY=.*|TD_API_KEY=$td_api_key|" .env
                fi

                read -p "TD Site (us01/jp01/eu01/ap02) [us01]: " td_site
                td_site=${td_site:-us}
                perl -i -pe "s|^TD_SITE=.*|TD_SITE=$td_site|" .env

                echo ""
                echo -e "${YELLOW}POC Configuration:${NC}"
                echo ""

                read -p "Project Name (e.g., retail-poc): " project_name
                if [ -n "$project_name" ]; then
                    perl -i -pe "s|^TD_PROJECT_NAME=.*|TD_PROJECT_NAME=$project_name|" .env
                fi

                read -p "Raw Database Name (source data): " raw_db
                if [ -n "$raw_db" ]; then
                    perl -i -pe "s|^TD_RAW_DB=.*|TD_RAW_DB=$raw_db|" .env
                fi

                read -p "Staging Database Name (target): " stg_db
                if [ -n "$stg_db" ]; then
                    perl -i -pe "s|^TD_STG_DB=.*|TD_STG_DB=$stg_db|" .env
                fi

                echo ""
                echo -e "${YELLOW}Debug Mode:${NC}"
                echo "Debug mode uses 10% sample data for faster testing."
                read -p "Enable debug mode? [Y/n]: " debug_mode
                debug_mode=${debug_mode:-Y}
                if [[ "$debug_mode" =~ ^[Nn]$ ]]; then
                    perl -i -pe "s|^DEBUG_MODE=.*|DEBUG_MODE=false|" .env
                    log_info "Debug mode: OFF (full data)"
                else
                    perl -i -pe "s|^DEBUG_MODE=.*|DEBUG_MODE=true|" .env
                    log_info "Debug mode: ON (10% sample)"
                fi

                echo ""
                echo -e "${YELLOW}Optional - Notifications:${NC}"
                read -p "Slack Webhook URL (press Enter to skip): " slack_webhook
                if [ -n "$slack_webhook" ]; then
                    perl -i -pe "s|^SLACK_WEBHOOK_URL=.*|SLACK_WEBHOOK_URL=$slack_webhook|" .env
                fi

                echo ""
            fi
        else
            log_error ".env.template not found!"
            exit 1
        fi
    else
        log_info ".env already exists, using existing configuration"
    fi

    # Validate required values
    set +u  # Temporarily allow unset variables
    source .env 2>/dev/null || true
    set -u

    if [ -z "${TD_API_KEY:-}" ]; then
        log_error "TD_API_KEY is required in .env"
        log_error "Please edit .env and add your TD API key, then run setup again."
        exit 1
    fi

    log_success "Environment configured!"
}

# ============================================================================
# Python Virtual Environment
# ============================================================================

setup_python_venv() {
    log_step "Setting Up Python Virtual Environment"

    VENV_DIR="tools/python/.venv"
    mkdir -p "tools/python"

    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        log_info "Created Python virtual environment"
    fi

    # Activate and install dependencies
    source "$VENV_DIR/bin/activate"

    # Create requirements.txt if not exists
    if [ ! -f "tools/python/requirements.txt" ]; then
        cat > tools/python/requirements.txt << 'EOF'
requests>=2.31.0
python-dotenv>=1.0.0
pyyaml>=6.0.1
click>=8.1.7
rich>=13.7.0
EOF
    fi

    pip install --quiet --upgrade pip
    pip install --quiet -r tools/python/requirements.txt

    deactivate

    log_success "Python environment ready!"
}

# ============================================================================
# Node.js Setup
# ============================================================================

setup_node_deps() {
    log_step "Setting Up Node.js Dependencies"

    mkdir -p "tools/node"

    # Create package.json if not exists
    if [ ! -f "tools/node/package.json" ]; then
        cat > tools/node/package.json << 'EOF'
{
  "name": "td-poc-watcher",
  "version": "1.0.0",
  "description": "Background watcher for TD POC workflows",
  "main": "watcher.js",
  "type": "module",
  "scripts": {
    "start": "node watcher.js",
    "watch": "node watcher.js --daemon"
  },
  "dependencies": {
    "dotenv": "^16.3.1",
    "chalk": "^5.3.0"
  }
}
EOF
    fi

    cd tools/node
    npm install --silent 2>/dev/null || npm install
    cd "$SCRIPT_DIR"

    log_success "Node.js dependencies ready!"
}

# ============================================================================
# Install TD MCP Server
# ============================================================================

install_td_mcp() {
    log_step "Installing TD MCP Server"

    # Check if already installed globally
    if npm list -g @treasuredata/mcp-server &> /dev/null; then
        log_success "TD MCP Server already installed globally"
        # Show version
        MCP_VERSION=$(npm list -g @treasuredata/mcp-server --depth=0 2>/dev/null | grep mcp-server | awk -F@ '{print $NF}')
        log_info "Version: $MCP_VERSION"
    else
        log_info "Installing @treasuredata/mcp-server globally..."
        npm install -g @treasuredata/mcp-server

        if npm list -g @treasuredata/mcp-server &> /dev/null; then
            log_success "TD MCP Server installed"
        else
            log_warn "Could not install TD MCP Server globally."
            log_warn "Will fall back to npx (downloads on first use)."
        fi
    fi
}

# ============================================================================
# MCP Configuration
# ============================================================================

setup_mcp() {
    log_step "Configuring MCP Servers"

    set +u
    source .env 2>/dev/null || true
    set -u

    # Determine the MCP command (prefer global install, fallback to npx)
    if npm list -g @treasuredata/mcp-server &> /dev/null; then
        MCP_CMD="mcp-server-treasuredata"
        MCP_ARGS=""
    else
        MCP_CMD="npx"
        MCP_ARGS="@treasuredata/mcp-server"
    fi

    # Try to add TD MCP to global Claude config
    if command -v claude &> /dev/null; then
        log_info "Configuring TD MCP server..."

        # Check if already configured
        if claude mcp list 2>/dev/null | grep -q "treasuredata\|^td"; then
            log_info "TD MCP already configured in Claude"
        else
            if [ -n "$MCP_ARGS" ]; then
                claude mcp add td \
                    -e TD_API_KEY="${TD_API_KEY:-}" \
                    -e TD_SITE="${TD_SITE:-us01}" \
                    -e TD_ENABLE_UPDATES="${TD_ENABLE_UPDATES:-true}" \
                    -- $MCP_CMD $MCP_ARGS 2>/dev/null || {
                    log_warn "Could not add TD MCP automatically."
                }
            else
                claude mcp add td \
                    -e TD_API_KEY="${TD_API_KEY:-}" \
                    -e TD_SITE="${TD_SITE:-us01}" \
                    -e TD_ENABLE_UPDATES="${TD_ENABLE_UPDATES:-true}" \
                    -- $MCP_CMD 2>/dev/null || {
                    log_warn "Could not add TD MCP automatically."
                }
            fi
        fi
    else
        log_warn "Claude CLI not in PATH. MCP will be configured on first run."
    fi

    log_success "MCP configuration complete!"
}

# ============================================================================
# Create Project-Local MCP Configuration (.mcp.json)
# ============================================================================

setup_local_mcp() {
    log_step "Creating Project-Local MCP Configuration"

    set +u
    source .env 2>/dev/null || true
    set -u

    MCP_FILE=".mcp.json"

    if [ -f "$MCP_FILE" ]; then
        log_info ".mcp.json already exists"

        if [ "${1:-}" != "--headless" ]; then
            read -p "Overwrite existing MCP config? [y/N]: " overwrite
            overwrite=${overwrite:-N}
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                log_info "Keeping existing MCP configuration"
                return 0
            fi
        fi
    fi

    # Get values from .env (with defaults)
    local api_key="${TD_API_KEY:-}"
    local site="${TD_SITE:-us01}"
    local enable_updates="${TD_ENABLE_UPDATES:-true}"

    # Show what we're using (mask API key for security)
    if [ -n "$api_key" ]; then
        local masked_key="${api_key:0:4}...${api_key: -4}"
        log_info "TD API Key: $masked_key"
    else
        log_warn "TD API Key: NOT SET"
    fi
    log_info "TD Site: $site"
    log_info "TD Enable Updates: $enable_updates"

    # WARNING for write operations
    if [ "$enable_updates" = "true" ]; then
        echo ""
        echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}${BOLD}║                    ⚠️  WRITE MODE ENABLED ⚠️                      ║${NC}"
        echo -e "${RED}${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}${BOLD}║  TD_ENABLE_UPDATES=true                                          ║${NC}"
        echo -e "${RED}${BOLD}║                                                                  ║${NC}"
        echo -e "${RED}${BOLD}║  The TD MCP server will be able to:                              ║${NC}"
        echo -e "${RED}${BOLD}║    • CREATE databases and tables                                 ║${NC}"
        echo -e "${RED}${BOLD}║    • INSERT, UPDATE, and DELETE data                             ║${NC}"
        echo -e "${RED}${BOLD}║    • DROP tables and databases                                   ║${NC}"
        echo -e "${RED}${BOLD}║                                                                  ║${NC}"
        echo -e "${RED}${BOLD}║  Set TD_ENABLE_UPDATES=false in .env for read-only mode.         ║${NC}"
        echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi

    # Determine the MCP command (prefer global install, fallback to npx)
    if npm list -g @treasuredata/mcp-server &> /dev/null; then
        # Resolve full path to binary (needed for nvm where PATH may not
        # be available to Claude Code's child processes)
        local mcp_bin
        mcp_bin=$(which td-mcp-server 2>/dev/null || echo "td-mcp-server")
        cat > "$MCP_FILE" << EOF
{
  "mcpServers": {
    "td": {
      "command": "${mcp_bin}",
      "args": [],
      "env": {
        "TD_API_KEY": "${api_key}",
        "TD_SITE": "${site}",
        "TD_ENABLE_UPDATES": "${enable_updates}"
      }
    }
  }
}
EOF
        log_info "Using globally installed TD MCP Server: $mcp_bin"
    else
        # Fallback to npx (downloads on first use)
        cat > "$MCP_FILE" << EOF
{
  "mcpServers": {
    "td": {
      "command": "npx",
      "args": ["@treasuredata/mcp-server"],
      "env": {
        "TD_API_KEY": "${api_key}",
        "TD_SITE": "${site}",
        "TD_ENABLE_UPDATES": "${enable_updates}"
      }
    }
  }
}
EOF
        log_info "Using npx (will download on first use)"
    fi

    log_success "Created $MCP_FILE"
    log_info "This provides project-local MCP configuration for Claude"

    # Warn about secrets
    log_warn "NOTE: .mcp.json contains your API key - it's in .gitignore"
}

# ============================================================================
# Install TD Skills Plugin (Clone directly - slash commands don't work in bash)
# ============================================================================

install_td_skills() {
    log_step "Installing TD Skills"

    REPO_DIR=".claude/skills/.td-skills-repo"
    SKILLS_DIR=".claude/skills"
    MARKETPLACE="$REPO_DIR/.claude-plugin/marketplace.json"

    # Step 1: Clone or update the repo
    if [ -d "$REPO_DIR/.git" ]; then
        log_info "TD Skills repo found, updating..."
        (cd "$REPO_DIR" && git pull --quiet 2>/dev/null) || true
        log_success "TD Skills updated!"
    else
        log_info "Cloning TD Skills from GitHub..."
        mkdir -p "$SKILLS_DIR"
        rm -rf "$REPO_DIR"
        git clone --depth 1 \
            https://github.com/treasure-data/td-skills.git \
            "$REPO_DIR" 2>/dev/null || {
            log_warn "Could not clone TD Skills repository."
            log_warn "Clone manually: git clone https://github.com/treasure-data/td-skills.git $REPO_DIR"
            return 0
        }
        log_success "TD Skills cloned!"
    fi

    # Step 2: Remove old symlinks and legacy directory
    find "$SKILLS_DIR" -maxdepth 1 -type l -name "td-*" -delete 2>/dev/null || true
    if [ -d "$SKILLS_DIR/td-skills" ] && [ ! -L "$SKILLS_DIR/td-skills" ]; then
        log_info "Removing old td-skills directory (replacing with symlinks)..."
        rm -rf "$SKILLS_DIR/td-skills"
    fi

    # Step 3: Create symlinks for each skill
    SKILL_COUNT=0
    if [ -f "$MARKETPLACE" ]; then
        SKILL_COUNT=$(python3 -c "
import json, os, sys

marketplace_path = sys.argv[1]
repo_dir = sys.argv[2]
skills_dir = sys.argv[3]

cat_short = {
    'sql-skills': 'sql',
    'tdx-skills': 'tdx',
    'aps-doc-skills': 'aps',
    'workflow-skills': 'wf',
    'realtime-skills': 'rt',
    'sdk-skills': 'sdk',
    'field-agent-skills': 'field',
    'semantic-layer': 'sem',
    'template-skill': 'tmpl',
}

with open(marketplace_path) as f:
    data = json.load(f)

count = 0
for plugin in data.get('plugins', []):
    plugin_name = plugin.get('name', '')
    prefix = cat_short.get(plugin_name, plugin_name.replace('-skills', '').replace('-', ''))

    for skill_path in plugin.get('skills', []):
        skill_path = skill_path.lstrip('./')
        skill_name = os.path.basename(skill_path)
        full_path = os.path.join(repo_dir, skill_path)
        skill_md = os.path.join(full_path, 'SKILL.md')

        if os.path.isfile(skill_md):
            link_name = 'td-{}-{}'.format(prefix, skill_name)
            link_path = os.path.join(skills_dir, link_name)
            rel_target = os.path.relpath(full_path, skills_dir)
            if os.path.islink(link_path):
                os.unlink(link_path)
            os.symlink(rel_target, link_path)
            count += 1

print(count)
" "$MARKETPLACE" "$REPO_DIR" "$SKILLS_DIR" 2>/dev/null) || SKILL_COUNT=0
    fi

    # Fallback: if marketplace.json missing or produced 0 skills, scan for SKILL.md files
    if [ "$SKILL_COUNT" -eq 0 ] 2>/dev/null; then
        log_info "marketplace.json not available, scanning for SKILL.md files..."
        while IFS= read -r skill_md; do
            skill_dir=$(dirname "$skill_md")
            skill_name=$(basename "$skill_dir")
            category_dir=$(basename "$(dirname "$skill_dir")")

            # Map category to short prefix
            case "$category_dir" in
                sql-skills)         prefix="sql" ;;
                tdx-skills)         prefix="tdx" ;;
                aps-doc-skills)     prefix="aps" ;;
                workflow-skills)    prefix="wf" ;;
                realtime-skills)    prefix="rt" ;;
                sdk-skills)         prefix="sdk" ;;
                field-agent-skills) prefix="field" ;;
                semantic-layer)     prefix="sem" ;;
                template-skill)     prefix="tmpl" ;;
                *)                  prefix=$(echo "$category_dir" | sed 's/-skills//;s/-//g') ;;
            esac

            link_name="td-${prefix}-${skill_name}"
            link_path="$SKILLS_DIR/$link_name"
            rel_target=$(python3 -c "import os; print(os.path.relpath('$skill_dir', '$SKILLS_DIR'))")

            if [ -L "$link_path" ]; then rm "$link_path"; fi
            ln -s "$rel_target" "$link_path"
            SKILL_COUNT=$((SKILL_COUNT + 1))
        done < <(find "$REPO_DIR" -mindepth 3 -maxdepth 3 -name "SKILL.md" -type f 2>/dev/null)
    fi

    log_success "Registered $SKILL_COUNT TD skills as symlinks"
    log_info "Skills available as: td-sql-*, td-tdx-*, td-aps-*, td-wf-*, td-rt-*, etc."
}

# ============================================================================
# Clone Reference Repository
# ============================================================================

clone_reference_repo() {
    log_step "Setting Up Reference Repository"

    set +u
    source .env 2>/dev/null || true
    set -u

    REPO="${TD_REFERENCE_REPO:-treasure-data/se-starter-pack}"
    BRANCH="${TD_REFERENCE_BRANCH:-main}"
    SUBDIR="${TD_REFERENCE_SUBDIR:-retail-starter-pack}"
    PROJECT_NAME="${TD_PROJECT_NAME:-retail-poc}"

    REF_DIR="reference"
    TEMP_DIR=".tmp-clone"
    PROJECT_DIR="$REF_DIR/$PROJECT_NAME"

    # Check if project directory already exists
    if [ -d "$PROJECT_DIR" ]; then
        log_info "Project directory '$PROJECT_NAME' already exists"
        log_info "Location: $PROJECT_DIR"

        if [ "${1:-}" != "--headless" ]; then
            read -p "Update from upstream? [y/N]: " update_ref
            update_ref=${update_ref:-N}
            if [[ ! "$update_ref" =~ ^[Yy]$ ]]; then
                log_info "Keeping existing project directory"
                return 0
            fi
        else
            log_info "Keeping existing project directory"
            return 0
        fi
    fi

    log_info "Cloning reference repository..."
    log_info "Repository: https://github.com/$REPO"
    log_info "Vertical: $SUBDIR"
    log_info "Project Name: $PROJECT_NAME"

    # Clean up any previous temp directory
    rm -rf "$TEMP_DIR"

    # Clone to temp directory
    git clone --depth 1 --branch "$BRANCH" \
        "https://github.com/$REPO.git" "$TEMP_DIR" 2>/dev/null || {
        log_error "Failed to clone repository"
        log_error "Please check your internet connection and try again"
        rm -rf "$TEMP_DIR"
        return 1
    }

    # Check if the subdirectory exists
    if [ ! -d "$TEMP_DIR/$SUBDIR" ]; then
        log_error "Subdirectory '$SUBDIR' not found in repository"
        log_error "Available directories:"
        ls -1 "$TEMP_DIR" | grep -v "^\." | head -10
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Create reference directory
    mkdir -p "$REF_DIR"

    # Extract and rename the vertical to project name
    if [ -d "$PROJECT_DIR" ]; then
        rm -rf "$PROJECT_DIR"
    fi
    mv "$TEMP_DIR/$SUBDIR" "$PROJECT_DIR"

    # Clean up temp directory
    rm -rf "$TEMP_DIR"

    log_success "Extracted '$SUBDIR' as '$PROJECT_NAME'"
    log_info "Project location: $PROJECT_DIR"

    # Show what was extracted
    if [ -d "$PROJECT_DIR" ]; then
        FILE_COUNT=$(find "$PROJECT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        log_info "Extracted $FILE_COUNT files"
    fi

    log_success "Reference repository ready!"
}

# ============================================================================
# Initialize POC State
# ============================================================================

init_poc_state() {
    log_step "Initializing POC State"

    set +u
    source .env 2>/dev/null || true
    set -u

    STATE_DIR=".poc-state"
    mkdir -p "$STATE_DIR"
    mkdir -p "$STATE_DIR/sessions"

    # Create config from .env
    cat > "$STATE_DIR/config.json" << EOF
{
  "project_name": "${TD_PROJECT_NAME:-retail-poc}",
  "raw_db": "${TD_RAW_DB:-}",
  "stg_db": "${TD_STG_DB:-}",
  "site": "${TD_SITE:-us01}",
  "max_retries": ${MAX_RETRIES:-10},
  "retry_delay_seconds": ${RETRY_DELAY_SECONDS:-300},
  "poll_interval_seconds": ${POLL_INTERVAL_SECONDS:-60},
  "debug_mode": ${DEBUG_MODE:-true},
  "debug_sample_percent": ${DEBUG_SAMPLE_PERCENT:-10},
  "slack_webhook_url": "${SLACK_WEBHOOK_URL:-}",
  "terminal_notify": ${TERMINAL_NOTIFY:-true}
}
EOF

    # Create initial POC state if not exists
    if [ ! -f "$STATE_DIR/current-poc.json" ]; then
        cat > "$STATE_DIR/current-poc.json" << 'EOF'
{
  "poc_id": null,
  "created_at": null,
  "stage": "init",
  "stages": {
    "init": { "status": "pending" },
    "profiling": { "status": "pending" },
    "staging": { "status": "pending" },
    "unification": { "status": "pending" },
    "golden": { "status": "pending" },
    "segment": { "status": "pending" }
  },
  "active_td_session": null,
  "errors": []
}
EOF
    fi

    log_success "POC state initialized!"
}

# ============================================================================
# Update .gitignore
# ============================================================================

update_gitignore() {
    log_step "Updating .gitignore"

    # Entries to add
    IGNORES=(
        "# TD POC Enabler"
        ".env"
        ".mcp/"
        ".mcp.json"
        ".poc-state/"
        ".claude/skills/.td-skills-repo/"
        ".claude/skills/td-*/"
        "tools/python/.venv/"
        "tools/node/node_modules/"
        "reference/"
        "*.log"
        ".DS_Store"
        "__pycache__/"
        "*.pyc"
        ".idea/"
        ".vscode/"
    )

    touch .gitignore

    for entry in "${IGNORES[@]}"; do
        if ! grep -qF "$entry" .gitignore 2>/dev/null; then
            echo "$entry" >> .gitignore
        fi
    done

    log_success ".gitignore updated!"
}

# ============================================================================
# Create Activation Script
# ============================================================================

create_activate_script() {
    log_step "Creating Activation Script"

    cat > activate.sh << 'EOF'
#!/bin/bash
# Activate TD POC Enabler environment
# Usage: source activate.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
    echo "Loaded .env configuration"
fi

# Activate Python venv
if [ -f "tools/python/.venv/bin/activate" ]; then
    source tools/python/.venv/bin/activate
    echo "Activated Python virtual environment"
fi

# Add local tools to PATH
export PATH="$SCRIPT_DIR/tools/python:$SCRIPT_DIR/tools/node:$PATH"

echo ""
echo "TD POC Enabler environment activated!"
echo "Run 'claude' to start, then use '/poc-start' to begin a POC"
echo ""
EOF

    chmod +x activate.sh

    log_success "Created activate.sh"
}

# ============================================================================
# Print Summary
# ============================================================================

print_summary() {
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}${BOLD}Setup Complete!${NC}"
    echo "============================================================================"
    echo ""
    echo "Your TD POC Enabler is ready to use on this MacBook."
    echo ""
    echo -e "${BOLD}Installed:${NC}"
    echo "  - Homebrew (package manager)"
    echo "  - Node.js $(node -v 2>/dev/null || echo 'installed')"
    echo "  - Python $(python3 --version 2>/dev/null | cut -d' ' -f2 || echo 'installed')"
    echo "  - Claude CLI"
    if command -v tdx &> /dev/null; then
        echo "  - TDX CLI (AI-native TD CLI)"
    fi
    if npm list -g @treasuredata/mcp-server &> /dev/null; then
        MCP_VER=$(npm list -g @treasuredata/mcp-server --depth=0 2>/dev/null | grep mcp-server | awk -F@ '{print $NF}')
        echo "  - TD MCP Server v$MCP_VER (global)"
    else
        echo "  - TD MCP Server (via npx)"
    fi
    TD_SKILL_LINK_COUNT=$(find .claude/skills -maxdepth 1 -type l -name "td-*" 2>/dev/null | wc -l | tr -d ' ')
    echo "  - TD Skills ($TD_SKILL_LINK_COUNT skills registered)"
    if command -v td &> /dev/null; then
        echo "  - TD Toolbelt (fallback)"
    fi
    echo ""
    echo -e "${BOLD}Quick Start (Choose one):${NC}"
    echo ""
    echo "  ${CYAN}Option A - Using TDX (recommended):${NC}"
    echo "     tdx auth setup    # Configure your TD credentials"
    echo "     tdx claude        # Launch Claude with TD integration"
    echo ""
    echo "  ${CYAN}Option B - Using Claude directly:${NC}"
    echo "     claude            # Start Claude Code"
    echo "     /poc-start        # Begin a new POC"
    echo ""
    echo -e "${BOLD}POC Commands:${NC}"
    echo "  /poc-start   - Start a new POC"
    echo "  /poc-status  - Check current progress"
    echo "  /poc-resume  - Continue after a break"
    echo ""
    echo -e "${BOLD}Background Watcher (optional):${NC}"
    echo "  cd tools/node && npm start"
    echo ""
    # Get project name for display
    set +u
    source .env 2>/dev/null || true
    local project_name="${TD_PROJECT_NAME:-retail-poc}"
    set -u

    echo -e "${BOLD}Configuration:${NC}"
    echo "  - Edit .env to change settings"
    echo "  - MCP config in .mcp.json (project-local)"
    echo "  - TD Skills in .claude/skills/td-*/ (symlinks)"
    echo "  - State is stored in .poc-state/"
    echo "  - Project workflows in reference/$project_name/"
    echo ""
    echo -e "${BOLD}Documentation:${NC}"
    echo "  - README.md - Getting started guide"
    echo "  - CLAUDE.md - AI assistant instructions"
    echo "  - https://tdx.treasuredata.com/ - TDX documentation"
    echo ""
    echo -e "${YELLOW}Note: If this is a new terminal, run 'source ~/.zshrc' first.${NC}"
    echo ""
    echo "============================================================================"
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Check for help flag
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        show_help
        exit 0
    fi

    echo ""
    echo "============================================================================"
    echo -e "${BOLD}TD POC Enabler - Setup${NC}"
    echo "============================================================================"
    echo ""
    echo "This script will set up everything needed on your MacBook."
    echo "It may take 5-10 minutes on first run."
    echo ""

    if [ "${1:-}" != "--headless" ]; then
        read -p "Continue with setup? [Y/n]: " confirm
        confirm=${confirm:-Y}
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Setup cancelled."
            exit 0
        fi
    fi

    detect_system
    install_xcode_cli
    install_homebrew
    install_nodejs
    install_python
    install_git
    install_claude_cli
    install_tdx
    install_td_toolbelt "$@"
    setup_env "$@"
    setup_python_venv
    setup_node_deps
    install_td_mcp
    setup_mcp
    setup_local_mcp "$@"
    install_td_skills
    clone_reference_repo "$@"
    init_poc_state
    update_gitignore
    create_activate_script
    print_summary

    # Offer to launch Claude
    if [ "${1:-}" != "--headless" ]; then
        echo ""
        read -p "Launch Claude now? [Y/n]: " launch_claude
        launch_claude=${launch_claude:-Y}

        if [[ "$launch_claude" =~ ^[Yy]$ ]]; then
            echo ""
            log_info "Starting Claude Code..."
            log_info "Use '/poc-start' to begin a new POC"
            echo ""

            # Use exec to replace shell with Claude (cleaner process handling)
            exec claude
        else
            echo ""
            log_info "Run 'claude' when ready to start"
            echo ""
        fi
    fi
}

main "$@"
