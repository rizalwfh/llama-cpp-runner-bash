#!/bin/bash

# PM2 configuration generator for Llama.cpp Runner

# Validate environment before proceeding
if [[ -z "${SCRIPT_DIR:-}" ]] || [[ -z "${LOGS_DIR:-}" ]] || [[ -z "${PM2_CONFIG_DIR:-}" ]]; then
    echo "❌ ERROR: Required environment variables not set in pm2-config.sh" >&2
    echo "💡 SCRIPT_DIR, LOGS_DIR, and PM2_CONFIG_DIR must be exported from main script" >&2
    return 1 2>/dev/null || exit 1
fi

# Generate PM2 ecosystem configuration
generate_pm2_config() {
    local instance_name="$1"
    local model_path="$2"
    local port="$3"
    local context_size="$4"
    local threads="$5"
    local model_type="${6:-completion}"
    local pooling_strategy="${7:-}"
    local microbatch_size="${8:-}"

    local config_file="$PM2_CONFIG_DIR/ecosystem-$instance_name.config.js"
    local server_binary=$(detect_llama_server)

    if [[ -z "$server_binary" ]]; then
        log_message "ERROR" "Could not detect llama.cpp server binary"
        return 1
    fi

    log_message "INFO" "Generating PM2 config: $config_file"
    log_message "INFO" "Using server binary: $server_binary"

    # Build args array based on model type
    local args_array="[
        '-m', '$model_path',
        '--port', '$port',
        '--host', '0.0.0.0',
        '--threads', '$threads',"

    # Add model-type specific arguments
    if [[ "$model_type" == "embedding" ]]; then
        args_array="$args_array
        '--embedding',"
        if [[ -n "$pooling_strategy" ]]; then
            args_array="$args_array
        '--pooling', '$pooling_strategy',"
        fi
        if [[ -n "$microbatch_size" ]]; then
            args_array="$args_array
        '-ub', '$microbatch_size',"
        fi
    elif [[ "$model_type" == "reranking" ]]; then
        args_array="$args_array
        '--reranking',"
    elif [[ "$model_type" == "completion" ]]; then
        args_array="$args_array
        '--ctx-size', '$context_size',
        '--n-predict', '-1',
        '--temp', '0.7',
        '--repeat-penalty', '1.1',
        '--batch-size', '512',
        '--keep', '-1',"
    fi

    # Add common arguments
    args_array="$args_array
        '--mlock',
        '--no-mmap'
      ]"

    # Create PM2 ecosystem configuration
    cat > "$config_file" << EOF
module.exports = {
  apps: [
    {
      name: '$instance_name',
      script: '$server_binary',
      args: $args_array,
      cwd: '$SCRIPT_DIR',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '2G',
      env: {
        NODE_ENV: 'production',
        LLAMA_SERVER_PORT: '$port',
        LLAMA_SERVER_HOST: '0.0.0.0',
        LLAMA_MODEL_TYPE: '$model_type'
      },
      error_file: '$LOGS_DIR/${instance_name}-error.log',
      out_file: '$LOGS_DIR/${instance_name}-out.log',
      log_file: '$LOGS_DIR/${instance_name}-combined.log',
      time: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      kill_timeout: 5000,
      wait_ready: true,
      listen_timeout: 10000,
      instance_var: 'INSTANCE_ID'
    }
  ]
};
EOF

    log_message "INFO" "PM2 configuration generated successfully"
    echo "$config_file"
}









