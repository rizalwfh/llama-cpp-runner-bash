# PM2 configuration generator for Llama.cpp Runner PowerShell version

# Import required utilities
Import-Module (Join-Path $PSScriptRoot "Utils.psm1") -Force

function New-PM2Config {
    <#
    .SYNOPSIS
    Generate PM2 ecosystem configuration

    .PARAMETER InstanceName
    Name of the PM2 instance

    .PARAMETER ModelPath
    Path to the model file

    .PARAMETER Port
    Port number for the server

    .PARAMETER ContextSize
    Context size for completion models

    .PARAMETER Threads
    Number of threads to use

    .PARAMETER ModelType
    Type of model (completion, embedding, reranking)

    .PARAMETER PoolingStrategy
    Pooling strategy for embedding models

    .PARAMETER MicrobatchSize
    Microbatch size for embedding models
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,

        [Parameter(Mandatory = $true)]
        [string]$ModelPath,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter()]
        [int]$ContextSize = 2048,

        [Parameter()]
        [int]$Threads = 4,

        [Parameter()]
        [ValidateSet("completion", "embedding", "reranking")]
        [string]$ModelType = "completion",

        [Parameter()]
        [ValidateSet("cls", "mean", "none")]
        [string]$PoolingStrategy = "",

        [Parameter()]
        [int]$MicrobatchSize = 0
    )

    # Get the PM2 config directory
    $configDir = $Script:PM2ConfigDir
    if (-not $configDir) {
        $configDir = Join-Path $PSScriptRoot "../config/pm2"
    }

    $configFile = Join-Path $configDir "ecosystem-$InstanceName.config.js"
    $serverBinary = Find-LlamaServer

    if (-not $serverBinary) {
        Write-LogMessage -Level "ERROR" -Message "Could not detect llama.cpp server binary"
        return $null
    }

    Write-LogMessage -Level "INFO" -Message "Generating PM2 config: $configFile"
    Write-LogMessage -Level "INFO" -Message "Using server binary: $serverBinary"

    # Get the script directory and logs directory
    $scriptDir = $Script:ScriptDir
    $logsDir = $Script:LogsDir
    if (-not $scriptDir) {
        $scriptDir = Split-Path $PSScriptRoot -Parent
    }
    if (-not $logsDir) {
        $logsDir = Join-Path $scriptDir "logs"
    }

    # Build args array based on model type
    $argsArray = @(
        "'-m', '$ModelPath'",
        "'--port', '$Port'",
        "'--host', '0.0.0.0'",
        "'--threads', '$Threads'"
    )

    # Add model-type specific arguments
    switch ($ModelType) {
        "embedding" {
            $argsArray += "'--embedding'"
            if ($PoolingStrategy) {
                $argsArray += "'--pooling', '$PoolingStrategy'"
            }
            if ($MicrobatchSize -gt 0) {
                $argsArray += "'-ub', '$MicrobatchSize'"
            }
        }
        "reranking" {
            $argsArray += "'--reranking'"
        }
        "completion" {
            $argsArray += @(
                "'--ctx-size', '$ContextSize'",
                "'--n-predict', '-1'",
                "'--temp', '0.7'",
                "'--repeat-penalty', '1.1'",
                "'--batch-size', '512'",
                "'--keep', '-1'"
            )
        }
    }

    # Add common arguments
    $argsArray += @(
        "'--mlock'",
        "'--no-mmap'"
    )

    # Convert paths to use forward slashes for cross-platform compatibility
    $modelPathJs = $ModelPath -replace '\\', '/'
    $scriptDirJs = $scriptDir -replace '\\', '/'
    $logsDirJs = $logsDir -replace '\\', '/'

    # Create the JavaScript configuration content
    $configContent = @"
module.exports = {
  apps: [
    {
      name: '$InstanceName',
      script: '$serverBinary',
      args: [
        $($argsArray -join ",`n        ")
      ],
      cwd: '$scriptDirJs',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '2G',
      env: {
        NODE_ENV: 'production',
        LLAMA_SERVER_PORT: '$Port',
        LLAMA_SERVER_HOST: '0.0.0.0',
        LLAMA_MODEL_TYPE: '$ModelType'
      },
      error_file: '$logsDirJs/${InstanceName}-error.log',
      out_file: '$logsDirJs/${InstanceName}-out.log',
      log_file: '$logsDirJs/${InstanceName}-combined.log',
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
"@

    try {
        # Ensure the config directory exists
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        # Write the configuration file
        Set-Content -Path $configFile -Value $configContent -Encoding UTF8

        Write-LogMessage -Level "INFO" -Message "PM2 configuration generated successfully"
        return $configFile
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to generate PM2 configuration: $($_.Exception.Message)"
        return $null
    }
}

function Test-PM2Config {
    <#
    .SYNOPSIS
    Validate a PM2 configuration file

    .PARAMETER ConfigFile
    Path to the PM2 configuration file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFile
    )

    if (-not (Test-Path $ConfigFile)) {
        Write-LogMessage -Level "ERROR" -Message "PM2 configuration file not found: $ConfigFile"
        return $false
    }

    try {
        # Try to parse the JavaScript file by converting it to a testable format
        $content = Get-Content $ConfigFile -Raw

        # Basic validation - check for required fields
        $requiredFields = @(
            "name:",
            "script:",
            "args:",
            "cwd:",
            "instances:",
            "exec_mode:"
        )

        foreach ($field in $requiredFields) {
            if ($content -notmatch [regex]::Escape($field)) {
                Write-LogMessage -Level "ERROR" -Message "PM2 config missing required field: $field"
                return $false
            }
        }

        Write-LogMessage -Level "INFO" -Message "PM2 configuration validation passed"
        return $true
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to validate PM2 configuration: $($_.Exception.Message)"
        return $false
    }
}

function Get-PM2ConfigInfo {
    <#
    .SYNOPSIS
    Extract information from a PM2 configuration file

    .PARAMETER ConfigFile
    Path to the PM2 configuration file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFile
    )

    if (-not (Test-Path $ConfigFile)) {
        return $null
    }

    try {
        $content = Get-Content $ConfigFile -Raw

        # Extract key information using regex
        $info = @{}

        # Extract name
        if ($content -match "name:\s*'([^']+)'") {
            $info.Name = $Matches[1]
        }

        # Extract port
        if ($content -match "'--port',\s*'(\d+)'") {
            $info.Port = [int]$Matches[1]
        }

        # Extract model path
        if ($content -match "'-m',\s*'([^']+)'") {
            $info.ModelPath = $Matches[1]
        }

        # Extract model type
        if ($content -match "LLAMA_MODEL_TYPE:\s*'([^']+)'") {
            $info.ModelType = $Matches[1]
        }

        # Extract threads
        if ($content -match "'--threads',\s*'(\d+)'") {
            $info.Threads = [int]$Matches[1]
        }

        # Extract context size (for completion models)
        if ($content -match "'--ctx-size',\s*'(\d+)'") {
            $info.ContextSize = [int]$Matches[1]
        }

        return $info
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to parse PM2 configuration: $($_.Exception.Message)"
        return $null
    }
}

function Remove-PM2Config {
    <#
    .SYNOPSIS
    Remove PM2 configuration file

    .PARAMETER InstanceName
    Name of the PM2 instance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )

    $configDir = $Script:PM2ConfigDir
    if (-not $configDir) {
        $configDir = Join-Path $PSScriptRoot "../config/pm2"
    }

    $configFile = Join-Path $configDir "ecosystem-$InstanceName.config.js"

    if (Test-Path $configFile) {
        try {
            Remove-Item -Path $configFile -Force
            Write-LogMessage -Level "INFO" -Message "PM2 configuration removed: $configFile"
            return $true
        }
        catch {
            Write-LogMessage -Level "ERROR" -Message "Failed to remove PM2 configuration: $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-LogMessage -Level "WARN" -Message "PM2 configuration file not found: $configFile"
        return $false
    }
}

function Get-PM2Configs {
    <#
    .SYNOPSIS
    List all PM2 configuration files
    #>
    [CmdletBinding()]
    param()

    $configDir = $Script:PM2ConfigDir
    if (-not $configDir) {
        $configDir = Join-Path $PSScriptRoot "../config/pm2"
    }

    if (-not (Test-Path $configDir)) {
        return @()
    }

    try {
        $configFiles = Get-ChildItem $configDir -Filter "ecosystem-*.config.js"
        $configs = @()

        foreach ($file in $configFiles) {
            $info = Get-PM2ConfigInfo -ConfigFile $file.FullName
            if ($info) {
                $info.ConfigFile = $file.FullName
                $configs += $info
            }
        }

        return $configs
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to list PM2 configurations: $($_.Exception.Message)"
        return @()
    }
}

# Export all functions
Export-ModuleMember -Function *