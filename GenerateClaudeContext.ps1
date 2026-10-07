param(
    [ValidateSet("foundation", "egg", "selling", "cutscene", "ui", "full")]
    [string]$Focus = "foundation"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputFile = Join-Path $Root "CLAUDE_CONTEXT.md"

# Documentation that every Claude session should know about.
$DocFiles = @(
    "CLAUDE.md",
    "PROJECT_STATE.md",
    "HANDOFF.md"
)
# Source files to include for each type of task.
$Profiles = @{
    foundation = @(
        "src/server/ServerScriptService/Services/RoundService.luau",
        "src/server/ServerScriptService/Services/StationTeleportService.luau",
        "src/client/StarterPlayerScripts/ClientMain.local.luau",
        "src/shared/Shared/GameConfig.luau",
        "src/shared/Shared/EggDefinitions.luau"
    )

    egg = @(
        "src/server/ServerScriptService/EggSim.legacy.luau",
        "src/server/ServerScriptService/EggSweepTest.legacy.luau",
        "src/server/ServerScriptService/Services/EggService.luau",
        "src/server/ServerScriptService/Services/PieceService.luau",
        "src/server/ServerScriptService/Services/ToolService.luau",
        "src/server/ServerScriptService/Services/RoundService.luau",
        "src/client/StarterPlayerScripts/Controllers/EggView.luau",
        "src/client/StarterPlayerScripts/Controllers/ToolController.luau",
        "src/client/StarterPlayerScripts/EggProgress.local.luau",
        "src/client/StarterPlayerScripts/LayerHUD.local.luau",
        "src/shared/Shared/EggDefinitions.luau",
        "src/shared/Shared/ToolDefinitions.luau",
        "src/shared/Shared/GameConfig.luau"
    )

    selling = @(
        "src/server/ServerScriptService/Services/InventoryService.luau",
        "src/server/ServerScriptService/Services/ShopService.luau",
        "src/server/ServerScriptService/Services/PlayerDataService.luau",
        "src/server/ServerScriptService/Services/EggService.luau",
        "src/server/ServerScriptService/Services/StationTeleportService.luau",
        "src/client/StarterPlayerScripts/Controllers/PickupController.luau",
        "src/client/StarterPlayerScripts/Controllers/ReactController.luau",
        "src/client/StarterPlayerScripts/UI/Store.luau",
        "src/client/StarterPlayerScripts/UI/SellPopup.luau",
        "src/client/StarterPlayerScripts/UI/Journal.luau",
        "src/shared/Shared/ItemDefinitions.luau",
        "src/shared/Shared/GameConfig.luau"
    )

    cutscene = @(
        "src/client/StarterPlayerScripts/HatchCutscene.local.luau",
        "src/client/StarterPlayerScripts/ReleaseCutscene.local.luau",
        "src/client/StarterPlayerScripts/DinoLife.local.luau",
        "src/client/StarterPlayerScripts/MotherHider.local.luau",
        "src/client/StarterPlayerScripts/ClientMain.local.luau",
        "src/client/StarterPlayerScripts/Controllers/EggView.luau",
        "src/client/StarterPlayerScripts/Controllers/ReactController.luau",
        "src/server/ServerScriptService/Services/EggService.luau",
        "src/server/ServerScriptService/Services/RoundService.luau",
        "src/shared/Shared/DinoAnimator.luau",
        "src/shared/Shared/HatchlingProp.luau",
        "src/shared/Shared/GameConfig.luau"
    )

    ui = @(
        "src/client/StarterPlayerScripts/ClientMain.local.luau",
        "src/client/StarterPlayerScripts/Controllers/ReactController.luau",
        "src/client/StarterPlayerScripts/UI/App.luau",
        "src/client/StarterPlayerScripts/UI/Theme.luau",
        "src/client/StarterPlayerScripts/UI/Store.luau",
        "src/client/StarterPlayerScripts/UI/Journal.luau",
        "src/client/StarterPlayerScripts/UI/Hotbar.luau",
        "src/client/StarterPlayerScripts/UI/ShopPanel.luau",
        "src/client/StarterPlayerScripts/UI/SellPopup.luau",
        "src/client/StarterPlayerScripts/UI/Notifications.luau",
        "src/client/StarterPlayerScripts/UI/Results.luau"
    )
}

function Add-FileToContext {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$RelativePath
    )

    $FullPath = Join-Path $Root $RelativePath

    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        $Builder.AppendLine("## MISSING FILE: $RelativePath") | Out-Null
        $Builder.AppendLine("") | Out-Null
        return
    }

    $Content = Get-Content -LiteralPath $FullPath -Raw -Encoding UTF8

    $Builder.AppendLine("## FILE: $RelativePath") | Out-Null
    $Builder.AppendLine("") | Out-Null

    if ([string]::IsNullOrWhiteSpace($Content)) {
        $Builder.AppendLine("(empty file)") | Out-Null
    }
    elseif ($RelativePath.EndsWith(".md")) {
        $Builder.AppendLine($Content.TrimEnd()) | Out-Null
    }
    else {
        $Builder.AppendLine('```lua') | Out-Null
        $Builder.AppendLine($Content.TrimEnd()) | Out-Null
        $Builder.AppendLine('```') | Out-Null
    }

    $Builder.AppendLine("") | Out-Null
    $Builder.AppendLine("---") | Out-Null
    $Builder.AppendLine("") | Out-Null
}

# Build source file list.
$SourceFiles = New-Object System.Collections.Generic.List[string]

if ($Focus -eq "full") {
    $SrcRoot = Join-Path $Root "src"

    if (Test-Path -LiteralPath $SrcRoot) {
        $Files = Get-ChildItem -LiteralPath $SrcRoot -Recurse -File |
            Where-Object {
                $_.Extension -in @(".lua", ".luau") -and
                $_.FullName -notmatch "\\Packages\\"
            }

        foreach ($File in $Files) {
            $Relative = $File.FullName.Substring($Root.Length).TrimStart("\", "/")
            $Relative = $Relative.Replace("\", "/")

            if (-not $SourceFiles.Contains($Relative)) {
                $SourceFiles.Add($Relative)
            }
        }
    }
}
else {
    foreach ($Path in $Profiles[$Focus]) {
        if (-not $SourceFiles.Contains($Path)) {
            $SourceFiles.Add($Path)
        }
    }
}

# Automatically include locally changed source files.
try {
    $StatusLines = git -C $Root status --porcelain 2>$null

    foreach ($Line in $StatusLines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        $PathText = $Line.Substring(3).Trim()

        if ($PathText -match " -> ") {
            $PathText = $PathText.Split(" -> ")[-1]
        }

        $PathText = $PathText.Replace("\", "/")

        if (
            $PathText.StartsWith("src/") -and
            ($PathText.EndsWith(".lua") -or $PathText.EndsWith(".luau")) -and
            -not $PathText.Contains("/Packages/")
        ) {
            if (-not $SourceFiles.Contains($PathText)) {
                $SourceFiles.Add($PathText)
            }
        }
    }
}
catch {
    # Git is optional.
}

# Build document.
$Builder = New-Object System.Text.StringBuilder

$Builder.AppendLine("# Eggscavator - Claude Context Pack") | Out-Null
$Builder.AppendLine("") | Out-Null
$Builder.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')") | Out-Null
$Builder.AppendLine("Focus: $Focus") | Out-Null
$Builder.AppendLine("") | Out-Null
$Builder.AppendLine("This is a temporary context file generated from the local repository.") | Out-Null
$Builder.AppendLine("The repository remains the source of truth.") | Out-Null
$Builder.AppendLine("") | Out-Null

# Git information.
$Builder.AppendLine("# Git State") | Out-Null
$Builder.AppendLine("") | Out-Null

try {
    $Branch = git -C $Root branch --show-current 2>$null
    $LastCommit = git -C $Root log -1 --oneline 2>$null
    $Status = git -C $Root status --short 2>$null

    $Builder.AppendLine("Branch: $Branch") | Out-Null
    $Builder.AppendLine("Latest commit: $LastCommit") | Out-Null
    $Builder.AppendLine("") | Out-Null
    $Builder.AppendLine("Working tree:") | Out-Null

    if ([string]::IsNullOrWhiteSpace(($Status -join ""))) {
        $Builder.AppendLine("Clean") | Out-Null
    }
    else {
        $Builder.AppendLine('```text') | Out-Null
        $Builder.AppendLine(($Status -join "`r`n")) | Out-Null
        $Builder.AppendLine('```') | Out-Null
    }
}
catch {
    $Builder.AppendLine("Git information unavailable.") | Out-Null
}

$Builder.AppendLine("") | Out-Null
$Builder.AppendLine("---") | Out-Null
$Builder.AppendLine("") | Out-Null

# Documentation.
$Builder.AppendLine("# Project Documentation") | Out-Null
$Builder.AppendLine("") | Out-Null

foreach ($Doc in $DocFiles) {
    Add-FileToContext -Builder $Builder -RelativePath $Doc
}

# Source index.
$Builder.AppendLine("# Included Source Files") | Out-Null
$Builder.AppendLine("") | Out-Null

foreach ($Source in $SourceFiles) {
    $Builder.AppendLine("- $Source") | Out-Null
}

$Builder.AppendLine("") | Out-Null
$Builder.AppendLine("---") | Out-Null
$Builder.AppendLine("") | Out-Null

# Source code.
$Builder.AppendLine("# Source Code") | Out-Null
$Builder.AppendLine("") | Out-Null

foreach ($Source in $SourceFiles) {
    Add-FileToContext -Builder $Builder -RelativePath $Source
}

[System.IO.File]::WriteAllText(
    $OutputFile,
    $Builder.ToString(),
    [System.Text.UTF8Encoding]::new($false)
)

$SizeKB = [math]::Round((Get-Item $OutputFile).Length / 1KB, 1)

Write-Host ""
Write-Host "CLAUDE_CONTEXT.md generated successfully." -ForegroundColor Green
Write-Host "Focus: $Focus"
Write-Host "Source files included: $($SourceFiles.Count)"
Write-Host "Output size: $SizeKB KB"
Write-Host "Output: $OutputFile"
Write-Host ""