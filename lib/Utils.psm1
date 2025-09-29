# Utility functions for Llama.cpp Runner PowerShell version

# Color constants
$Global:Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Cyan"
    Default = "White"
}

# Global script variables
$Script:ScriptDir = $null
$Script:ModelsDir = $null
$Script:LogsDir = $null
$Script:ConfigDir = $null
$Script:PM2ConfigDir = $null

function Initialize-Environment {
    <#
    .SYNOPSIS
    Initialize environment variables and directories for the PowerShell runner

    .PARAMETER ScriptDirectory
    Root directory of the script
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptDirectory
    )

    try {
        $Script:ScriptDir = $ScriptDirectory
        $Script:ModelsDir = Join-Path $ScriptDirectory "models"
        $Script:LogsDir = Join-Path $ScriptDirectory "logs"
        $Script:ConfigDir = Join-Path $ScriptDirectory "config"
        $Script:PM2ConfigDir = Join-Path $ConfigDir "pm2"

        # Create directories if they don't exist
        $dirsToCreate = @($Script:ModelsDir, $Script:LogsDir, $Script:ConfigDir, $Script:PM2ConfigDir)
        foreach ($dir in $dirsToCreate) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        Write-LogMessage -Level "INFO" -Message "Environment initialized successfully"
        return $true
    }
    catch {
        Write-Host "❌ ERROR: Failed to initialize environment: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-Dependencies {
    <#
    .SYNOPSIS
    Check if required dependencies are installed
    #>
    [CmdletBinding()]
    param()

    $missingDeps = @()

    # Check for PM2
    if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
        $missingDeps += "pm2"
    }

    # Check for curl
    if (-not (Get-Command curl -ErrorAction SilentlyContinue)) {
        $missingDeps += "curl"
    }

    # Check for jq (for JSON processing)
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        $missingDeps += "jq"
    }

    # Check for llama-server or llama-cpp-server
    $llamaServer = Get-Command llama-server -ErrorAction SilentlyContinue
    $llamaCppServer = Get-Command llama-cpp-server -ErrorAction SilentlyContinue
    if (-not $llamaServer -and -not $llamaCppServer) {
        $missingDeps += "llama-server or llama-cpp-server"
    }

    if ($missingDeps.Count -gt 0) {
        Write-Host "❌ Missing dependencies:" -ForegroundColor $Global:Colors.Red
        foreach ($dep in $missingDeps) {
            Write-Host "   • $dep" -ForegroundColor $Global:Colors.Red
        }
        Write-Host ""
        Write-Host "📝 Installation instructions:" -ForegroundColor $Global:Colors.Yellow
        Write-Host "   • PM2: npm install -g pm2" -ForegroundColor $Global:Colors.Yellow
        Write-Host "   • curl: Install from https://curl.se/ or use PowerShell's Invoke-WebRequest" -ForegroundColor $Global:Colors.Yellow
        Write-Host "   • jq: Download from https://stedolan.github.io/jq/ or use winget install stedolan.jq" -ForegroundColor $Global:Colors.Yellow
        Write-Host "   • llama.cpp: Build from https://github.com/ggml-org/llama.cpp" -ForegroundColor $Global:Colors.Yellow
        return $false
    }

    return $true
}

function Find-AvailablePort {
    <#
    .SYNOPSIS
    Find an available port starting from the given port

    .PARAMETER StartPort
    The starting port to check from

    .PARAMETER MaxAttempts
    Maximum number of ports to check
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$StartPort,

        [Parameter()]
        [int]$MaxAttempts = 100
    )

    if (-not (Test-PortNumber -Port $StartPort)) {
        Write-LogMessage -Level "ERROR" -Message "Invalid starting port: $StartPort"
        return $null
    }

    $port = $StartPort
    $attempts = 0

    while ($attempts -lt $MaxAttempts) {
        if ($port -gt 65535) {
            Write-LogMessage -Level "ERROR" -Message "Port range exceeded while searching for available port"
            return $null
        }

        $tcpConnections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if (-not $tcpConnections) {
            return $port
        }

        $port++
        $attempts++
    }

    Write-LogMessage -Level "ERROR" -Message "Could not find available port after $MaxAttempts attempts"
    return $null
}

function Wait-ForHealth {
    <#
    .SYNOPSIS
    Wait for a service to become healthy

    .PARAMETER Url
    The health check URL

    .PARAMETER TimeoutSeconds
    Maximum time to wait in seconds
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    Write-Host "Waiting for service to start..." -ForegroundColor $Global:Colors.Blue

    $count = 0
    while ($count -lt $TimeoutSeconds) {
        try {
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-Host ""
                return $true
            }
        }
        catch {
            # Service not ready yet
        }

        Write-Host "." -NoNewline -ForegroundColor $Global:Colors.Blue
        Start-Sleep -Seconds 1
        $count++
    }

    Write-Host ""
    return $false
}

function Write-LogMessage {
    <#
    .SYNOPSIS
    Log message with timestamp and color coding

    .PARAMETER Level
    Log level (INFO, WARN, ERROR)

    .PARAMETER Message
    Message to log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Level`: $Message"

    # Color coding for console output
    $color = switch ($Level) {
        "INFO" { $Global:Colors.Green }
        "WARN" { $Global:Colors.Yellow }
        "ERROR" { $Global:Colors.Red }
        "DEBUG" { $Global:Colors.Blue }
        default { $Global:Colors.Default }
    }

    Write-Host $logEntry -ForegroundColor $color

    # Also log to file if LogsDir is set
    if ($Script:LogsDir) {
        $logFile = Join-Path $Script:LogsDir "runner.log"
        Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    }
}

function Test-ModelId {
    <#
    .SYNOPSIS
    Validate model ID format

    .PARAMETER ModelId
    HuggingFace model ID to validate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId
    )

    return $ModelId -match '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$'
}

function Get-ModelFilename {
    <#
    .SYNOPSIS
    Get model filename from HuggingFace model ID

    .PARAMETER ModelId
    HuggingFace model ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId
    )

    return ($ModelId -replace '/', '_') + ".gguf"
}

function Get-ModelPath {
    <#
    .SYNOPSIS
    Get full model path

    .PARAMETER ModelId
    HuggingFace model ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId
    )

    $filename = Get-ModelFilename -ModelId $ModelId
    return Join-Path $Script:ModelsDir $filename
}

function Test-ModelExistsLocally {
    <#
    .SYNOPSIS
    Check if model file exists locally

    .PARAMETER ModelId
    HuggingFace model ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId
    )

    $modelPath = Get-ModelPath -ModelId $ModelId
    return Test-Path $modelPath
}

function Get-FileSize {
    <#
    .SYNOPSIS
    Get file size in human readable format

    .PARAMETER FilePath
    Path to the file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (Test-Path $FilePath) {
        $file = Get-Item $FilePath
        $size = $file.Length

        if ($size -gt 1GB) {
            return "{0:N1}GB" -f ($size / 1GB)
        }
        elseif ($size -gt 1MB) {
            return "{0:N1}MB" -f ($size / 1MB)
        }
        elseif ($size -gt 1KB) {
            return "{0:N1}KB" -f ($size / 1KB)
        }
        else {
            return "${size}B"
        }
    }

    return "N/A"
}

function Test-PM2ProcessExists {
    <#
    .SYNOPSIS
    Check if PM2 process exists

    .PARAMETER InstanceName
    Name of the PM2 instance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )

    try {
        $result = & pm2 describe $InstanceName 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Get-PM2ProcessStatus {
    <#
    .SYNOPSIS
    Get PM2 process status

    .PARAMETER InstanceName
    Name of the PM2 instance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )

    try {
        $result = & pm2 jlist 2>$null | ConvertFrom-Json
        $process = $result | Where-Object { $_.name -eq $InstanceName }
        if ($process) {
            return $process.pm2_env.status
        }
        return "not found"
    }
    catch {
        return "not found"
    }
}

function Test-DiskSpace {
    <#
    .SYNOPSIS
    Check available disk space

    .PARAMETER RequiredGB
    Required disk space in GB
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$RequiredGB = 5
    )

    try {
        $drive = Get-Item $Script:ModelsDir | ForEach-Object { $_.PSDrive }
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 1)

        if ($freeSpaceGB -lt $RequiredGB) {
            Write-LogMessage -Level "ERROR" -Message "Insufficient disk space: ${freeSpaceGB}GB available, ${RequiredGB}GB required"
            return $false
        }

        Write-LogMessage -Level "INFO" -Message "Disk space check passed: ${freeSpaceGB}GB available"
        return $true
    }
    catch {
        Write-LogMessage -Level "WARN" -Message "Could not determine available disk space"
        return $false
    }
}

function Find-LlamaServer {
    <#
    .SYNOPSIS
    Detect llama.cpp server binary
    #>
    [CmdletBinding()]
    param()

    $serverCommands = @("llama-server", "llama-cpp-server", "server")

    foreach ($cmd in $serverCommands) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            return $cmd
        }
    }

    Write-LogMessage -Level "ERROR" -Message "No llama.cpp server binary found"
    return $null
}

function Get-OptimalThreads {
    <#
    .SYNOPSIS
    Get optimal thread count
    #>
    [CmdletBinding()]
    param()

    $cpuCores = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
    $optimalThreads = if ($cpuCores -gt 4) { $cpuCores - 1 } else { $cpuCores }
    return $optimalThreads
}

function Test-PortNumber {
    <#
    .SYNOPSIS
    Validate port number

    .PARAMETER Port
    Port number to validate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    return ($Port -ge 1024 -and $Port -le 65535)
}

function New-RandomString {
    <#
    .SYNOPSIS
    Generate random string for temp files

    .PARAMETER Length
    Length of the random string
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Length = 8
    )

    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    $random = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $random += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $random
}

# Export all functions
Export-ModuleMember -Function *