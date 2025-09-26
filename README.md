# 🦙 Llama.cpp Runner with PM2

A production-ready bash-based runner for serving large language models from HuggingFace using llama.cpp and PM2 process management.

## ✨ Features

- 🚀 **Easy Setup**: Interactive prompts with comprehensive validation and error recovery
- 📦 **HuggingFace Integration**: Automatic model download with resume capability and smart file selection
- 🔄 **PM2 Process Management**: Production-ready process management with auto-restart and memory limits
- 🎛️ **Instance Lifecycle Management**: Built-in start/stop/restart/delete commands with health checks and validation
- 💾 **GGUF Model Support**: Optimized for GGUF quantized models with intelligent selection (Q4_0, Q4_K_M preferred)
- 🔍 **Health Monitoring**: Built-in health checks, startup validation, and monitoring
- 📊 **Logging**: Comprehensive logging with timestamps and structured output
- ⚙️ **Configurable**: Flexible configuration with validation and sensible defaults
- 🏗️ **Port Management**: Automatic port allocation with conflict detection
- 🛡️ **Error Recovery**: Robust error handling with cleanup and detailed troubleshooting guidance
- 🐛 **Debug Mode**: Detailed debug output and tracing with `DEBUG=1` flag
- 🔄 **Config Migration**: Automatic migration of old PM2 configurations
- 💾 **Disk Management**: Space validation and automatic cleanup of old files

## 📋 Prerequisites

### Required Dependencies

```bash
# Install PM2 (Node.js process manager)
npm install -g pm2

# Install system dependencies (Ubuntu/Debian)
sudo apt update
sudo apt install curl jq

# Install system dependencies (macOS)
brew install curl jq

# Verify installations
pm2 --version
curl --version
jq --version
```

### llama.cpp Installation

You need to have llama.cpp built and available in your system PATH:

```bash
# Clone and build llama.cpp
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

# Build for CPU
make

# Build with CUDA support (optional)
make LLAMA_CUDA=1

# Build with OpenCL support (optional)
make LLAMA_OPENCL=1

# Make sure the binary is in your PATH
sudo cp llama-server /usr/local/bin/
```

## 🚀 Quick Start

1. **Clone or download this runner**:
   ```bash
   git clone https://github.com/rizalwfh/llama-cpp-runner-bash.git llama-cpp-runner
   cd llama-cpp-runner
   ```

2. **Run the interactive setup**:
   ```bash
   ./runner.sh
   ```

3. **Follow the prompts**:
   - Enter HuggingFace model ID (e.g., `microsoft/Phi-3-mini-4k-instruct`)
   - Specify PM2 instance name (alphanumeric, hyphens, underscores only)
   - Configure optional settings (port: 8080+, context size: 512-32768, threads: 1-CPU cores)

4. **Access your model**:
   - API: `http://localhost:8080` (or your configured port)
   - Health check: `http://localhost:8080/health`
   - Web UI: `http://localhost:8080` (built-in web interface)

5. **Manage your instances**:
   ```bash
   ./runner.sh --list              # List all instances
   ./runner.sh --stop my-instance  # Stop an instance
   ./runner.sh --start my-instance # Start an instance
   ./runner.sh --delete my-instance # Delete an instance
   ```

## 📖 Usage

### Interactive Mode (Recommended)

```bash
./runner.sh
```

### Common Workflows

#### Daily Instance Management
```bash
# Check what's running
./runner.sh --list

# Stop instances to free resources
./runner.sh --stop large-model
./runner.sh --stop phi3-mini

# Start only what you need
./runner.sh --start gemma-2b

# Restart if having issues
./runner.sh --restart gemma-2b
```

#### Cleanup and Maintenance
```bash
# Remove unused instances
./runner.sh --delete old-model

# Clean up disk space
./runner.sh --cleanup

# Check system status
./runner.sh --status
```

### Command Line Options

#### Information & Utilities
```bash
# Show help
./runner.sh --help

# List running PM2 processes
./runner.sh --list

# Show detailed status
./runner.sh --status

# Clean up old models and logs
./runner.sh --cleanup

# Enable debug mode for troubleshooting
DEBUG=1 ./runner.sh
```

#### Instance Management
```bash
# Start a stopped instance
./runner.sh --start <instance-name>

# Stop a running instance
./runner.sh --stop <instance-name>

# Restart an instance
./runner.sh --restart <instance-name>

# Delete an instance (with confirmation)
./runner.sh --delete <instance-name>
```

**Examples:**
```bash
# Start the 'phi3-mini' instance
./runner.sh --start phi3-mini

# Stop the 'gemma-7b' instance
./runner.sh --stop gemma-7b

# Restart the 'mistral' instance with health check
./runner.sh --restart mistral

# Delete the 'old-model' instance and cleanup files
./runner.sh --delete old-model
```

## 🔧 Configuration

### Default Settings

- **Port**: 8080 (auto-incremented if busy)
- **Context Size**: 2048 tokens (range: 512-32768)
- **Threads**: 4 (or optimal based on CPU cores)
- **Temperature**: 0.7
- **Batch Size**: 512
- **Memory Limit**: 2GB (PM2 restart threshold)
- **Model Selection**: Prefers Q4_0 or Q4_K_M quantization for best size/quality balance

### Custom Configuration

During interactive setup, you can customize:
- Server port
- Context window size
- Number of processing threads
- Model-specific parameters

## 📦 Supported Models

### Popular GGUF Models

#### 🔥 Small Models (< 4GB)
- `microsoft/DialoGPT-medium` - Conversational model
- `microsoft/DialoGPT-small` - Lightweight chat model
- `HuggingFaceTB/SmolLM-135M-Instruct` - Very small instruction model

#### 🚀 Medium Models (4-8GB)
- `microsoft/Phi-3-mini-4k-instruct` - Efficient 3.8B parameter model
- `google/gemma-2b-it` - Gemma 2B instruction-tuned
- `microsoft/Phi-3-mini-128k-instruct` - Extended context version

#### 💪 Large Models (8GB+)
- `microsoft/Phi-3-medium-4k-instruct` - 14B parameter model
- `google/gemma-7b-it` - Gemma 7B instruction-tuned
- `mistralai/Mistral-7B-Instruct-v0.3` - Latest Mistral instruct

**Note**:
- All models are automatically validated against HuggingFace API
- Script intelligently selects best available GGUF files (Q4_0, Q4_K_M preferred)
- Requires 5GB+ free disk space for downloads
- Models with resume support if download is interrupted

## 🛠️ Instance Management

### Using runner.sh (Recommended)

The runner script provides enhanced instance management with health checks, validation, and better error messages:

```bash
# List all instances with status
./runner.sh --list

# Start an instance (with health check)
./runner.sh --start <instance-name>

# Stop an instance safely
./runner.sh --stop <instance-name>

# Restart with health validation
./runner.sh --restart <instance-name>

# Delete instance and cleanup files
./runner.sh --delete <instance-name>

# View detailed status
./runner.sh --status
```

**Benefits of using runner.sh commands:**
- ✅ **Health checks** after start/restart operations
- ✅ **Instance validation** before operations
- ✅ **Smart error messages** and troubleshooting tips
- ✅ **Safe deletion** with confirmation prompts
- ✅ **Automatic cleanup** of configuration files and logs
- ✅ **Port discovery** and service URL display

### Direct PM2 Commands

For advanced users who prefer direct PM2 control:

```bash
# List all processes
pm2 list

# View logs for a specific instance
pm2 logs <instance-name>

# Monitor all processes in real-time
pm2 monit

# Save current PM2 process list
pm2 save

# Resurrect saved processes (useful after reboot)
pm2 resurrect

# Start PM2 at system startup
pm2 startup

# View detailed process information
pm2 show <instance-name>
```

## 🏗️ Directory Structure

```
llama-cpp-runner/
├── runner.sh          # Main runner script (496 lines)
├── lib/                     # Library functions
│   ├── utils.sh             # Core utilities, validation, logging (275 lines)
│   ├── download.sh          # HuggingFace download with resume (312 lines)
│   └── pm2-config.sh        # PM2 configuration generator (90 lines)
├── config/
│   └── pm2/                 # PM2 configuration files
│       └── ecosystem-*.config.js  # Generated PM2 configs per instance
├── models/                  # Downloaded GGUF model files
├── logs/                    # Application and PM2 logs
│   ├── runner.log           # Main application log
│   └── *-{error,out,combined}.log # PM2 process logs
└── README.md               # Documentation
```

## 🔍 API Usage

Once your model is running, you can interact with it using the llama.cpp server API:

### Health Check

```bash
curl http://localhost:8080/health
```

### Text Completion

```bash
curl -X POST http://localhost:8080/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain quantum computing in simple terms:",
    "n_predict": 150,
    "temperature": 0.7,
    "repeat_penalty": 1.1,
    "top_k": 40,
    "top_p": 0.9
  }'
```

### Chat Completion

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain the basics of machine learning"}
    ],
    "max_tokens": 200,
    "temperature": 0.7
  }'
```

## 🔧 Troubleshooting

### Model Type Selection Guide

- **Choose Completion** for:
  - Text generation and chat applications
  - Question answering systems
  - Creative writing and content generation
  - General language understanding tasks

- **Choose Embedding** for:
  - Semantic search applications
  - Text similarity and clustering
  - Recommendation systems
  - Information retrieval tasks

- **Choose Reranking** for:
  - Document ranking and retrieval
  - Search result reordering
  - Relevance scoring
  - Information filtering systems

### Common Issues

1. **Model not found**:
   - Verify HuggingFace model ID format: `username/model-name`
   - Ensure model repository has GGUF files or is compatible with llama.cpp
   - Try with `DEBUG=1` to see API validation details

2. **Download failures**:
   - Check internet connectivity
   - Verify sufficient disk space (requires 5GB+ free)
   - Downloads resume automatically on retry
   - Large models may take significant time

3. **Port conflicts**:
   - Script automatically finds available ports
   - Check with: `netstat -tuln | grep <port>`
   - Default starts at 8080, increments if busy

4. **Dependency issues**:
   - PM2: `npm install -g pm2`
   - Missing `llama-server` binary from llama.cpp build
   - Required: `curl`, `jq`, `netstat`

5. **Memory issues**:
   - PM2 restarts processes exceeding 2GB memory
   - Use smaller quantized models (Q4_0, Q4_K_M)
   - Monitor with: `pm2 monit`

6. **Instance management issues**:
   - Use `./runner.sh --list` to see all available instances
   - Instance not found: Check the exact name with `./runner.sh --list`
   - Health check fails: Wait a few seconds and try `./runner.sh --restart <instance>`
   - Can't start instance: Check if another process is using the port
   - Delete confirmation not working: Make sure to type `y` (lowercase) to confirm

### Debug Mode

```bash
# Enable verbose logging and detailed tracing
DEBUG=1 ./runner.sh

# Debug output includes:
# - API validation responses
# - Download progress details
# - File operation traces
# - Function call validation
# - Environment variable checks

# Check PM2 logs for runtime issues
pm2 logs <instance-name>
# Or use the runner for better error context
./runner.sh --list

# Monitor system resources in real-time
pm2 monit
```

### Log Locations

- **Runner logs**: `logs/runner.log` - Main application events and errors
- **PM2 instance logs**:
  - `logs/<instance-name>-error.log` - Error output
  - `logs/<instance-name>-out.log` - Standard output
  - `logs/<instance-name>-combined.log` - Combined logs
- **PM2 system logs**: `~/.pm2/logs/` - PM2 daemon logs
- **Temporary files**: `/tmp/*_*.gguf` - Cleaned automatically after 30 minutes

## 🚦 Health Monitoring

The runner includes comprehensive health monitoring:

- **Startup Validation**: 30-second health check after service start
- **Automatic Restarts**: PM2 automatically restarts crashed processes
- **Memory Limits**: Processes restart if memory usage exceeds 2GB
- **Health Endpoints**: `/health` endpoint for external monitoring
- **Log Rotation**: Automatic cleanup of logs >100MB and models >30 days old
- **Port Conflict Detection**: Automatic port allocation to avoid conflicts
- **Disk Space Monitoring**: Pre-download validation requires 5GB+ free space
- **Process Monitoring**: Real-time monitoring via `pm2 monit`

## 🔎 Model Selection Algorithm

The runner uses intelligent model file selection:

### **Selection Priority**:
1. **Q4_0 Quantization**: Best balance of size and quality
2. **Q4_K_M Quantization**: Mixed precision, good performance
3. **Q8_0/F16**: Higher quality, larger size
4. **First Available**: Fallback to any compatible GGUF file

### **Validation Process**:
1. Query HuggingFace API for model metadata
2. Search for GGUF files using multiple patterns
3. Validate file accessibility and download URLs
4. Select optimal quantization based on preferences
5. Download with resume support and integrity checks

### **Model Type Compatibility**:
- **Completion Models**: Standard language models for text generation
- **Embedding Models**: Models trained for text representation (sentence-transformers, BGE, GTE)
- **Reranking Models**: Cross-encoder models for document ranking

### **File Naming Convention**:
- Downloaded files: `{username}_{model-name}.gguf`
- Temporary files: `/tmp/{random}_{model}.gguf`
- Cleanup: Automatic removal after 30 minutes

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

### Development Setup

```bash
# Make scripts executable
chmod +x runner.sh
chmod +x lib/*.sh

# Test the script with debug mode
DEBUG=1 ./runner.sh --help
```

## 📄 License

This project is licensed under the MIT License. See LICENSE file for details.

## 🙏 Acknowledgments

- [llama.cpp](https://github.com/ggml-org/llama.cpp) - Fast LLM inference in C/C++
- [PM2](https://github.com/Unitech/pm2) - Production process manager for Node.js
- [HuggingFace](https://huggingface.co/) - Model repository and hosting

## 📧 Support

For support, please:
1. Check the troubleshooting section above
2. Search existing issues in the repository
3. Create a new issue with detailed information about your problem

---

**Happy model serving! 🦙✨**