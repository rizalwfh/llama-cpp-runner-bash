#!/bin/bash

# Llama.cpp Runner with PM2 Integration
# This script downloads models from HuggingFace and serves them using llama.cpp with PM2

# Enable debug mode if DEBUG=1
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -euxo pipefail
    echo "🐛 Debug mode enabled"
else
    set -euo pipefail
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
MODELS_DIR="$SCRIPT_DIR/models"
LOGS_DIR="$SCRIPT_DIR/logs"
CONFIG_DIR="$SCRIPT_DIR/config"
PM2_CONFIG_DIR="$CONFIG_DIR/pm2"

# Export variables so they're available to sourced functions
export SCRIPT_DIR LIB_DIR MODELS_DIR LOGS_DIR CONFIG_DIR PM2_CONFIG_DIR

# Colors for output - export them too
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
export RED GREEN YELLOW BLUE NC

# Ensure directories exist
mkdir -p "$MODELS_DIR" "$LOGS_DIR" "$PM2_CONFIG_DIR"

# Source utility functions with error checking
if [[ ! -f "$LIB_DIR/utils.sh" ]]; then
    echo "❌ ERROR: utils.sh not found at $LIB_DIR/utils.sh"
    exit 1
fi

if [[ ! -f "$LIB_DIR/download.sh" ]]; then
    echo "❌ ERROR: download.sh not found at $LIB_DIR/download.sh"
    exit 1
fi

if [[ ! -f "$LIB_DIR/pm2-config.sh" ]]; then
    echo "❌ ERROR: pm2-config.sh not found at $LIB_DIR/pm2-config.sh"
    exit 1
fi

# Source functions in correct dependency order
# utils.sh must be sourced first as other files depend on its functions
echo "🔧 Loading utility functions..."
source "$LIB_DIR/utils.sh"

echo "📦 Loading download functions..."
source "$LIB_DIR/download.sh"

echo "⚙️  Loading PM2 configuration functions..."
source "$LIB_DIR/pm2-config.sh"

echo "✅ All functions loaded successfully"

# Verify critical functions are available
verify_functions() {
    local missing_functions=()

    # Check utils.sh functions
    declare -f check_dependencies >/dev/null || missing_functions+=("check_dependencies")
    declare -f find_available_port >/dev/null || missing_functions+=("find_available_port")
    declare -f wait_for_health >/dev/null || missing_functions+=("wait_for_health")
    declare -f log_message >/dev/null || missing_functions+=("log_message")

    # Check download.sh functions
    declare -f download_model >/dev/null || missing_functions+=("download_model")

    # Check pm2-config.sh functions
    declare -f generate_pm2_config >/dev/null || missing_functions+=("generate_pm2_config")

    if [[ ${#missing_functions[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Missing required functions: ${missing_functions[*]}${NC}"
        return 1
    fi

    return 0
}

if ! verify_functions; then
    echo -e "${RED}❌ Function verification failed${NC}"
    exit 1
fi

# Default configuration
DEFAULT_PORT=8080
DEFAULT_CONTEXT_SIZE=2048
DEFAULT_THREADS=4

# Cleanup function for graceful exit
cleanup_on_exit() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]] && [[ -n "${instance_name:-}" ]]; then
        echo ""
        echo -e "${YELLOW}🧹 Cleaning up failed deployment...${NC}"

        # Remove PM2 process if it was created (only if PM2 is running)
        if command -v pm2 &> /dev/null && pm2 ping &> /dev/null; then
            if pm2_process_exists "$instance_name"; then
                echo "Removing PM2 process: $instance_name"
                pm2 delete "$instance_name" 2>/dev/null || {
                    echo "Warning: Could not remove PM2 process $instance_name"
                }
            fi
        fi

        # Remove configuration file if it was created
        local config_file="$PM2_CONFIG_DIR/ecosystem-$instance_name.config.js"
        if [[ -f "$config_file" ]]; then
            echo "Removing configuration file: $config_file"
            rm -f "$config_file" || {
                echo "Warning: Could not remove config file $config_file"
            }
        fi

        # Clean up any temporary files
        find /tmp -name "*_*.gguf" -mmin -30 -delete 2>/dev/null || true

        echo -e "${BLUE}💡 Cleanup completed. You can run the script again.${NC}"
        log_message "INFO" "Cleanup completed after failed deployment"
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Migration function for existing PM2 configs
migrate_old_configs() {
    local old_configs_found=false

    # Check for old config files in root directory
    for old_config in "$SCRIPT_DIR"/ecosystem-*.config.js; do
        if [[ -f "$old_config" ]]; then
            old_configs_found=true
            local filename=$(basename "$old_config")
            local new_config="$PM2_CONFIG_DIR/$filename"

            log_message "INFO" "Migrating config: $filename" >&2

            # Move old config to new location
            if mv "$old_config" "$new_config"; then
                log_message "INFO" "Successfully migrated: $filename → config/pm2/$filename" >&2
            else
                log_message "WARN" "Failed to migrate: $filename" >&2
            fi
        fi
    done

    # Check for old monitoring config
    if [[ -f "$SCRIPT_DIR/monitoring.config.js" ]]; then
        old_configs_found=true
        if mv "$SCRIPT_DIR/monitoring.config.js" "$PM2_CONFIG_DIR/monitoring.config.js"; then
            log_message "INFO" "Migrated monitoring.config.js → config/pm2/" >&2
        fi
    fi

    if [[ "$old_configs_found" == "true" ]]; then
        echo -e "${GREEN}🔄 Migrated old PM2 configurations to config/pm2/ directory${NC}" >&2
    fi
}

# Run migration on startup
migrate_old_configs

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  🦙 Llama.cpp Runner with PM2                ║"
    echo "║              Serve HuggingFace Models in Production          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -l, --list           List running PM2 processes"
    echo "  -s, --status         Show detailed status of all instances"
    echo "  -c, --cleanup        Clean up old models and logs"
    echo ""
    echo "Interactive mode (default): Run without options to start interactive setup"
}

interactive_setup() {
    print_banner

    echo -e "${YELLOW}🚀 Welcome to Llama.cpp Runner Setup${NC}"
    echo ""

    # Get model ID from user
    while true; do
        echo -e "${BLUE}📦 Enter HuggingFace Model ID:${NC}"
        echo "   Examples: microsoft/DialoGPT-medium, huggingfaceh4/zephyr-7b-beta"
        echo "   Format: username/model-name"
        echo ""
        read -p "Model ID: " model_id

        if [[ -n "$model_id" && "$model_id" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
            break
        else
            echo -e "${RED}❌ Invalid model ID format. Please use: username/model-name${NC}"
            echo ""
        fi
    done

    # Get PM2 instance name
    while true; do
        echo ""
        echo -e "${BLUE}🏷️  Enter PM2 Instance Name:${NC}"
        echo "   This will be used to identify your process in PM2"
        echo "   Use alphanumeric characters, hyphens, and underscores only"
        echo ""
        read -p "Instance name: " instance_name

        if [[ -n "$instance_name" && "$instance_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            # Check if instance already exists
            if pm2 describe "$instance_name" &>/dev/null; then
                echo -e "${YELLOW}⚠️  Instance '$instance_name' already exists.${NC}"
                read -p "Do you want to restart it? (y/N): " restart_choice
                if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
                    pm2 delete "$instance_name" || true
                    break
                fi
            else
                break
            fi
        else
            echo -e "${RED}❌ Invalid instance name. Use only alphanumeric characters, hyphens, and underscores.${NC}"
        fi
    done

    # Get optional configuration
    echo ""
    echo -e "${BLUE}⚙️  Optional Configuration (press Enter for defaults):${NC}"

    # Get and validate port
    while true; do
        read -p "Port (default: $DEFAULT_PORT): " port
        port=${port:-$DEFAULT_PORT}

        if validate_port "$port"; then
            break
        else
            echo -e "${RED}❌ Invalid port number. Must be between 1024-65535.${NC}"
        fi
    done

    # Get and validate context size
    while true; do
        read -p "Context size (default: $DEFAULT_CONTEXT_SIZE): " context_size
        context_size=${context_size:-$DEFAULT_CONTEXT_SIZE}

        if [[ "$context_size" =~ ^[0-9]+$ ]] && [[ $context_size -ge 512 ]] && [[ $context_size -le 32768 ]]; then
            break
        else
            echo -e "${RED}❌ Invalid context size. Must be between 512-32768.${NC}"
        fi
    done

    # Get and validate thread count
    local max_threads=$(nproc)
    while true; do
        read -p "Number of threads (default: $DEFAULT_THREADS, max: $max_threads): " threads
        threads=${threads:-$DEFAULT_THREADS}

        if [[ "$threads" =~ ^[0-9]+$ ]] && [[ $threads -ge 1 ]] && [[ $threads -le $max_threads ]]; then
            break
        else
            echo -e "${RED}❌ Invalid thread count. Must be between 1-$max_threads.${NC}"
        fi
    done

    echo ""
    echo -e "${GREEN}📋 Configuration Summary:${NC}"
    echo "   Model ID: $model_id"
    echo "   Instance: $instance_name"
    echo "   Port: $port"
    echo "   Context Size: $context_size"
    echo "   Threads: $threads"
    echo ""

    read -p "Continue with this configuration? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Setup cancelled.${NC}"
        exit 0
    fi

    # Start the deployment process
    echo ""
    echo -e "${GREEN}🚀 Starting deployment...${NC}"

    # Check dependencies with error recovery
    echo -e "${YELLOW}🔍 Checking system dependencies...${NC}"
    if ! check_dependencies; then
        echo -e "${RED}❌ Dependency check failed${NC}"
        echo -e "${BLUE}💡 Please install missing dependencies and try again${NC}"
        exit 1
    fi

    # Download model with error recovery
    echo -e "${YELLOW}📥 Downloading model...${NC}"
    if ! model_path=$(download_model "$model_id"); then
        echo -e "${RED}❌ Failed to download model${NC}"
        echo -e "${BLUE}💡 Troubleshooting tips:${NC}"
        echo "   • Check internet connection"
        echo "   • Verify model ID: $model_id"
        echo "   • Ensure sufficient disk space"
        echo "   • Try running with DEBUG=1 for more details"
        exit 1
    fi

    if [[ ! -f "$model_path" ]]; then
        echo -e "${RED}❌ Model file not found after download: $model_path${NC}"
        exit 1
    fi

    log_message "INFO" "Model successfully downloaded: $model_path"

    # Find available port with fallback
    echo -e "${YELLOW}🔍 Finding available port...${NC}"
    if ! final_port=$(find_available_port "$port"); then
        echo -e "${RED}❌ Could not find available port starting from $port${NC}"
        echo -e "${BLUE}💡 Try using a different port range or free up ports in use${NC}"
        exit 1
    fi
    if [[ "$final_port" != "$port" ]]; then
        echo -e "${YELLOW}⚠️  Port $port is busy, using port $final_port instead${NC}"
        log_message "WARN" "Port changed from $port to $final_port"
    fi

    # Generate PM2 configuration with error handling
    echo -e "${YELLOW}⚙️  Generating PM2 configuration...${NC}"
    if ! config_file=$(generate_pm2_config "$instance_name" "$model_path" "$final_port" "$context_size" "$threads"); then
        echo -e "${RED}❌ Failed to generate PM2 configuration${NC}"
        exit 1
    fi

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}❌ PM2 configuration file not created: $config_file${NC}"
        exit 1
    fi

    log_message "INFO" "PM2 configuration generated: $config_file"

    # Start with PM2 with error handling
    echo -e "${YELLOW}🚀 Starting with PM2...${NC}"
    if ! pm2 start "$config_file"; then
        echo -e "${RED}❌ Failed to start PM2 process${NC}"
        echo -e "${BLUE}💡 Troubleshooting:${NC}"
        echo "   • Check PM2 logs: pm2 logs $instance_name"
        echo "   • Verify llama-server binary is available"
        echo "   • Check system resources with: pm2 monit"
        exit 1
    fi

    log_message "INFO" "PM2 process started successfully"

    # Wait for startup and health check
    echo -e "${YELLOW}🔍 Performing health check...${NC}"
    if wait_for_health "http://localhost:$final_port/health" 30; then
        echo -e "${GREEN}✅ Service is running successfully!${NC}"
        echo ""
        echo -e "${GREEN}🎉 Deployment Complete!${NC}"
        echo ""
        echo -e "${BLUE}📊 Service Information:${NC}"
        echo "   • Instance Name: $instance_name"
        echo "   • Model: $model_id"
        echo "   • Server URL: http://localhost:$final_port"
        echo "   • Health Check: http://localhost:$final_port/health"
        echo "   • API Documentation: http://localhost:$final_port (web UI)"
        echo ""
        echo -e "${BLUE}📋 PM2 Management Commands:${NC}"
        echo "   • View logs: pm2 logs $instance_name"
        echo "   • Restart: pm2 restart $instance_name"
        echo "   • Stop: pm2 stop $instance_name"
        echo "   • Delete: pm2 delete $instance_name"
        echo "   • Monitor: pm2 monit"
        echo ""
    else
        echo -e "${RED}❌ Health check failed. Service may not be running properly.${NC}"
        echo -e "${BLUE}💡 Troubleshooting steps:${NC}"
        echo "   1. Check PM2 process status: pm2 list"
        echo "   2. View process logs: pm2 logs $instance_name"
        echo "   3. Check if port $final_port is available: netstat -tuln | grep $final_port"
        echo "   4. Monitor system resources: pm2 monit"
        echo "   5. Try manual start for debugging:"
        echo "      DEBUG=1 ./llama-runner.sh"
        echo ""
        echo -e "${YELLOW}⚠️  The service may still be starting up. You can check its status with:${NC}"
        echo "   pm2 list"
        echo "   pm2 logs $instance_name"

        log_message "ERROR" "Health check failed for $instance_name on port $final_port"
        exit 1
    fi
}

list_processes() {
    echo -e "${BLUE}📋 PM2 Processes:${NC}"
    pm2 list
}

show_status() {
    echo -e "${BLUE}📊 Detailed Status:${NC}"
    if ! pm2 status 2>/dev/null; then
        echo -e "${RED}❌ PM2 is not running or not accessible${NC}"
        return 1
    fi
    echo ""
    echo -e "${BLUE}💾 Memory Usage:${NC}"
    pm2 show 2>/dev/null || echo "No detailed process information available"
}

cleanup_old_files() {
    echo -e "${YELLOW}🧹 Cleaning up old files...${NC}"
    local cleaned_items=0

    # Remove models older than 30 days
    if [[ -d "$MODELS_DIR" ]]; then
        local old_models=$(find "$MODELS_DIR" -name "*.gguf" -mtime +30 2>/dev/null | wc -l)
        find "$MODELS_DIR" -name "*.gguf" -mtime +30 -delete 2>/dev/null || true
        if [[ $old_models -gt 0 ]]; then
            echo "  • Removed $old_models old model files"
            cleaned_items=$((cleaned_items + old_models))
        fi
    fi

    # Rotate logs
    if [[ -d "$LOGS_DIR" ]]; then
        local large_logs=$(find "$LOGS_DIR" -name "*.log" -size +100M 2>/dev/null | wc -l)
        find "$LOGS_DIR" -name "*.log" -size +100M -exec truncate -s 50M {} \; 2>/dev/null || true
        if [[ $large_logs -gt 0 ]]; then
            echo "  • Truncated $large_logs large log files"
            cleaned_items=$((cleaned_items + large_logs))
        fi
    fi

    # Clean PM2 logs if PM2 is available
    if command -v pm2 &> /dev/null && pm2 ping &> /dev/null; then
        pm2 flush 2>/dev/null && echo "  • Flushed PM2 logs" || true
    fi

    # Clean temporary download files
    local temp_files=$(find /tmp -name "*_*.gguf" -mmin +60 2>/dev/null | wc -l)
    find /tmp -name "*_*.gguf" -mmin +60 -delete 2>/dev/null || true
    if [[ $temp_files -gt 0 ]]; then
        echo "  • Removed $temp_files temporary files"
        cleaned_items=$((cleaned_items + temp_files))
    fi

    if [[ $cleaned_items -eq 0 ]]; then
        echo "  • No files needed cleanup"
    fi

    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

main() {
    case "${1:-}" in
        -h|--help)
            print_usage
            ;;
        -l|--list)
            list_processes
            ;;
        -s|--status)
            show_status
            ;;
        -c|--cleanup)
            cleanup_old_files
            ;;
        "")
            interactive_setup
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"