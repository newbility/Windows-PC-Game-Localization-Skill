[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('create', 'cleanup')]
    [string]$Action,
    [Parameter(Mandatory)]
    [string]$ScratchRoot,
    [string]$RunId,
    [switch]$Completed
)

$ErrorActionPreference = 'Stop'

function Get-PlainDirectory([string]$Path) {
    $directory = Get-Item -LiteralPath $Path -Force
    if ($directory -isnot [IO.DirectoryInfo]) {
        throw "Expected a filesystem directory: $Path"
    }
    for ($ancestor = $directory; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked workspace path: $($ancestor.FullName)"
        }
    }
    return $directory
}

function Assert-NoLinkedChildren([IO.DirectoryInfo]$Directory) {
    $pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pending.Push($Directory)
    while ($pending.Count -gt 0) {
        foreach ($entry in $pending.Pop().EnumerateFileSystemInfos()) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked path inside workspace: $($entry.FullName)"
            }
            if ($entry -is [IO.DirectoryInfo]) {
                $pending.Push($entry)
            }
        }
    }
}

if ($Action -eq 'cleanup' -and (-not $Completed -or $RunId -cnotmatch '\A[0-9a-f]{32}\z')) {
    throw 'Cleanup requires the RunId returned by create and -Completed.'
}

$scratch = Get-PlainDirectory $ScratchRoot
$containerPath = Join-Path $scratch.FullName 'game-localization-public-handoff'
$markerName = '.handoff-workspace.json'

if ($Action -eq 'create') {
    if ($RunId -or $Completed) {
        throw 'Create generates its own RunId. Omit -RunId and -Completed.'
    }
    $RunId = [Guid]::NewGuid().ToString('N')
    $newPath = Join-Path $containerPath $RunId
    if (-not $PSCmdlet.ShouldProcess($newPath, 'Create a temporary handoff workspace')) { return }
    [IO.Directory]::CreateDirectory($containerPath) | Out-Null
}

$container = Get-PlainDirectory $containerPath
if ($container.Parent.FullName -ne $scratch.FullName) {
    throw "Workspace container is outside the selected scratch root: $containerPath"
}
$workspacePath = Join-Path $container.FullName $RunId
$markerPath = Join-Path $workspacePath $markerName

if ($Action -eq 'create') {
    if (Test-Path -LiteralPath $workspacePath) {
        throw "Temporary workspace already exists: $workspacePath"
    }
    [IO.Directory]::CreateDirectory($workspacePath) | Out-Null
    $marker = @{ schema = 1; runId = $RunId; workspace = $workspacePath } | ConvertTo-Json
    [IO.File]::WriteAllText($markerPath, $marker)
    return [pscustomobject]@{ RunId = $RunId; Workspace = $workspacePath; Status = 'created' }
}

$workspace = Get-PlainDirectory $workspacePath
if ($workspace.Parent.FullName -ne $container.FullName -or $workspace.Name -cne $RunId) {
    throw "Workspace is outside the verified container: $workspacePath"
}
$markerFile = Get-Item -LiteralPath $markerPath -Force
if ($markerFile -isnot [IO.FileInfo] -or ($markerFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "Invalid workspace marker: $markerPath"
}
$marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($marker.schema -ne 1 -or $marker.runId -cne $RunId -or $marker.workspace -ne $workspace.FullName) {
    throw "Workspace marker does not match the current run: $markerPath"
}
Assert-NoLinkedChildren $workspace

if ($PSCmdlet.ShouldProcess($workspace.FullName, 'Remove this completed handoff workspace')) {
    Remove-Item -LiteralPath $workspace.FullName -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $workspace.FullName) {
        throw "Workspace still exists: $($workspace.FullName)"
    }
    [pscustomobject]@{ RunId = $RunId; Workspace = $workspace.FullName; Status = 'removed' }
}
