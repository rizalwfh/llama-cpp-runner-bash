#!/bin/bash

# Utility functions for Llama.cpp Runner

# Validate required variables
validate_environment() {
    local missing_vars=()

    # Check for required directory variables
    [[ -z "${SCRIPT_DIR:-}" ]] && missing_vars+=("SCRIPT_DIR")
    [[ -z "${MODELS_DIR:-}" ]] && missing_vars+=("MODELS_DIR")
    [[ -z "${LOGS_DIR:-}" ]] && missing_vars+=("LOGS_DIR")
    [[ -z "${CONFIG_DIR:-}" ]] && missing_vars+=("CONFIG_DIR")
    [[ -z "${PM2_CONFIG_DIR:-}" ]] && missing_vars+=("PM2_CONFIG_DIR")

    # Check for color variables
    [[ -z "${RED:-}" ]] && missing_vars+=("RED")
    [[ -z "${GREEN:-}" ]] && missing_vars+=("GREEN")
    [[ -z "${YELLOW:-}" ]] && missing_vars+=("YELLOW")
    [[ -z "${BLUE:-}" ]] && missing_vars+=("BLUE")
    [[ -z "${NC:-}" ]] && missing_vars+=("NC")

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "❌ ERROR: Missing required environment variables: ${missing_vars[*]}"
        echo "💡 These should be exported from the main script"
        return 1
    fi

    # Ensure directories exist
    mkdir -p "$MODELS_DIR" "$LOGS_DIR" "$PM2_CONFIG_DIR" 2>/dev/null || {
        echo "❌ ERROR: Cannot create required directories"
        return 1
    }

    return 0
}

# Auto-validate environment when this file is sourced
if ! validate_environment; then
    echo "❌ Environment validation failed in utils.sh"
    return 1 2>/dev/null || exit 1
fi

# Check if required dependencies are installed
check_dependencies() {
    local missing_deps=()

    # Check for required commands
    if ! command -v pm2 &> /dev/null; then
        missing_deps+=("pm2")
    fi

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    # Check for llama-server or llama-cpp-server
    if ! command -v llama-server &> /dev/null && ! command -v llama-cpp-server &> /dev/null; then
        missing_deps+=("llama-server or llama-cpp-server")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Missing dependencies:${NC}"
        for dep in "${missing_deps[@]}"; do
            echo "   • $dep"
        done
        echo ""
        echo -e "${YELLOW}📝 Installation instructions:${NC}"
        echo "   • PM2: npm install -g pm2"
        echo "   • curl: apt install curl (Ubuntu/Debian) or brew install curl (macOS)"
        echo "   • jq: apt install jq (Ubuntu/Debian) or brew install jq (macOS)"
        echo "   • llama.cpp: Build from https://github.com/ggml-org/llama.cpp"
        echo ""
        exit 1
    fi
}

# Find an available port starting from the given port
find_available_port() {
    local start_port="$1"
    local port="$start_port"
    local max_attempts=100
    local attempts=0

    # Validate input port
    if ! validate_port "$start_port"; then
        log_message "ERROR" "Invalid starting port: $start_port"
        return 1
    fi

    while [[ $attempts -lt $max_attempts ]]; do
        # Check if port is valid before testing
        if [[ $port -gt 65535 ]]; then
            log_message "ERROR" "Port range exceeded while searching for available port"
            return 1
        fi

        if ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
        ((port++))
        ((attempts++))
    done

    log_message "ERROR" "Could not find available port after $max_attempts attempts"
    return 1
}

# Wait for a service to become healthy
wait_for_health() {
    local url="$1"
    local timeout="$2"
    local count=0

    echo "Waiting for service to start..." >&2

    while [[ $count -lt $timeout ]]; do
        if curl -s "$url" >/dev/null 2>&1; then
            return 0
        fi

        echo -n "." >&2
        sleep 1
        ((count++))
    done

    echo "" >&2
    return 1
}

# Log message with timestamp
# Note: All output goes to stderr to avoid interfering with function return values
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "${GREEN}[$timestamp] INFO: $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] WARN: $message${NC}" >&2
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] ERROR: $message${NC}" >&2
            ;;
        *)
            echo "[$timestamp] $level: $message" >&2
            ;;
    esac

    # Also log to file
    echo "[$timestamp] $level: $message" >> "$LOGS_DIR/runner.log"
}

# Validate model ID format
validate_model_id() {
    local model_id="$1"

    if [[ ! "$model_id" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        return 1
    fi

    return 0
}

# Get model filename from HuggingFace model ID
get_model_filename() {
    local model_id="$1"
    echo "${model_id//\//_}.gguf"
}

# Get full model path
get_model_path() {
    local model_id="$1"
    local filename=$(get_model_filename "$model_id")
    echo "$MODELS_DIR/$filename"
}

# Check if model file exists locally
model_exists_locally() {
    local model_id="$1"
    local model_path=$(get_model_path "$model_id")
    [[ -f "$model_path" ]]
}

# Get file size in human readable format
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        du -h "$file" | cut -f1
    else
        echo "N/A"
    fi
}



# Check if PM2 process exists
pm2_process_exists() {
    local instance_name="$1"
    pm2 describe "$instance_name" &>/dev/null
}

# Get PM2 process status
get_pm2_process_status() {
    local instance_name="$1"
    pm2 describe "$instance_name" 2>/dev/null | jq -r '.[0].pm2_env.status' 2>/dev/null || echo "not found"
}


# Check available disk space in GB for models directory
check_disk_space() {
    local required_gb="${1:-5}"

    local available_gb=$(df -BG "$MODELS_DIR" 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
    if [[ -z "$available_gb" ]] || [[ ! "$available_gb" =~ ^[0-9]+$ ]]; then
        log_message "WARN" "Could not determine available disk space"
        return 1
    fi

    if [[ $available_gb -lt $required_gb ]]; then
        log_message "ERROR" "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        return 1
    fi

    log_message "INFO" "Disk space check passed: ${available_gb}GB available"
    return 0
}

# Detect llama.cpp server binary
detect_llama_server() {
    if command -v llama-server &> /dev/null; then
        echo "llama-server"
    elif command -v llama-cpp-server &> /dev/null; then
        echo "llama-cpp-server"
    elif command -v server &> /dev/null; then
        echo "server"
    else
        log_message "ERROR" "No llama.cpp server binary found"
        return 1
    fi
}

# Get optimal thread count
get_optimal_threads() {
    local cpu_cores=$(nproc)
    local optimal_threads=$((cpu_cores > 4 ? cpu_cores - 1 : cpu_cores))
    echo "$optimal_threads"
}

# Validate port number
validate_port() {
    local port="$1"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1024 ]] || [[ $port -gt 65535 ]]; then
        return 1
    fi

    return 0
}

# Generate random string for temp files
generate_random_string() {
    local length="${1:-8}"
    tr -dc A-Za-z0-9 </dev/urandom | head -c "$length"
}

