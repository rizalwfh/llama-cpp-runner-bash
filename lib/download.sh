#!/bin/bash

# HuggingFace model download utilities for Llama.cpp Runner

# Validate environment before proceeding
if [[ -z "${MODELS_DIR:-}" ]] || [[ -z "${LOGS_DIR:-}" ]]; then
    echo "❌ ERROR: Required environment variables not set in download.sh" >&2
    echo "💡 MODELS_DIR and LOGS_DIR must be exported from main script" >&2
    return 1 2>/dev/null || exit 1
fi

# Validate HuggingFace model and find compatible files
validate_and_find_model_files() {
    local model_id="$1"
    local api_url="https://huggingface.co/api/models/$model_id"
    local hf_url="https://huggingface.co/$model_id"

    log_message "INFO" "Validating model existence on HuggingFace..."

    # Get API response and check status
    local api_response
    local api_status
    api_response=$(curl -s -w "\n%{http_code}" "$api_url" 2>/dev/null)
    api_status=$(echo "$api_response" | tail -n1)

    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "DEBUG" "API URL: $api_url"
        log_message "DEBUG" "HTTP Status: $api_status"
    fi

    # Check if we got a successful response (200 or 2xx)
    if [[ ! "$api_status" =~ ^2[0-9][0-9]$ ]]; then
        log_message "ERROR" "Model not found or not accessible on HuggingFace: $model_id (HTTP $api_status)"
        log_message "INFO" "You can verify the model exists at: $hf_url"
        return 1
    fi

    # Extract the JSON response and find GGUF files
    local model_data=$(echo "$api_response" | head -n -1)
    local files_info=$(echo "$model_data" | jq -r '.siblings[]? | select(.rfilename | test("\\.(gguf|bin)$"; "i")) | .rfilename' 2>/dev/null)

    if [[ -z "$files_info" ]]; then
        log_message "WARN" "No GGUF/bin files found in API response, analyzing all files..."

        local all_files=$(echo "$model_data" | jq -r '.siblings[]? | .rfilename' 2>/dev/null)

        # Try different patterns to find GGUF files
        files_info=$(echo "$all_files" | grep -i -E '\.(gguf|bin)$' | head -10)

        if [[ -z "$files_info" ]]; then
            files_info=$(echo "$all_files" | grep -i -E '(q4_0|q4_k_m|f16|q8_0).*\.gguf$' | head -5)
        fi

        if [[ -z "$files_info" ]]; then
            log_message "WARN" "Still no GGUF files found, trying common patterns..."
            local base_name=$(echo "$model_id" | sed 's/.*\///')
            local common_patterns=(
                "${base_name}.gguf"
                "model.gguf"
                "ggml-model-q4_0.gguf"
                "ggml-model-q4_k_m.gguf"
                "${base_name}-q4_0.gguf"
                "${base_name}-f16.gguf"
                "pytorch_model.bin"
            )

            for pattern in "${common_patterns[@]}"; do
                files_info="$pattern"
                break
            done
        fi
    fi

    if [[ -z "$files_info" ]]; then
        log_message "ERROR" "No suitable model files found for: $model_id"
        return 1
    fi

    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "DEBUG" "Found GGUF files:"
        echo "$files_info" >&2
    fi

    echo "$files_info"
    return 0
}

# Download model from HuggingFace
download_model() {
    local model_id="$1"
    local model_filename=$(get_model_filename "$model_id")
    local model_path=$(get_model_path "$model_id")

    # Check if model already exists
    if model_exists_locally "$model_id"; then
        local file_size=$(get_file_size "$model_path")
        log_message "INFO" "Model already exists locally: $model_path ($file_size)"
        echo "$model_path"
        return 0
    fi

    # Check available disk space (require at least 5GB)
    if ! check_disk_space 5; then
        log_message "ERROR" "Insufficient disk space for model download"
        return 1
    fi

    log_message "INFO" "Downloading model: $model_id"

    # Validate model and find available files
    local files_info
    if ! files_info=$(validate_and_find_model_files "$model_id"); then
        return 1
    fi

    # Select the best GGUF file (prefer Q4_0 or Q4_K_M for good balance of size/quality)
    local selected_file
    selected_file=$(select_best_model_file "$files_info")

    if [[ -z "$selected_file" ]]; then
        log_message "ERROR" "No suitable model files found for: $model_id"
        return 1
    fi

    log_message "INFO" "Selected model file: $selected_file"

    # Download the model file
    local download_url="https://huggingface.co/$model_id/resolve/main/$selected_file"
    local temp_path="/tmp/$(generate_random_string)_$model_filename"

    log_message "INFO" "Downloading from: $download_url"

    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "DEBUG" "Download URL: $download_url"
        log_message "DEBUG" "Temporary path: $temp_path"
        log_message "DEBUG" "Final path: $model_path"
    fi

    # Download with progress and resume capability
    if ! download_with_progress "$download_url" "$temp_path"; then
        log_message "ERROR" "Failed to download model"
        rm -f "$temp_path"
        return 1
    fi

    # Verify the download
    if [[ ! -f "$temp_path" ]] || [[ ! -s "$temp_path" ]]; then
        log_message "ERROR" "Downloaded file is empty or missing"
        rm -f "$temp_path"
        return 1
    fi

    # Basic integrity check - ensure file is at least 1MB (reasonable minimum for GGUF)
    local file_size_bytes=$(stat -c%s "$temp_path" 2>/dev/null || echo "0")
    if [[ $file_size_bytes -lt 1048576 ]]; then
        log_message "ERROR" "Downloaded file appears corrupted or incomplete: ${file_size_bytes} bytes"
        rm -f "$temp_path"
        return 1
    fi

    # Move to final location
    if ! mv "$temp_path" "$model_path"; then
        log_message "ERROR" "Failed to move model to final location"
        rm -f "$temp_path"
        return 1
    fi

    local final_size=$(get_file_size "$model_path")
    log_message "INFO" "Model downloaded successfully: $model_path ($final_size)"

    echo "$model_path"
}

# Select the best model file from available options
select_best_model_file() {
    local files_info="$1"
    local selected_file

    # First try to find a good quantization level (Q4_0 or Q4_K_M)
    selected_file=$(echo "$files_info" | grep -i -E '(q4_0|q4_k_m)' | head -n 1)

    # If no Q4 files, try other common quantizations
    if [[ -z "$selected_file" ]]; then
        selected_file=$(echo "$files_info" | grep -i -E '(q8_0|f16)' | head -n 1)
    fi

    # Finally, just take the first available GGUF file
    if [[ -z "$selected_file" ]]; then
        selected_file=$(echo "$files_info" | head -n 1)
    fi

    echo "$selected_file"
}

# Download file with progress bar and resume support
download_with_progress() {
    local url="$1"
    local output_path="$2"
    local max_retries=3
    local retry_count=0

    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "DEBUG" "Starting download with progress"
        log_message "DEBUG" "URL: $url"
        log_message "DEBUG" "Output: $output_path"
    fi

    while [[ $retry_count -lt $max_retries ]]; do
        log_message "INFO" "Download attempt $((retry_count + 1))/$max_retries"

        # Use curl with resume support and progress bar
        local curl_exit_code=0
        if curl -L \
            --progress-bar \
            --continue-at - \
            --max-time 3600 \
            --retry 3 \
            --retry-delay 5 \
            --output "$output_path" \
            "$url" || curl_exit_code=$?; then

            if [[ "${DEBUG:-0}" == "1" ]]; then
                log_message "DEBUG" "Download completed successfully"
                if [[ -f "$output_path" ]]; then
                    local file_size=$(stat -c%s "$output_path" 2>/dev/null || echo "0")
                    log_message "DEBUG" "Downloaded file size: $file_size bytes"
                fi
            fi
            return 0
        fi

        if [[ "${DEBUG:-0}" == "1" ]]; then
            log_message "DEBUG" "Download failed with exit code: $curl_exit_code"
        fi

        ((retry_count++))
        if [[ $retry_count -lt $max_retries ]]; then
            log_message "WARN" "Download failed, retrying in 10 seconds..."
            sleep 10
        fi
    done

    log_message "ERROR" "Download failed after $max_retries attempts"
    return 1
}






# List locally downloaded models
list_local_models() {
    echo -e "${BLUE}📦 Local Models:${NC}"
    echo ""

    if [[ ! -d "$MODELS_DIR" ]] || [[ -z "$(ls -A "$MODELS_DIR" 2>/dev/null)" ]]; then
        echo "No models found in $MODELS_DIR"
        return 0
    fi

    local total_size=0

    while IFS= read -r -d '' model_file; do
        local filename=$(basename "$model_file")
        local model_id=$(echo "$filename" | sed 's/_/\//' | sed 's/\.gguf$//')
        local size=$(get_file_size "$model_file")
        local size_bytes=$(stat -c%s "$model_file" 2>/dev/null || echo "0")

        total_size=$((total_size + size_bytes))

        echo "   • $model_id"
        echo "     File: $filename"
        echo "     Size: $size"
        echo "     Path: $model_file"
        echo ""
    done < <(find "$MODELS_DIR" -name "*.gguf" -print0)

    local total_size_human=$(echo "$total_size" | awk '{
        if ($1 > 1024*1024*1024)
            printf "%.1fGB", $1/1024/1024/1024
        else if ($1 > 1024*1024)
            printf "%.1fMB", $1/1024/1024
        else if ($1 > 1024)
            printf "%.1fKB", $1/1024
        else
            printf "%dB", $1
    }')

    echo "Total size: $total_size_human"
}

# Remove local model
remove_local_model() {
    local model_id="$1"
    local model_path=$(get_model_path "$model_id")

    if [[ ! -f "$model_path" ]]; then
        log_message "WARN" "Model not found locally: $model_id"
        return 1
    fi

    local size=$(get_file_size "$model_path")

    read -p "Remove model $model_id ($size)? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$model_path"
        log_message "INFO" "Model removed: $model_id"
    else
        log_message "INFO" "Model removal cancelled"
    fi
}