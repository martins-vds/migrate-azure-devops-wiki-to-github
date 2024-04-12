$script:currentSection = $null
$script:lastNumber = 0
$script:spacesToRemove = ""
$script:previousLine = ""

$sections = @{
    Code       = @{
        Start   = '^(\s*)```.+'
        End     = '^(\s*)```$'
        Process = "ProcessCodeSection"
    }
    Image      = @{
        Start   = '^(\s*)!\[.*\]\(.*\)$'
        End     = '^(?!(\s*)!\[.*\]\(.*\))$'
        Process = "ProcessImageSection"
    }
    Note       = @{
        Start   = '^(\s*)\>.*$'
        End     = '^(?!(\s*)\>.*)$'
        Process = "ProcessNoteSection"
    }
    ListNumber = @{
        Start   = '^\d+\.'
        End     = '^(?!^\d+\.)'
        Process = "ProcessListNumberIncrementSection"
    }
    Paragraph  = @{
        Start   = '^(\s*)\w'
        End     = '^(?!(\s*)\w)'
        Process = "ProcessParagraphSection"
    }
    Header     = @{
        Start   = '^(\s*)#'
        End     = '^(?!(\s*)#)'
        Process = "ProcessHeaderSection"
    }
    Html       = @{
        Start   = "(?<!\<\s*)((ht|f)tp(s?)\:\/\/[0-9a-zA-Z]([-.\w]*[0-9a-zA-Z])*(:(0-9)*)*(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&%\$#_=]*)?)(?!\s*/>)"
        End     = "^(?!(?<!\<\s*)((ht|f)tp(s?)\:\/\/[0-9a-zA-Z]([-.\w]*[0-9a-zA-Z])*(:(0-9)*)*(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&%\$#_=]*)?)(?!\s*/>))"
        Process = "ProcessHtmlSection"
    }
}

function ProcessCodeSection([string] $line) {
    if ($line -match '^(\s*)```.+') {
        $script:spacesToRemove = $matches[1]
        $line -replace "^$script:spacesToRemove", ''
    }
    elseif ($line -match '^(\s*)```$') {
        $line -replace "^$($matches[1])", ''
    }
    else {
        $line -replace "^$script:spacesToRemove", ''
    }
}

function ProcessImageSection([string] $line) {
    if ($line -match '^(\s*)!\[.*\]\(.*\)$') {
        $script:spacesToRemove = $matches[1]
        $line -replace "^$script:spacesToRemove", ''
    }
    else {
        $line
    }
}

function ProcessNoteSection([string] $line) {
    if ($line -match '^(\s*)>.*$') {
        $script:spacesToRemove = $matches[1]
        $line -replace "^$script:spacesToRemove", ''
    }
    else {
        $line
    }
}

function ProcessListNumberIncrementSection([string] $line) {
    if ($line -match '^\d+\.') {
        $script:lastNumber++
        $line -replace '^\d+', $script:lastNumber
    }
    else {
        $line
    }
}

function ProcessParagraphSection([string] $line) {
    if ($line -match '^(\s*)\w') {
        $script:spacesToRemove = $matches[1]
        $line -replace "^$script:spacesToRemove", ''
    }
    else {
        $line
    }
}

function ProcessHeaderSection([string] $line) {
    if ($line -match '^(\s*)#') {
        $script:lastNumber = 0
        $script:spacesToRemove = $matches[1]
        $line -replace "^$script:spacesToRemove", '' -replace "^(#+)\s*(.*)$", "`$1 `$2"
    }
    elseif ($line -match "^\w") {
        "`n$line"
    }
    else {
        $line
    }
}

function ProcessHtmlSection([string] $line) {
    if ($line -match "(?<!\<\s*)((ht|f)tp(s?)\:\/\/[0-9a-zA-Z]([-.\w]*[0-9a-zA-Z])*(:(0-9)*)*(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&%\$#_=]*)?)(?!\s*/>)") {
        
        $line -replace "$($matches[1])", "<$($matches[1])>"
    }
    else {
        $line
    }
}

function Fix-Formatting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (-Not ($_ | Test-Path) ) {
                    throw "File or folder does not exist"
                }
                if (-Not ($_ | Test-Path -PathType Leaf) ) {
                    throw "The Path argument must be a file. Folder paths are not allowed."
                }
                if ($_ -notmatch "\.md$") {
                    throw "The file specified in the path argument must be of type md"
                }
                return $true 
            })]
        [System.IO.FileInfo]    
        $MarkdownFile,
        [Parameter(Mandatory = $false)]
        [switch]
        $Overwrite
    )
    
    $markdown = Get-Content $MarkdownFile -Encoding utf8 | ForEach-Object {
        $line = $_        
        if ($null -eq $script:currentSection) {
            $sectionsToProcess = $sections.Keys | Where-Object { $line -match $sections[$_].Start } | Select-Object -First 1
    
            if ($null -eq $sectionsToProcess) {
                $line
            }
            else {
                $script:currentSection = $sectionsToProcess
                & $sections[$script:currentSection].Process $line
            }
        }
        else {
            if ($line -match $sections[$script:currentSection].End) {           
                & $sections[$script:currentSection].Process $line
                $script:currentSection = $null
            }
            else {
                & $sections[$script:currentSection].Process $line
            }
        }
    }
    
    if ($Overwrite) {
        $MarkdownOutput = $MarkdownFile.FullName
    }
    else {
        $MarkdownOutput = "$($MarkdownFile.DirectoryName)\$($MarkdownFile.BaseName)_fixed.md"
    }
    
    $markdown | Out-File -FilePath $MarkdownOutput -Encoding utf8 -Force
}
