<#
.SYNOPSIS
Converts an Azure DevOps Wiki to GitHub Wiki format.

.DESCRIPTION
This script clones an Azure DevOps Wiki repository and a GitHub Wiki repository, migrates the wiki pages from Azure DevOps format to GitHub format, and pushes the changes to the GitHub repository.

.PARAMETER AzureDevOpsWikiRepositoryUrl
The URL of the Azure DevOps Wiki repository to migrate.

.PARAMETER GitHubWikiRepositoryUrl
The URL of the GitHub Wiki repository to push the migrated pages to.

.EXAMPLE
ConvertTo-GitHubWiki -AzureDevOpsWikiRepositoryUrl "https://dev.azure.com/organization/project/_git/wiki" -GitHubWikiRepositoryUrl "https://github.com/organization/project.wiki.git"

.NOTES
Author: Vinny Martins
Date: 2024-04-09
Version: 1.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [System.Uri]
    $AzureDevOpsWikiRepositoryUrl,
    [Parameter(Mandatory = $true)]
    [System.Uri]
    $GitHubWikiRepositoryUrl
)

$ErrorActionPreference = 'Stop'

. $PSScriptRoot\Markdown.ps1

function GetTempLogFile {
    $tempFile = [System.IO.FileInfo]([System.IO.Path]::GetTempFileName())
    $logFile = Join-Path $tempFile.DirectoryName "$($tempFile.Name).log"
    Move-Item $tempFile $logFile -Force | Out-Null

    return $logFile
}

function Exec {
    param (
        [scriptblock]$ScriptBlock,
        [int[]] $SuccessCodes = @(0)
    )
    
    $logFile = GetTempLogFile

    & @ScriptBlock *> $logFile

    if ($lastexitcode -notin $SuccessCodes) {
        throw "Script block '$($ScriptBlock.ToString().Trim().Substring(0, 10))...' failed with code $($lastexitcode). See log file '$logFile' for details."
    }
}

function CreateTempDirectory {
    $tempDirectory = Join-Path $env:TEMP "devops-to-github-wiki"

    if (Test-Path $tempDirectory) {
        Remove-Item $tempDirectory -Recurse -Force | Out-Null
    }    

    $tempDirectory = Join-Path $tempDirectory $(New-Guid)
    New-Item -ItemType Directory -Path $tempDirectory | Out-Null

    return $tempDirectory
}

function CloneRepository ([string] $repositoryUrl, [string] $path) {
    Exec { git clone $([uri]::EscapeUriString($repositoryUrl)) $path }    
}

function PushToRepository ([string] $repositoryUrl, [string] $path) {
    Push-Location $path

    try {
        Exec { git add . }
        Exec { git commit -m "Migrate from Azure DevOps Wiki" } -SuccessCodes @(0, 1)
        Exec { git push $([uri]::EscapeUriString($repositoryUrl)) }
    }
    finally {
        Pop-Location
    }
}

function DeleteAllFiles ([string] $path) {
    Get-ChildItem $path -Recurse -Exclude ".git" | Remove-Item -Recurse -Force    
}

# Convert all markdown files in the current directory to GitHub wiki format
function ReadPages ([string]$path) {
    $orderFile = Join-Path $path ".order"
    
    if (Test-Path $orderFile) {
        return Write-Output @(Get-Content $orderFile) -NoEnumerate
    }

    return @()
}

function MigratePage ([string] $page) {
    $content = Get-Content $page

    $content = $content | ForEach-Object {
        $line = $_
        $line = MigrateImage $line

        $line
    }

    return $content
}

function MigrateImage ([string] $line) {
    return $line -replace '!\[([^\]]*)\]\(([^\)]*)\)', '![$1](./$2)'
}

function SanitizePageName ([string] $pageName) {
    return $([uri]::UnescapeDataString($pageName)) -replace '[\/:*?"<>|]', ''
}

function MigrateWikiPages ([string] $path, [string] $prefix = "", [string] $outputPath = ".") {
    $pages = ReadPages $path

    for ($i = 0; $i -lt $pages.Count; $i++) {
        $page = $pages[$i]

        $pagePath = Join-Path $path $page
        $pageFile = "$pagePath.md"
        $pageContent = MigratePage $pageFile

        $newIndex = $($i + 1).ToString("00")
        $newPrefix = "$($prefix)$newIndex"
        $newPageFile = "$newPrefix-$(SanitizePageName $page).md"
        $newPagePath = Join-Path $outputPath $newPageFile

        New-Item -ItemType File -Path $newPagePath -Force | Out-Null
        Set-Content $newPagePath $pageContent
        
        Fix-Formatting -MarkdownFile $newPagePath -Overwrite

        if (Test-Path $pagePath -PathType Container) {
            MigrateWikiPages $pagePath "$($newPrefix)." $outputPath
        }
    }
}

function CopyAttachmentFiles ([string] $sourcePath, [string] $destinationPath) {
    $attachmentsPath = Join-Path $sourcePath ".attachments"
    Copy-Item -Path $attachmentsPath -Destination "$destinationPath" -Recurse -Force | Out-Null
}

function AppendToTableOfContents ([string[]] $toc, [string] $page) {
    $prefixNoDot = $page -replace "([^-]+)-.*\.md", '$1' -replace "\.", ""
    $link = $page -replace "(.*)\.md", '$1'
    $title = $link -replace "---", " - "
    
    $spaces = " " * ($prefixNoDot.Length - 2)
    $toc += "$spaces- [$title]($link)"

    return $toc
}

function CreateTableOfContents ([string] $path) {
    $pages = Get-ChildItem $path -Recurse -Filter "*.md" | Sort-Object Name

    $toc = @()
    $pages | ForEach-Object {
        $page = $_
        
        $toc = AppendToTableOfContents $toc $page.Name
    }

    return "# Table of Contents`n`n$(($toc | Out-String))"
}

function CreateHomePage ([string] $path) {
    $toc = CreateTableOfContents $path
    $homePage = Join-Path $path "Home.md"

    New-Item -ItemType File -Path $homePage -Force | Out-Null
    Out-File -FilePath $homePage -InputObject $toc -Encoding utf8
}

function Cleanup ([string] $path) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force | Out-Null
    }
}

try {
    $temp = CreateTempDirectory

    $devopsWiki = Join-Path $temp "devops-wiki"
    $githubWiki = Join-Path $temp "github-wiki"

    Write-Host "Cloning repositories..."

    CloneRepository $AzureDevOpsWikiRepositoryUrl $devopsWiki
    CloneRepository $GitHubWikiRepositoryUrl $githubWiki

    Write-Host "Migrating wiki pages..."
    DeleteAllFiles $githubWiki
    MigrateWikiPages -path $devopsWiki -outputPath $githubWiki
    CopyAttachmentFiles $devopsWiki $githubWiki
    CreateHomePage $githubWiki

    Write-Host "Pushing changes to GitHub..."
    PushToRepository $GitHubWikiRepositoryUrl $githubWiki
    Write-Host "Done!"
}
catch {
    Write-Error "Failed to convert Azure DevOps Wiki to GitHub Wiki: $_"
}
finally {
    Write-Host "Cleaning up..."
    Cleanup $temp
}

