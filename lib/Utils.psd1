@{
    # Script module or binary module file associated with this manifest
    RootModule = 'Utils.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = '12345678-1234-1234-1234-123456789012'

    # Author of this module
    Author = 'Llama.cpp Runner PowerShell Team'

    # Company or vendor of this module
    CompanyName = 'Open Source'

    # Copyright statement for this module
    Copyright = '(c) 2024. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Utility functions for Llama.cpp Runner PowerShell version. Provides core functionality for environment validation, dependency checking, port management, health monitoring, and logging.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Initialize-Environment',
        'Test-Dependencies',
        'Find-AvailablePort',
        'Wait-ForHealth',
        'Write-LogMessage',
        'Test-ModelId',
        'Get-ModelFilename',
        'Get-ModelPath',
        'Test-ModelExistsLocally',
        'Get-FileSize',
        'Test-PM2ProcessExists',
        'Get-PM2ProcessStatus',
        'Test-DiskSpace',
        'Find-LlamaServer',
        'Get-OptimalThreads',
        'Test-PortNumber',
        'New-RandomString'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('llama.cpp', 'AI', 'ML', 'HuggingFace', 'PM2', 'Server', 'Utils')

            # A URL to the license for this module.
            LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = ''

            # A URL to an icon representing this module.
            IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'Initial release of Llama.cpp Runner PowerShell utilities'

            # Prerelease string of this module
            Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false

            # External dependent modules of this module
            ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    DefaultCommandPrefix = ''
}