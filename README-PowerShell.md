# 🦙 Llama.cpp Runner with PM2 - PowerShell Version

A production-ready PowerShell-based runner for serving large language models from HuggingFace using llama.cpp and PM2 process management. This is the PowerShell equivalent of the original Bash script with enhanced Windows compatibility and PowerShell-native features.

## ✨ Features

- 🚀 **Cross-Platform**: Works on Windows, Linux, and macOS with PowerShell 5.1+
- 📦 **HuggingFace Integration**: Automatic model download with resume capability and smart file selection
- 🔄 **PM2 Process Management**: Production-ready process management with auto-restart and memory limits
- 🎛️ **Instance Lifecycle Management**: Built-in start/stop/restart/delete commands with health checks
- 💾 **GGUF Model Support**: Optimized for GGUF quantized models with intelligent selection
- 🔍 **Health Monitoring**: Built-in health checks, startup validation, and monitoring
- 📊 **Enhanced Progress**: PowerShell-native progress indicators and colored output
- ⚙️ **Configurable**: Flexible configuration with parameter validation
- 🏗️ **Port Management**: Automatic port allocation with conflict detection
- 🛡️ **Error Recovery**: Robust error handling with cleanup and detailed troubleshooting
- 🐛 **Debug Mode**: Detailed debug output with `$env:DEBUG=1`
- 💾 **Disk Management**: Space validation and automatic cleanup

## 📋 Prerequisites

### Required Dependencies

```powershell
# Install PM2 (Node.js process manager)
npm install -g pm2

# Install PowerShell (if not already installed)
# Windows: Pre-installed on Windows 10/11
# Linux/macOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell

# Verify installations
pm2 --version
$PSVersionTable.PSVersion
```

### System Dependencies

**Windows:**
```powershell
# Using Chocolatey
choco install curl jq

# Using winget
winget install curl
winget install stedolan.jq

# Or download manually:
# curl: https://curl.se/windows/
# jq: https://stedolan.github.io/jq/download/
```

**Linux/macOS:**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install curl jq

# macOS
brew install curl jq
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
# Windows: Add to PATH environment variable
# Linux/macOS: sudo cp llama-server /usr/local/bin/
```

## 🚀 Quick Start

1. **Clone or download this runner**:
   ```powershell
   git clone https://github.com/rizalwfh/llama-cpp-runner-bash.git llama-cpp-runner
   cd llama-cpp-runner
   ```

2. **Run the interactive setup**:
   ```powershell
   .\Runner.ps1
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
   ```powershell
   .\Runner.ps1 -List                                 # List all instances
   .\Runner.ps1 -Action stop -InstanceName my-instance     # Stop an instance
   .\Runner.ps1 -Action start -InstanceName my-instance    # Start an instance
   .\Runner.ps1 -Action delete -InstanceName my-instance   # Delete an instance
   ```

## 📖 Usage

### Interactive Mode (Recommended)

```powershell
.\Runner.ps1
```

### Command Line Options

#### Information & Utilities
```powershell
# Show help
.\Runner.ps1 -Help

# List running PM2 processes
.\Runner.ps1 -List

# Show detailed status
.\Runner.ps1 -Status

# Clean up old models and logs
.\Runner.ps1 -Cleanup

# Enable debug mode for troubleshooting
$env:DEBUG=1; .\Runner.ps1
```

#### Instance Management
```powershell
# Start a stopped instance
.\Runner.ps1 -Action start -InstanceName <instance-name>

# Stop a running instance
.\Runner.ps1 -Action stop -InstanceName <instance-name>

# Restart an instance
.\Runner.ps1 -Action restart -InstanceName <instance-name>

# Delete an instance (with confirmation)
.\Runner.ps1 -Action delete -InstanceName <instance-name>
```

**Examples:**
```powershell
# Start the 'phi3-mini' instance
.\Runner.ps1 -Action start -InstanceName phi3-mini

# Stop the 'gemma-7b' instance
.\Runner.ps1 -Action stop -InstanceName gemma-7b

# Restart the 'mistral' instance with health check
.\Runner.ps1 -Action restart -InstanceName mistral

# Delete the 'old-model' instance and cleanup files
.\Runner.ps1 -Action delete -InstanceName old-model
```

## 🆕 PowerShell-Specific Features

### Enhanced Parameter Validation
```powershell
# PowerShell provides built-in parameter validation
# Invalid parameters will show helpful error messages
.\Runner.ps1 -Action invalid    # Shows valid options
```

### Advanced Error Handling
```powershell
# PowerShell's try/catch provides detailed error information
# Automatic cleanup on script termination
# Graceful handling of Ctrl+C interruption
```

### Native Progress Indicators
```powershell
# Built-in progress bars for downloads
# Colored output for better readability
# Structured logging with timestamps
```

### Cross-Platform Compatibility
```powershell
# Works on Windows PowerShell 5.1 and PowerShell Core 6+
# Automatic path handling for different operating systems
# Native PowerShell modules with proper manifest files
```

## 🔧 Configuration

### Default Settings

- **Port**: 8080 (auto-incremented if busy)
- **Context Size**: 2048 tokens (range: 512-32768)
- **Threads**: 4 (or optimal based on CPU cores)
- **Temperature**: 0.7
- **Batch Size**: 512
- **Memory Limit**: 2GB (PM2 restart threshold)
- **Model Selection**: Prefers Q4_0 or Q4_K_M quantization

### PowerShell Module Structure

```
lib/
├── Utils.psm1          # Core utilities module
├── Utils.psd1          # Module manifest
├── Download.psm1       # HuggingFace download module
├── Download.psd1       # Module manifest
├── PM2Config.psm1      # PM2 configuration module
└── PM2Config.psd1      # Module manifest
```

## 🛠️ PowerShell Module Development

### Importing Modules Manually
```powershell
# Import individual modules for development
Import-Module .\lib\Utils.psm1 -Force
Import-Module .\lib\Download.psm1 -Force
Import-Module .\lib\PM2Config.psm1 -Force

# Get available functions
Get-Command -Module Utils
```

### Module Functions
```powershell
# Utils Module
Initialize-Environment -ScriptDirectory $PWD
Test-Dependencies
Find-AvailablePort -StartPort 8080
Write-LogMessage -Level "INFO" -Message "Test message"

# Download Module
Invoke-ModelDownload -ModelId "microsoft/Phi-3-mini-4k-instruct" -ModelType "completion"
Get-LocalModels

# PM2Config Module
New-PM2Config -InstanceName "test" -ModelPath "path/to/model.gguf" -Port 8080
Get-PM2Configs
```

## 🔧 Troubleshooting

### PowerShell-Specific Issues

1. **Execution Policy**:
   ```powershell
   # Check current execution policy
   Get-ExecutionPolicy

   # Set execution policy (run as Administrator)
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Module Import Issues**:
   ```powershell
   # Force reload modules
   Remove-Module Utils, Download, PM2Config -ErrorAction SilentlyContinue
   Import-Module .\lib\Utils.psm1 -Force
   ```

3. **Path Issues on Windows**:
   ```powershell
   # Use PowerShell-native path handling
   $modelPath = Join-Path $PWD "models\model.gguf"
   # Script automatically handles path separators
   ```

4. **PowerShell Version Compatibility**:
   ```powershell
   # Check PowerShell version
   $PSVersionTable.PSVersion

   # Script requires PowerShell 5.1 or higher
   # Compatible with both Windows PowerShell and PowerShell Core
   ```

### Common Issues (Same as Bash Version)

1. **Model not found**: Verify HuggingFace model ID format
2. **Download failures**: Check internet connectivity and disk space
3. **Port conflicts**: Script automatically finds available ports
4. **Dependency issues**: Ensure PM2, curl, jq, and llama-server are installed
5. **Memory issues**: PM2 restarts processes exceeding 2GB memory

### Debug Mode
```powershell
# Enable verbose logging and detailed tracing
$env:DEBUG=1; .\Runner.ps1

# Debug output includes:
# - API validation responses
# - Download progress details
# - File operation traces
# - Function call validation
# - Environment variable checks
```

## 🚦 Compatibility with Bash Version

The PowerShell version maintains 100% compatibility with the Bash version:

- **Same Configuration Files**: Uses identical PM2 ecosystem configurations
- **Same Directory Structure**: Maintains the same models/, logs/, and config/ directories
- **Same API Endpoints**: Produces identical server configurations
- **Same Command Interface**: Equivalent command-line options and functionality

You can switch between Bash and PowerShell versions seamlessly:

```bash
# Using Bash version
./runner.sh --list

# Using PowerShell version (equivalent)
.\Runner.ps1 -List
```

## 🤝 Contributing

Contributions are welcome! The PowerShell version follows the same patterns as the Bash version while leveraging PowerShell-specific features.

### Development Setup

```powershell
# Make sure script can execute
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Test the script with debug mode
$env:DEBUG=1; .\Runner.ps1 -Help
```

## 📄 License

This project is licensed under the MIT License. See LICENSE file for details.

## 🙏 Acknowledgments

- [llama.cpp](https://github.com/ggml-org/llama.cpp) - Fast LLM inference in C/C++
- [PM2](https://github.com/Unitech/pm2) - Production process manager for Node.js
- [HuggingFace](https://huggingface.co/) - Model repository and hosting
- [PowerShell](https://github.com/PowerShell/PowerShell) - Cross-platform automation framework

## 📧 Support

For PowerShell-specific support:
1. Check the PowerShell troubleshooting section above
2. Verify PowerShell version compatibility
3. Ensure execution policy allows script execution
4. Create an issue with PowerShell version information

---

**Happy model serving with PowerShell! 🦙✨**