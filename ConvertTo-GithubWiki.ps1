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

function Exec {
    param (
        [scriptblock]$ScriptBlock,
        [int[]] $SuccessCodes = @(0)
    )
    & @ScriptBlock | Out-Null
    if ($lastexitcode -notin $SuccessCodes) {
        throw "Script block '$($ScriptBlock.ToString().Trim().Substring(0, 10))...' failed with code $($lastexitcode)"
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

function MigrateWikiPages ([string] $path, [string] $prefix = "", [string] $outputPath = ".") {
    $pages = ReadPages $path

    for ($i = 0; $i -lt $pages.Count; $i++) {
        $page = $pages[$i]

        $pagePath = Join-Path $path $page
        $pageFile = "$pagePath.md"
        $pageContent = MigratePage $pageFile

        $newPrefix = "$($prefix)$($i+1)"
        $newPage = Join-Path $outputPath "$newPrefix $page.md"

        New-Item -ItemType File -Path $newPage -Force | Out-Null
        Set-Content $newPage $pageContent
        
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
    $prefix = $page -replace "([^\s]+)\s(.*)\.md", '$1'
    $title = $page -replace "([^\s]+)\s(.*)\.md", '$1 $2'
    $link = $title -replace " ", "-"

    $prefixNoDot = $prefix -replace "\.", ""
    $spaces = "  " * ($prefixNoDot.Length - 1)
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
} 
finally {
    Write-Host "Cleaning up temporary directory $temp"
    Cleanup $temp
}

Write-Host "Done!"