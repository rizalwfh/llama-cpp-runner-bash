#Requires -Version 5.1

<#
.SYNOPSIS
    Llama.cpp Runner with PM2 Integration - PowerShell Version

.DESCRIPTION
    This script downloads models from HuggingFace and serves them using llama.cpp with PM2 process management.
    PowerShell version of the original Bash script with enhanced error handling and Windows compatibility.

.PARAMETER Action
    Action to perform (start, stop, restart, delete, list, status, cleanup, help)

.PARAMETER InstanceName
    Name of the PM2 instance for instance management commands

.PARAMETER Help
    Show help information

.PARAMETER List
    List running PM2 processes

.PARAMETER Status
    Show detailed status of all instances

.PARAMETER Cleanup
    Clean up old models and logs

.EXAMPLE
    .\Runner.ps1
    Start interactive setup

.EXAMPLE
    .\Runner.ps1 -List
    Show all PM2 processes

.EXAMPLE
    .\Runner.ps1 -Action start -InstanceName my-model
    Start 'my-model' instance

.EXAMPLE
    .\Runner.ps1 -Action stop -InstanceName my-model
    Stop 'my-model' instance

.NOTES
    Author: PowerShell conversion of Llama.cpp Runner
    Requires: PM2, curl, jq, llama-server
#>

[CmdletBinding(DefaultParameterSetName = "Interactive")]
param(
    [Parameter(ParameterSetName = "Action", Mandatory = $true)]
    [ValidateSet("start", "stop", "restart", "delete")]
    [string]$Action,

    [Parameter(ParameterSetName = "Action", Mandatory = $true)]
    [Parameter(ParameterSetName = "Start")]
    [Parameter(ParameterSetName = "Stop")]
    [Parameter(ParameterSetName = "Restart")]
    [Parameter(ParameterSetName = "Delete")]
    [string]$InstanceName,

    [Parameter(ParameterSetName = "Help")]
    [switch]$Help,

    [Parameter(ParameterSetName = "List")]
    [switch]$List,

    [Parameter(ParameterSetName = "Status")]
    [switch]$Status,

    [Parameter(ParameterSetName = "Cleanup")]
    [switch]$Cleanup,

    [Parameter(ParameterSetName = "Start")]
    [switch]$Start,

    [Parameter(ParameterSetName = "Stop")]
    [switch]$Stop,

    [Parameter(ParameterSetName = "Restart")]
    [switch]$Restart,

    [Parameter(ParameterSetName = "Delete")]
    [switch]$Delete
)

# Global configuration
$Script:DefaultPort = 8080
$Script:DefaultContextSize = 2048
$Script:DefaultThreads = 4

# Get script directory
$Script:ScriptDirectory = $PSScriptRoot

# Import modules
$LibPath = Join-Path $Script:ScriptDirectory "lib"
Import-Module (Join-Path $LibPath "Utils.psm1") -Force
Import-Module (Join-Path $LibPath "Download.psm1") -Force
Import-Module (Join-Path $LibPath "PM2Config.psm1") -Force

# Initialize environment
if (-not (Initialize-Environment -ScriptDirectory $Script:ScriptDirectory)) {
    Write-Host "❌ Failed to initialize environment" -ForegroundColor Red
    exit 1
}

# Cleanup function for graceful exit
function Invoke-CleanupOnExit {
    param(
        [string]$InstanceName = "",
        [bool]$ExitWithError = $false
    )

    if ($ExitWithError -and $InstanceName) {
        Write-Host ""
        Write-Host "🧹 Cleaning up failed deployment..." -ForegroundColor Yellow

        # Remove PM2 process if it was created
        try {
            $pm2Ping = & pm2 ping 2>$null
            if ($LASTEXITCODE -eq 0) {
                if (Test-PM2ProcessExists -InstanceName $InstanceName) {
                    Write-Host "Removing PM2 process: $InstanceName"
                    & pm2 delete $InstanceName 2>$null | Out-Null
                }
            }
        }
        catch {
            Write-Host "Warning: Could not remove PM2 process $InstanceName"
        }

        # Remove configuration file if it was created
        $configDir = Join-Path $Script:ScriptDirectory "config\pm2"
        $configFile = Join-Path $configDir "ecosystem-$InstanceName.config.js"
        if (Test-Path $configFile) {
            Write-Host "Removing configuration file: $configFile"
            try {
                Remove-Item -Path $configFile -Force
            }
            catch {
                Write-Host "Warning: Could not remove config file $configFile"
            }
        }

        # Clean up any temporary files
        $tempFiles = Get-ChildItem $env:TEMP -Filter "*_*.gguf" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) }
        foreach ($file in $tempFiles) {
            try {
                Remove-Item $file.FullName -Force
            }
            catch {
                # Ignore cleanup errors
            }
        }

        Write-Host "💡 Cleanup completed. You can run the script again." -ForegroundColor Cyan
        Write-LogMessage -Level "INFO" -Message "Cleanup completed after failed deployment"
    }
}

function Show-Banner {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                  🦙 Llama.cpp Runner with PM2                ║" -ForegroundColor Cyan
    Write-Host "║              Serve HuggingFace Models in Production          ║" -ForegroundColor Cyan
    Write-Host "║                    PowerShell Version                        ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Usage {
    Write-Host "Usage: .\Runner.ps1 [OPTIONS] [INSTANCE_NAME]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Help                Show this help message"
    Write-Host "  -List                List running PM2 processes"
    Write-Host "  -Status              Show detailed status of all instances"
    Write-Host "  -Cleanup             Clean up old models and logs"
    Write-Host ""
    Write-Host "Instance Management:"
    Write-Host "  -Action start -InstanceName <name>     Start a stopped PM2 instance"
    Write-Host "  -Action stop -InstanceName <name>      Stop a running PM2 instance"
    Write-Host "  -Action restart -InstanceName <name>   Restart a PM2 instance"
    Write-Host "  -Action delete -InstanceName <name>    Delete a PM2 instance and its configuration"
    Write-Host ""
    Write-Host "Interactive mode (default): Run without options to start interactive setup"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\Runner.ps1                                    # Start interactive setup"
    Write-Host "  .\Runner.ps1 -List                              # Show all PM2 processes"
    Write-Host "  .\Runner.ps1 -Action start -InstanceName my-model     # Start 'my-model' instance"
    Write-Host "  .\Runner.ps1 -Action stop -InstanceName my-model      # Stop 'my-model' instance"
    Write-Host "  .\Runner.ps1 -Action restart -InstanceName my-model   # Restart 'my-model' instance"
    Write-Host "  .\Runner.ps1 -Action delete -InstanceName my-model    # Delete 'my-model' instance"
}

function Start-InteractiveSetup {
    Show-Banner

    Write-Host "🚀 Welcome to Llama.cpp Runner Setup" -ForegroundColor Yellow
    Write-Host ""

    # Get model ID from user
    do {
        Write-Host "📦 Enter HuggingFace Model ID:" -ForegroundColor Cyan
        Write-Host "   Examples: microsoft/DialoGPT-medium, huggingfaceh4/zephyr-7b-beta"
        Write-Host "   Format: username/model-name"
        Write-Host ""
        $modelId = Read-Host "Model ID"

        if ($modelId -and (Test-ModelId -ModelId $modelId)) {
            break
        }
        else {
            Write-Host "❌ Invalid model ID format. Please use: username/model-name" -ForegroundColor Red
            Write-Host ""
        }
    } while ($true)

    # Get model type from user
    do {
        Write-Host ""
        Write-Host "🤖 Select Model Type:" -ForegroundColor Cyan
        Write-Host "   1) Completion/Chat - For text generation and conversations"
        Write-Host "   2) Embedding - For generating text embeddings/vectors"
        Write-Host "   3) Reranking - For document reranking and relevance scoring"
        Write-Host ""
        $modelTypeChoice = Read-Host "Model type (1-3)"

        switch ($modelTypeChoice) {
            "1" {
                $modelType = "completion"
                break
            }
            "2" {
                $modelType = "embedding"
                break
            }
            "3" {
                $modelType = "reranking"
                break
            }
            default {
                Write-Host "❌ Invalid choice. Please select 1, 2, or 3." -ForegroundColor Red
                continue
            }
        }
        break
    } while ($true)

    # Get PM2 instance name
    do {
        Write-Host ""
        Write-Host "🏷️  Enter PM2 Instance Name:" -ForegroundColor Cyan
        Write-Host "   This will be used to identify your process in PM2"
        Write-Host "   Use alphanumeric characters, hyphens, and underscores only"
        Write-Host ""
        $instanceName = Read-Host "Instance name"

        if ($instanceName -and ($instanceName -match '^[a-zA-Z0-9_-]+$')) {
            # Check if instance already exists
            if (Test-PM2ProcessExists -InstanceName $instanceName) {
                Write-Host "⚠️  Instance '$instanceName' already exists." -ForegroundColor Yellow
                $restartChoice = Read-Host "Do you want to restart it? (y/N)"
                if ($restartChoice -match '^[Yy]$') {
                    & pm2 delete $instanceName 2>$null | Out-Null
                    break
                }
            }
            else {
                break
            }
        }
        else {
            Write-Host "❌ Invalid instance name. Use only alphanumeric characters, hyphens, and underscores." -ForegroundColor Red
        }
    } while ($true)

    # Get embedding-specific configuration
    $poolingStrategy = ""
    $microbatchSize = 0

    if ($modelType -eq "embedding") {
        do {
            Write-Host ""
            Write-Host "🎯 Embedding Configuration:" -ForegroundColor Cyan
            Write-Host "   Pooling Strategy:"
            Write-Host "   • cls - Use [CLS] token (BERT-style)"
            Write-Host "   • mean - Mean of all token embeddings"
            Write-Host "   • none - Return all token embeddings (no pooling)"
            Write-Host ""
            $poolingStrategy = Read-Host "Pooling strategy (cls/mean/none, default: cls)"
            if (-not $poolingStrategy) { $poolingStrategy = "cls" }

            if ($poolingStrategy -match '^(cls|mean|none)$') {
                break
            }
            else {
                Write-Host "❌ Invalid pooling strategy. Use cls, mean, or none." -ForegroundColor Red
            }
        } while ($true)

        do {
            $microbatchInput = Read-Host "Microbatch size (default: 8192)"
            if (-not $microbatchInput) { $microbatchInput = "8192" }

            if ($microbatchInput -match '^\d+$' -and [int]$microbatchInput -ge 1 -and [int]$microbatchInput -le 32768) {
                $microbatchSize = [int]$microbatchInput
                break
            }
            else {
                Write-Host "❌ Invalid microbatch size. Must be between 1-32768." -ForegroundColor Red
            }
        } while ($true)
    }

    # Get optional configuration
    Write-Host ""
    Write-Host "⚙️  Optional Configuration (press Enter for defaults):" -ForegroundColor Cyan

    # Get and validate port
    do {
        $portInput = Read-Host "Port (default: $Script:DefaultPort)"
        if (-not $portInput) { $portInput = $Script:DefaultPort }

        if (Test-PortNumber -Port $portInput) {
            $port = [int]$portInput
            break
        }
        else {
            Write-Host "❌ Invalid port number. Must be between 1024-65535." -ForegroundColor Red
        }
    } while ($true)

    # Get and validate context size
    $contextSize = $Script:DefaultContextSize
    if ($modelType -eq "completion") {
        do {
            $contextInput = Read-Host "Context size (default: $Script:DefaultContextSize)"
            if (-not $contextInput) { $contextInput = $Script:DefaultContextSize }

            if ($contextInput -match '^\d+$' -and [int]$contextInput -ge 512 -and [int]$contextInput -le 32768) {
                $contextSize = [int]$contextInput
                break
            }
            else {
                Write-Host "❌ Invalid context size. Must be between 512-32768." -ForegroundColor Red
            }
        } while ($true)
    }

    # Get and validate thread count
    $maxThreads = Get-OptimalThreads
    do {
        $threadsInput = Read-Host "Number of threads (default: $Script:DefaultThreads, max: $maxThreads)"
        if (-not $threadsInput) { $threadsInput = $Script:DefaultThreads }

        if ($threadsInput -match '^\d+$' -and [int]$threadsInput -ge 1 -and [int]$threadsInput -le $maxThreads) {
            $threads = [int]$threadsInput
            break
        }
        else {
            Write-Host "❌ Invalid thread count. Must be between 1-$maxThreads." -ForegroundColor Red
        }
    } while ($true)

    Write-Host ""
    Write-Host "📋 Configuration Summary:" -ForegroundColor Green
    Write-Host "   Model ID: $modelId"
    Write-Host "   Model Type: $modelType"
    Write-Host "   Instance: $instanceName"
    Write-Host "   Port: $port"
    if ($modelType -eq "embedding") {
        Write-Host "   Pooling Strategy: $poolingStrategy"
        Write-Host "   Microbatch Size: $microbatchSize"
    }
    if ($modelType -eq "completion") {
        Write-Host "   Context Size: $contextSize"
    }
    Write-Host "   Threads: $threads"
    Write-Host ""

    $confirm = Read-Host "Continue with this configuration? (Y/n)"
    if ($confirm -match '^[Nn]$') {
        Write-Host "Setup cancelled." -ForegroundColor Yellow
        return
    }

    # Start the deployment process
    Write-Host ""
    Write-Host "🚀 Starting deployment..." -ForegroundColor Green

    try {
        # Check dependencies with error recovery
        Write-Host "🔍 Checking system dependencies..." -ForegroundColor Yellow
        if (-not (Test-Dependencies)) {
            Write-Host "❌ Dependency check failed" -ForegroundColor Red
            Write-Host "💡 Please install missing dependencies and try again" -ForegroundColor Cyan
            return
        }

        # Download model with error recovery
        Write-Host "📥 Downloading model..." -ForegroundColor Yellow
        $modelPath = Invoke-ModelDownload -ModelId $modelId -ModelType $modelType
        if (-not $modelPath) {
            Write-Host "❌ Failed to download model" -ForegroundColor Red
            Write-Host "💡 Troubleshooting tips:" -ForegroundColor Cyan
            Write-Host "   • Check internet connection"
            Write-Host "   • Verify model ID: $modelId"
            Write-Host "   • Ensure sufficient disk space"
            Write-Host "   • Try running with `$env:DEBUG=1 for more details"
            Invoke-CleanupOnExit -InstanceName $instanceName -ExitWithError $true
            return
        }

        if (-not (Test-Path $modelPath)) {
            Write-Host "❌ Model file not found after download: $modelPath" -ForegroundColor Red
            Invoke-CleanupOnExit -InstanceName $instanceName -ExitWithError $true
            return
        }

        Write-LogMessage -Level "INFO" -Message "Model successfully downloaded: $modelPath"

        # Find available port with fallback
        Write-Host "🔍 Finding available port..." -ForegroundColor Yellow
        $finalPort = Find-AvailablePort -StartPort $port
        if (-not $finalPort) {
            Write-Host "❌ Could not find available port starting from $port" -ForegroundColor Red
            Write-Host "💡 Try using a different port range or free up ports in use" -ForegroundColor Cyan
            Invoke-CleanupOnExit -InstanceName $instanceName -ExitWithError $true
            return
        }
        if ($finalPort -ne $port) {
            Write-Host "⚠️  Port $port is busy, using port $finalPort instead" -ForegroundColor Yellow
            Write-LogMessage -Level "WARN" -Message "Port changed from $port to $finalPort"
        }

        # Generate PM2 configuration with error handling
        Write-Host "⚙️  Generating PM2 configuration..." -ForegroundColor Yellow
        $configFile = New-PM2Config -InstanceName $instanceName -ModelPath $modelPath -Port $finalPort -ContextSize $contextSize -Threads $threads -ModelType $modelType -PoolingStrategy $poolingStrategy -MicrobatchSize $microbatchSize

        if (-not $configFile -or -not (Test-Path $configFile)) {
            Write-Host "❌ Failed to generate PM2 configuration" -ForegroundColor Red
            Invoke-CleanupOnExit -InstanceName $instanceName -ExitWithError $true
            return
        }

        Write-LogMessage -Level "INFO" -Message "PM2 configuration generated: $configFile"

        # Start with PM2 with error handling
        Write-Host "🚀 Starting with PM2..." -ForegroundColor Yellow
        $pm2Result = & pm2 start $configFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to start PM2 process" -ForegroundColor Red
            Write-Host "💡 Troubleshooting:" -ForegroundColor Cyan
            Write-Host "   • Check PM2 logs: pm2 logs $instanceName"
            Write-Host "   • Verify llama-server binary is available"
            Write-Host "   • Check system resources with: pm2 monit"
            Invoke-CleanupOnExit -InstanceName $instanceName -ExitWithError $true
            return
        }

        Write-LogMessage -Level "INFO" -Message "PM2 process started successfully"

        # Wait for startup and health check
        Write-Host "🔍 Performing health check..." -ForegroundColor Yellow
        if (Wait-ForHealth -Url "http://localhost:$finalPort/health" -TimeoutSeconds 30) {
            Write-Host "✅ Service is running successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "🎉 Deployment Complete!" -ForegroundColor Green
            Write-Host ""
            Write-Host "📊 Service Information:" -ForegroundColor Cyan
            Write-Host "   • Instance Name: $instanceName"
            Write-Host "   • Model: $modelId ($modelType)"
            Write-Host "   • Server URL: http://localhost:$finalPort"
            Write-Host "   • Health Check: http://localhost:$finalPort/health"

            if ($modelType -eq "completion") {
                Write-Host "   • API Documentation: http://localhost:$finalPort (web UI)"
                Write-Host "   • Chat Completions: http://localhost:$finalPort/v1/chat/completions"
                Write-Host "   • Text Completions: http://localhost:$finalPort/completion"
            }
            elseif ($modelType -eq "embedding") {
                Write-Host "   • Embeddings (OpenAI): http://localhost:$finalPort/v1/embeddings"
                Write-Host "   • Embeddings (Native): http://localhost:$finalPort/embedding"
            }
            elseif ($modelType -eq "reranking") {
                Write-Host "   • Reranking (OpenAI): http://localhost:$finalPort/v1/rerank"
                Write-Host "   • Reranking (Native): http://localhost:$finalPort/reranking"
            }

            Write-Host ""
            Write-Host "📋 PM2 Management Commands:" -ForegroundColor Cyan
            Write-Host "   • View logs: pm2 logs $instanceName"
            Write-Host "   • Restart: pm2 restart $instanceName"
            Write-Host "   • Stop: pm2 stop $instanceName"
            Write-Host "   • Delete: pm2 delete $instanceName"
            Write-Host "   • Monitor: pm2 monit"
            Write-Host ""
        }
        else {
            Write-Host "❌ Health check failed. Service may not be running properly." -ForegroundColor Red
            Write-Host "💡 Troubleshooting steps:" -ForegroundColor Cyan
            Write-Host "   1. Check PM2 process status: pm2 list"
            Write-Host "   2. View process logs: pm2 logs $instanceName"
            Write-Host "   3. Check if port $finalPort is available"
            Write-Host "   4. Monitor system resources: pm2 monit"
            Write-Host "   5. Try manual start for debugging:"
            Write-Host "      `$env:DEBUG=1; .\Runner.ps1"
            Write-Host ""
            Write-Host "⚠️  The service may still be starting up. You can check its status with:" -ForegroundColor Yellow
            Write-Host "   pm2 list"
            Write-Host "   pm2 logs $instanceName"

            Write-LogMessage -Level "ERROR" -Message "Health check failed for $instanceName on port $finalPort"
            Invoke-CleanupOnExit -InstanceName $instanceName -ExitWithError $true
        }
    }
    catch {
        Write-Host "❌ Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
        Invoke-CleanupOnExit -InstanceName $instanceName -ExitWithError $true
    }
}

function Show-ProcessList {
    Write-Host "📋 PM2 Processes:" -ForegroundColor Cyan
    & pm2 list
}

function Show-DetailedStatus {
    Write-Host "📊 Detailed Status:" -ForegroundColor Cyan
    try {
        & pm2 status 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ PM2 is not running or not accessible" -ForegroundColor Red
            return
        }
        Write-Host ""
        Write-Host "💾 Memory Usage:" -ForegroundColor Cyan
        & pm2 show 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "No detailed process information available"
        }
    }
    catch {
        Write-Host "❌ Failed to get status: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Cleanup {
    Write-Host "🧹 Cleaning up old files..." -ForegroundColor Yellow
    $cleanedItems = 0

    # Remove models older than 30 days
    $modelsDir = Join-Path $Script:ScriptDirectory "models"
    if (Test-Path $modelsDir) {
        $oldModels = Get-ChildItem $modelsDir -Filter "*.gguf" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
        $oldModelCount = $oldModels.Count
        $oldModels | Remove-Item -Force -ErrorAction SilentlyContinue
        if ($oldModelCount -gt 0) {
            Write-Host "  • Removed $oldModelCount old model files"
            $cleanedItems += $oldModelCount
        }
    }

    # Rotate logs
    $logsDir = Join-Path $Script:ScriptDirectory "logs"
    if (Test-Path $logsDir) {
        $largeLogs = Get-ChildItem $logsDir -Filter "*.log" |
            Where-Object { $_.Length -gt 100MB }
        $largeLogCount = $largeLogs.Count
        foreach ($log in $largeLogs) {
            try {
                # Truncate large logs to 50MB
                $content = Get-Content $log.FullName -Tail 1000
                Set-Content $log.FullName -Value $content
            }
            catch {
                # Ignore truncation errors
            }
        }
        if ($largeLogCount -gt 0) {
            Write-Host "  • Truncated $largeLogCount large log files"
            $cleanedItems += $largeLogCount
        }
    }

    # Clean PM2 logs if PM2 is available
    try {
        $pm2Ping = & pm2 ping 2>$null
        if ($LASTEXITCODE -eq 0) {
            & pm2 flush 2>$null | Out-Null
            Write-Host "  • Flushed PM2 logs"
        }
    }
    catch {
        # PM2 not available or failed
    }

    # Clean temporary download files
    $tempFiles = Get-ChildItem $env:TEMP -Filter "*_*.gguf" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) }
    $tempFileCount = $tempFiles.Count
    $tempFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    if ($tempFileCount -gt 0) {
        Write-Host "  • Removed $tempFileCount temporary files"
        $cleanedItems += $tempFileCount
    }

    if ($cleanedItems -eq 0) {
        Write-Host "  • No files needed cleanup"
    }

    Write-Host "✅ Cleanup completed" -ForegroundColor Green
}

function Start-Instance {
    param([string]$InstanceName)

    if (-not $InstanceName) {
        Write-Host "❌ Instance name is required" -ForegroundColor Red
        Write-Host "Usage: .\Runner.ps1 -Action start -InstanceName <instance-name>"
        return
    }

    # Check if instance exists
    if (-not (Test-PM2ProcessExists -InstanceName $InstanceName)) {
        Write-Host "❌ Instance '$InstanceName' not found" -ForegroundColor Red
        Write-Host "💡 Use '.\Runner.ps1 -List' to see available instances" -ForegroundColor Cyan
        return
    }

    # Get current status
    $currentStatus = Get-PM2ProcessStatus -InstanceName $InstanceName

    if ($currentStatus -eq "online") {
        Write-Host "⚠️  Instance '$InstanceName' is already running" -ForegroundColor Yellow
        return
    }

    Write-Host "🚀 Starting instance: $InstanceName" -ForegroundColor Yellow

    $result = & pm2 start $InstanceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to start instance: $InstanceName" -ForegroundColor Red
        Write-Host "💡 Check logs with: pm2 logs $InstanceName" -ForegroundColor Cyan
        return
    }

    # Get port from PM2 configuration
    $configDir = Join-Path $Script:ScriptDirectory "config\pm2"
    $configFile = Join-Path $configDir "ecosystem-$InstanceName.config.js"
    $port = $null

    if (Test-Path $configFile) {
        $configContent = Get-Content $configFile -Raw
        if ($configContent -match "'--port',\s*'(\d+)'") {
            $port = $Matches[1]
        }
    }

    if ($port) {
        Write-Host "🔍 Performing health check..." -ForegroundColor Yellow
        if (Wait-ForHealth -Url "http://localhost:$port/health" -TimeoutSeconds 30) {
            Write-Host "✅ Instance '$InstanceName' started successfully!" -ForegroundColor Green
            Write-Host "📊 Service URL: http://localhost:$port" -ForegroundColor Cyan
        }
        else {
            Write-Host "⚠️  Instance started but health check failed" -ForegroundColor Yellow
            Write-Host "💡 Check logs with: pm2 logs $InstanceName" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "✅ Instance '$InstanceName' started" -ForegroundColor Green
        Write-Host "💡 Check status with: pm2 list" -ForegroundColor Cyan
    }
}

function Stop-Instance {
    param([string]$InstanceName)

    if (-not $InstanceName) {
        Write-Host "❌ Instance name is required" -ForegroundColor Red
        Write-Host "Usage: .\Runner.ps1 -Action stop -InstanceName <instance-name>"
        return
    }

    # Check if instance exists
    if (-not (Test-PM2ProcessExists -InstanceName $InstanceName)) {
        Write-Host "❌ Instance '$InstanceName' not found" -ForegroundColor Red
        Write-Host "💡 Use '.\Runner.ps1 -List' to see available instances" -ForegroundColor Cyan
        return
    }

    # Get current status
    $currentStatus = Get-PM2ProcessStatus -InstanceName $InstanceName

    if ($currentStatus -eq "stopped") {
        Write-Host "⚠️  Instance '$InstanceName' is already stopped" -ForegroundColor Yellow
        return
    }

    Write-Host "🛑 Stopping instance: $InstanceName" -ForegroundColor Yellow

    $result = & pm2 stop $InstanceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to stop instance: $InstanceName" -ForegroundColor Red
        return
    }

    Write-Host "✅ Instance '$InstanceName' stopped successfully" -ForegroundColor Green
    Write-LogMessage -Level "INFO" -Message "Instance stopped: $InstanceName"
}

function Restart-Instance {
    param([string]$InstanceName)

    if (-not $InstanceName) {
        Write-Host "❌ Instance name is required" -ForegroundColor Red
        Write-Host "Usage: .\Runner.ps1 -Action restart -InstanceName <instance-name>"
        return
    }

    # Check if instance exists
    if (-not (Test-PM2ProcessExists -InstanceName $InstanceName)) {
        Write-Host "❌ Instance '$InstanceName' not found" -ForegroundColor Red
        Write-Host "💡 Use '.\Runner.ps1 -List' to see available instances" -ForegroundColor Cyan
        return
    }

    Write-Host "🔄 Restarting instance: $InstanceName" -ForegroundColor Yellow

    $result = & pm2 restart $InstanceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to restart instance: $InstanceName" -ForegroundColor Red
        Write-Host "💡 Check logs with: pm2 logs $InstanceName" -ForegroundColor Cyan
        return
    }

    # Get port from PM2 configuration
    $configDir = Join-Path $Script:ScriptDirectory "config\pm2"
    $configFile = Join-Path $configDir "ecosystem-$InstanceName.config.js"
    $port = $null

    if (Test-Path $configFile) {
        $configContent = Get-Content $configFile -Raw
        if ($configContent -match "'--port',\s*'(\d+)'") {
            $port = $Matches[1]
        }
    }

    if ($port) {
        Write-Host "🔍 Performing health check..." -ForegroundColor Yellow
        if (Wait-ForHealth -Url "http://localhost:$port/health" -TimeoutSeconds 30) {
            Write-Host "✅ Instance '$InstanceName' restarted successfully!" -ForegroundColor Green
            Write-Host "📊 Service URL: http://localhost:$port" -ForegroundColor Cyan
        }
        else {
            Write-Host "⚠️  Instance restarted but health check failed" -ForegroundColor Yellow
            Write-Host "💡 Check logs with: pm2 logs $InstanceName" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "✅ Instance '$InstanceName' restarted" -ForegroundColor Green
        Write-Host "💡 Check status with: pm2 list" -ForegroundColor Cyan
    }

    Write-LogMessage -Level "INFO" -Message "Instance restarted: $InstanceName"
}

function Remove-Instance {
    param([string]$InstanceName)

    if (-not $InstanceName) {
        Write-Host "❌ Instance name is required" -ForegroundColor Red
        Write-Host "Usage: .\Runner.ps1 -Action delete -InstanceName <instance-name>"
        return
    }

    # Check if instance exists
    if (-not (Test-PM2ProcessExists -InstanceName $InstanceName)) {
        Write-Host "❌ Instance '$InstanceName' not found" -ForegroundColor Red
        Write-Host "💡 Use '.\Runner.ps1 -List' to see available instances" -ForegroundColor Cyan
        return
    }

    Write-Host "🗑️  Deleting instance: $InstanceName" -ForegroundColor Yellow
    Write-Host "⚠️  This will permanently remove the PM2 process and configuration" -ForegroundColor Yellow

    $confirm = Read-Host "Are you sure you want to delete '$InstanceName'? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Operation cancelled" -ForegroundColor Cyan
        return
    }

    # Stop and delete PM2 process
    $result = & pm2 delete $InstanceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to delete PM2 process: $InstanceName" -ForegroundColor Red
        return
    }

    # Remove configuration file
    $configDir = Join-Path $Script:ScriptDirectory "config\pm2"
    $configFile = Join-Path $configDir "ecosystem-$InstanceName.config.js"
    if (Test-Path $configFile) {
        Write-Host "🗑️  Removing configuration file..." -ForegroundColor Yellow
        Remove-Item -Path $configFile -Force -ErrorAction SilentlyContinue
    }

    # Clean up instance-specific logs
    $logsDir = Join-Path $Script:ScriptDirectory "logs"
    $logFiles = @(
        "$InstanceName-error.log",
        "$InstanceName-out.log",
        "$InstanceName-combined.log"
    )

    foreach ($logFile in $logFiles) {
        $logPath = Join-Path $logsDir $logFile
        if (Test-Path $logPath) {
            Write-Host "🗑️  Removing log file: $logFile" -ForegroundColor Yellow
            Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Ask about model file cleanup
    Write-Host ""
    Write-Host "📦 Model files cleanup:" -ForegroundColor Cyan
    Write-Host "⚠️  Do you want to remove model files? This will delete downloaded model files that may be used by other instances." -ForegroundColor Yellow
    $removeModels = Read-Host "Remove model files? (y/N)"

    if ($removeModels -match '^[Yy]$') {
        Write-Host "🗑️  Cleaning up old model files..." -ForegroundColor Yellow
        $modelsDir = Join-Path $Script:ScriptDirectory "models"
        $oldModels = Get-ChildItem $modelsDir -Filter "*.gguf" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) }
        $oldModels | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "✅ Model cleanup completed" -ForegroundColor Green
    }

    Write-Host "✅ Instance '$InstanceName' deleted successfully" -ForegroundColor Green
    Write-LogMessage -Level "INFO" -Message "Instance deleted: $InstanceName"
}

# Main execution logic
try {
    if ($Help) {
        Show-Usage
    }
    elseif ($List) {
        Show-ProcessList
    }
    elseif ($Status) {
        Show-DetailedStatus
    }
    elseif ($Cleanup) {
        Invoke-Cleanup
    }
    elseif ($Action) {
        switch ($Action) {
            "start" { Start-Instance -InstanceName $InstanceName }
            "stop" { Stop-Instance -InstanceName $InstanceName }
            "restart" { Restart-Instance -InstanceName $InstanceName }
            "delete" { Remove-Instance -InstanceName $InstanceName }
        }
    }
    elseif ($Start) {
        Start-Instance -InstanceName $InstanceName
    }
    elseif ($Stop) {
        Stop-Instance -InstanceName $InstanceName
    }
    elseif ($Restart) {
        Restart-Instance -InstanceName $InstanceName
    }
    elseif ($Delete) {
        Remove-Instance -InstanceName $InstanceName
    }
    else {
        # Default to interactive mode
        Start-InteractiveSetup
    }
}
catch {
    Write-Host "❌ An error occurred: $($_.Exception.Message)" -ForegroundColor Red
    Write-LogMessage -Level "ERROR" -Message "Script error: $($_.Exception.Message)"

    if ($InstanceName) {
        Invoke-CleanupOnExit -InstanceName $InstanceName -ExitWithError $true
    }
}