# HuggingFace model download utilities for Llama.cpp Runner PowerShell version

# Import required utilities
Import-Module (Join-Path $PSScriptRoot "Utils.psm1") -Force

function Test-ModelTypeCompatibility {
    <#
    .SYNOPSIS
    Validate model type compatibility

    .PARAMETER ModelId
    HuggingFace model ID

    .PARAMETER IntendedType
    Intended model type (completion, embedding, reranking)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("completion", "embedding", "reranking")]
        [string]$IntendedType
    )

    # Common patterns for different model types
    $embeddingPatterns = @(
        "sentence-transformers",
        "all-MiniLM",
        "all-mpnet",
        "bge-.*-en",
        "gte-",
        "e5-",
        "instructor",
        "embed"
    )

    $rerankingPatterns = @(
        "rerank",
        "cross-encoder",
        "bge-reranker",
        "ms-marco"
    )

    $completionPatterns = @(
        "instruct",
        "chat",
        "llama",
        "phi",
        "gemma",
        "mistral",
        "qwen",
        "deepseek"
    )

    switch ($IntendedType) {
        "embedding" {
            $matched = $embeddingPatterns | Where-Object { $ModelId -match $_ }
            if ($matched) {
                Write-LogMessage -Level "INFO" -Message "Model appears to be an embedding model (pattern match)"
            } else {
                Write-LogMessage -Level "WARN" -Message "Model may not be optimized for embeddings. Common embedding models include sentence-transformers, BGE, GTE, E5 series."
            }
        }
        "reranking" {
            $matched = $rerankingPatterns | Where-Object { $ModelId -match $_ }
            if ($matched) {
                Write-LogMessage -Level "INFO" -Message "Model appears to be a reranking model (pattern match)"
            } else {
                Write-LogMessage -Level "WARN" -Message "Model may not be optimized for reranking. Look for models with 'reranker' or 'cross-encoder' in the name."
            }
        }
        "completion" {
            $matched = $completionPatterns | Where-Object { $ModelId -match $_ }
            if ($matched) {
                Write-LogMessage -Level "INFO" -Message "Model appears to be a completion/chat model (pattern match)"
            } else {
                Write-LogMessage -Level "WARN" -Message "Model may not be optimized for text completion. Look for models with 'instruct', 'chat', or language model names."
            }
        }
    }

    return $true
}

function Find-ModelFiles {
    <#
    .SYNOPSIS
    Validate HuggingFace model and find compatible files

    .PARAMETER ModelId
    HuggingFace model ID

    .PARAMETER ModelType
    Model type (completion, embedding, reranking)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId,

        [Parameter()]
        [ValidateSet("completion", "embedding", "reranking")]
        [string]$ModelType = "completion"
    )

    $apiUrl = "https://huggingface.co/api/models/$ModelId"
    $hfUrl = "https://huggingface.co/$ModelId"

    Write-LogMessage -Level "INFO" -Message "Validating model existence on HuggingFace..."

    # Validate model type compatibility
    Test-ModelTypeCompatibility -ModelId $ModelId -IntendedType $ModelType | Out-Null

    try {
        # Get API response
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 30

        if ($env:DEBUG -eq "1") {
            Write-LogMessage -Level "DEBUG" -Message "API URL: $apiUrl"
            Write-LogMessage -Level "DEBUG" -Message "API response received successfully"
        }

        # Find GGUF files
        $filesInfo = $response.siblings | Where-Object {
            $_.rfilename -match '\.(gguf|bin)$'
        } | Select-Object -ExpandProperty rfilename

        if (-not $filesInfo) {
            Write-LogMessage -Level "WARN" -Message "No GGUF/bin files found in API response, analyzing all files..."

            # Try different patterns to find GGUF files
            $allFiles = $response.siblings | Select-Object -ExpandProperty rfilename
            $filesInfo = $allFiles | Where-Object { $_ -match '\.(gguf|bin)$' } | Select-Object -First 10

            if (-not $filesInfo) {
                $filesInfo = $allFiles | Where-Object { $_ -match '(q4_0|q4_k_m|f16|q8_0).*\.gguf$' } | Select-Object -First 5
            }

            if (-not $filesInfo) {
                Write-LogMessage -Level "WARN" -Message "Still no GGUF files found, trying common patterns..."
                $baseName = ($ModelId -split '/')[-1]
                $commonPatterns = @(
                    "$baseName.gguf",
                    "model.gguf",
                    "ggml-model-q4_0.gguf",
                    "ggml-model-q4_k_m.gguf",
                    "$baseName-q4_0.gguf",
                    "$baseName-f16.gguf",
                    "pytorch_model.bin"
                )

                $filesInfo = $commonPatterns | Select-Object -First 1
            }
        }

        if (-not $filesInfo) {
            Write-LogMessage -Level "ERROR" -Message "No suitable model files found for: $ModelId"
            return $null
        }

        if ($env:DEBUG -eq "1") {
            Write-LogMessage -Level "DEBUG" -Message "Found GGUF files:"
            $filesInfo | ForEach-Object { Write-LogMessage -Level "DEBUG" -Message "  $_" }
        }

        return $filesInfo
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Model not found or not accessible on HuggingFace: $ModelId"
        Write-LogMessage -Level "INFO" -Message "You can verify the model exists at: $hfUrl"
        Write-LogMessage -Level "ERROR" -Message "Error details: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-ModelDownload {
    <#
    .SYNOPSIS
    Download model from HuggingFace

    .PARAMETER ModelId
    HuggingFace model ID

    .PARAMETER ModelType
    Model type (completion, embedding, reranking)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId,

        [Parameter()]
        [ValidateSet("completion", "embedding", "reranking")]
        [string]$ModelType = "completion"
    )

    $modelFilename = Get-ModelFilename -ModelId $ModelId
    $modelPath = Get-ModelPath -ModelId $ModelId

    # Check if model already exists
    if (Test-ModelExistsLocally -ModelId $ModelId) {
        $fileSize = Get-FileSize -FilePath $modelPath
        Write-LogMessage -Level "INFO" -Message "Model already exists locally: $modelPath ($fileSize)"
        return $modelPath
    }

    # Check available disk space (require at least 5GB)
    if (-not (Test-DiskSpace -RequiredGB 5)) {
        Write-LogMessage -Level "ERROR" -Message "Insufficient disk space for model download"
        return $null
    }

    Write-LogMessage -Level "INFO" -Message "Downloading model: $ModelId"

    # Validate model and find available files
    $filesInfo = Find-ModelFiles -ModelId $ModelId -ModelType $ModelType
    if (-not $filesInfo) {
        return $null
    }

    # Select the best GGUF file
    $selectedFile = Select-BestModelFile -FilesInfo $filesInfo
    if (-not $selectedFile) {
        Write-LogMessage -Level "ERROR" -Message "No suitable model files found for: $ModelId"
        return $null
    }

    Write-LogMessage -Level "INFO" -Message "Selected model file: $selectedFile"

    # Download the model file
    $downloadUrl = "https://huggingface.co/$ModelId/resolve/main/$selectedFile"
    $randomString = New-RandomString -Length 8
    $tempPath = Join-Path $env:TEMP "${randomString}_$modelFilename"

    Write-LogMessage -Level "INFO" -Message "Downloading from: $downloadUrl"

    if ($env:DEBUG -eq "1") {
        Write-LogMessage -Level "DEBUG" -Message "Download URL: $downloadUrl"
        Write-LogMessage -Level "DEBUG" -Message "Temporary path: $tempPath"
        Write-LogMessage -Level "DEBUG" -Message "Final path: $modelPath"
    }

    # Download with progress
    if (-not (Invoke-DownloadWithProgress -Url $downloadUrl -OutputPath $tempPath)) {
        Write-LogMessage -Level "ERROR" -Message "Failed to download model"
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        return $null
    }

    # Verify the download
    if (-not (Test-Path $tempPath) -or (Get-Item $tempPath).Length -eq 0) {
        Write-LogMessage -Level "ERROR" -Message "Downloaded file is empty or missing"
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        return $null
    }

    # Basic integrity check - ensure file is at least 1MB
    $fileSizeBytes = (Get-Item $tempPath).Length
    if ($fileSizeBytes -lt 1048576) {
        Write-LogMessage -Level "ERROR" -Message "Downloaded file appears corrupted or incomplete: $fileSizeBytes bytes"
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        return $null
    }

    # Move to final location
    try {
        Move-Item -Path $tempPath -Destination $modelPath -Force
        $finalSize = Get-FileSize -FilePath $modelPath
        Write-LogMessage -Level "INFO" -Message "Model downloaded successfully: $modelPath ($finalSize)"
        return $modelPath
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to move model to final location: $($_.Exception.Message)"
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Select-BestModelFile {
    <#
    .SYNOPSIS
    Select the best model file from available options

    .PARAMETER FilesInfo
    Array of available file names
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$FilesInfo
    )

    # First try to find a good quantization level (Q4_0 or Q4_K_M)
    $selectedFile = $FilesInfo | Where-Object { $_ -match '(q4_0|q4_k_m)' } | Select-Object -First 1

    # If no Q4 files, try other common quantizations
    if (-not $selectedFile) {
        $selectedFile = $FilesInfo | Where-Object { $_ -match '(q8_0|f16)' } | Select-Object -First 1
    }

    # Finally, just take the first available GGUF file
    if (-not $selectedFile) {
        $selectedFile = $FilesInfo | Select-Object -First 1
    }

    return $selectedFile
}

function Invoke-DownloadWithProgress {
    <#
    .SYNOPSIS
    Download file with progress bar and resume support

    .PARAMETER Url
    URL to download from

    .PARAMETER OutputPath
    Path to save the file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $maxRetries = 3
    $retryCount = 0

    if ($env:DEBUG -eq "1") {
        Write-LogMessage -Level "DEBUG" -Message "Starting download with progress"
        Write-LogMessage -Level "DEBUG" -Message "URL: $Url"
        Write-LogMessage -Level "DEBUG" -Message "Output: $OutputPath"
    }

    while ($retryCount -lt $maxRetries) {
        Write-LogMessage -Level "INFO" -Message "Download attempt $($retryCount + 1)/$maxRetries"

        try {
            # Create webclient for download with progress
            $webClient = New-Object System.Net.WebClient

            # Register progress event
            $progressEventJob = Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
                $Global:DownloadProgress = $Event.SourceEventArgs.ProgressPercentage
                if ($Global:DownloadProgress % 10 -eq 0 -and $Global:DownloadProgress -ne $Global:LastProgress) {
                    Write-Host "Download progress: $($Global:DownloadProgress)%" -ForegroundColor Cyan
                    $Global:LastProgress = $Global:DownloadProgress
                }
            }

            # Start download
            $Global:DownloadProgress = 0
            $Global:LastProgress = 0

            $downloadTask = $webClient.DownloadFileTaskAsync($Url, $OutputPath)

            # Wait for completion
            while (-not $downloadTask.IsCompleted) {
                Start-Sleep -Milliseconds 500
            }

            # Cleanup
            Unregister-Event -SourceIdentifier $progressEventJob.Name
            $webClient.Dispose()

            if ($downloadTask.IsFaulted) {
                throw $downloadTask.Exception.InnerException
            }

            if ($env:DEBUG -eq "1") {
                Write-LogMessage -Level "DEBUG" -Message "Download completed successfully"
                if (Test-Path $OutputPath) {
                    $fileSize = (Get-Item $OutputPath).Length
                    Write-LogMessage -Level "DEBUG" -Message "Downloaded file size: $fileSize bytes"
                }
            }

            Write-Host "Download progress: 100%" -ForegroundColor Green
            return $true
        }
        catch {
            if ($env:DEBUG -eq "1") {
                Write-LogMessage -Level "DEBUG" -Message "Download failed with error: $($_.Exception.Message)"
            }

            # Cleanup on failure
            if ($webClient) {
                try { Unregister-Event -SourceIdentifier $progressEventJob.Name -ErrorAction SilentlyContinue } catch {}
                $webClient.Dispose()
            }

            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-LogMessage -Level "WARN" -Message "Download failed, retrying in 10 seconds..."
                Start-Sleep -Seconds 10
            }
        }
    }

    Write-LogMessage -Level "ERROR" -Message "Download failed after $maxRetries attempts"
    return $false
}

function Get-LocalModels {
    <#
    .SYNOPSIS
    List locally downloaded models
    #>
    [CmdletBinding()]
    param()

    Write-Host "📦 Local Models:" -ForegroundColor Cyan
    Write-Host ""

    $modelsDir = $Script:ModelsDir
    if (-not $modelsDir) {
        $modelsDir = Join-Path $PSScriptRoot "../models"
    }

    if (-not (Test-Path $modelsDir) -or -not (Get-ChildItem $modelsDir -Filter "*.gguf")) {
        Write-Host "No models found in $modelsDir"
        return
    }

    $totalSize = 0
    $modelFiles = Get-ChildItem $modelsDir -Filter "*.gguf"

    foreach ($modelFile in $modelFiles) {
        $filename = $modelFile.Name
        $modelId = $filename -replace '_', '/' -replace '\.gguf$', ''
        $size = Get-FileSize -FilePath $modelFile.FullName
        $sizeBytes = $modelFile.Length

        $totalSize += $sizeBytes

        Write-Host "   • $modelId" -ForegroundColor White
        Write-Host "     File: $filename" -ForegroundColor Gray
        Write-Host "     Size: $size" -ForegroundColor Gray
        Write-Host "     Path: $($modelFile.FullName)" -ForegroundColor Gray
        Write-Host ""
    }

    $totalSizeHuman = if ($totalSize -gt 1GB) {
        "{0:N1}GB" -f ($totalSize / 1GB)
    } elseif ($totalSize -gt 1MB) {
        "{0:N1}MB" -f ($totalSize / 1MB)
    } elseif ($totalSize -gt 1KB) {
        "{0:N1}KB" -f ($totalSize / 1KB)
    } else {
        "${totalSize}B"
    }

    Write-Host "Total size: $totalSizeHuman" -ForegroundColor Yellow
}

function Remove-LocalModel {
    <#
    .SYNOPSIS
    Remove local model

    .PARAMETER ModelId
    HuggingFace model ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId
    )

    $modelPath = Get-ModelPath -ModelId $ModelId

    if (-not (Test-Path $modelPath)) {
        Write-LogMessage -Level "WARN" -Message "Model not found locally: $ModelId"
        return $false
    }

    $size = Get-FileSize -FilePath $modelPath
    $confirmation = Read-Host "Remove model $ModelId ($size)? (y/N)"

    if ($confirmation -match '^[Yy]$') {
        try {
            Remove-Item -Path $modelPath -Force
            Write-LogMessage -Level "INFO" -Message "Model removed: $ModelId"
            return $true
        }
        catch {
            Write-LogMessage -Level "ERROR" -Message "Failed to remove model: $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-LogMessage -Level "INFO" -Message "Model removal cancelled"
        return $false
    }
}

# Export all functions
Export-ModuleMember -Function *