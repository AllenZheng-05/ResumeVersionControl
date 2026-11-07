#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Sets up a new application folder, after checking for a prior application.

.DESCRIPTION
  Searches resumes/ and resumes/archive/ for the same company (by folder name)
  and the same posting URL (in job_posting.md). If either matches, it lists them
  and stops unless -Force is passed, since a different role at the same company
  can be fine.

  Otherwise it creates resumes/<Category>/<Company>_<RoleTitle>_<today>/ with:
    - <ResumeName>.tex (name from CLAUDE.md section 0): the master's current
      preamble and header, with an empty body. Each resume stays self-contained so sent copies stay frozen.
    - job_posting.md: the template from CLAUDE.md section 2, with Date Applied
      blank until the application is submitted.

.PARAMETER Company
  Company name with no spaces (e.g. Acme).

.PARAMETER RoleTitle
  Role title with no spaces (e.g. SoftwareEngineerIntern).

.PARAMETER Category
  Kebab-case role category (e.g. software-engineer).

.PARAMETER PostingUrl
  Posting URL, used for the duplicate check and recorded in job_posting.md.

.PARAMETER Force
  Create the folder even if a prior application matched.

.EXAMPLE
  ./scripts/new_application.ps1 -Company Acme -RoleTitle SoftwareEngineerIntern -Category software-engineer -PostingUrl https://acme.com/jobs/123
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Company,

    [Parameter(Mandatory = $true)]
    [string]$RoleTitle,

    [Parameter(Mandatory = $true)]
    [string]$Category,

    [string]$PostingUrl = '',

    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($Company -match '\s' -or $RoleTitle -match '\s') {
    Write-Error "Company and RoleTitle can't contain spaces; folder names use <Company>_<RoleTitle>_<YYYY-MM-DD>."
}
if ($Category -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    Write-Error "Category must be kebab-case, e.g. software-engineer."
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$resumesDir = Join-Path $repoRoot "resumes"
$masterPath = Join-Path $repoRoot "master/master_resume.tex"
$claudePath = Join-Path $repoRoot "CLAUDE.md"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$nameMatch = Select-String -Path $claudePath -Pattern 'Resume file name:\*\*\s*`([^`]+)`' | Select-Object -First 1
if (-not $nameMatch) {
    Write-Error "Couldn't find the resume file name in section 0 of $claudePath"
}
$resumeName = $nameMatch.Matches[0].Groups[1].Value
if ($resumeName -eq 'Jane_Doe_Resume') {
    Write-Error "The resume file name is still the placeholder. Change Jane_Doe_Resume to <FirstName>_<LastName>_Resume in section 0 of $claudePath."
}

# --- Prior-application check ---
$allFolders = @()
if (Test-Path $resumesDir) {
    $allFolders = @(Get-ChildItem -Path $resumesDir -Directory -Recurse |
            Where-Object { $_.Name -match '_\d{4}-\d{2}-\d{2}$' })
}

$priorMatches = New-Object System.Collections.Generic.List[string]
foreach ($folder in $allFolders) {
    $relative = $folder.FullName.Substring($repoRoot.Length + 1)
    if ($folder.Name -like "$Company`_*") {
        $priorMatches.Add("$relative (same company)")
        continue
    }
    if ($PostingUrl) {
        $posting = Join-Path $folder.FullName "job_posting.md"
        if ((Test-Path $posting) -and (Select-String -Path $posting -SimpleMatch -Pattern $PostingUrl -Quiet)) {
            $priorMatches.Add("$relative (same posting URL)")
        }
    }
}

if ($priorMatches.Count -gt 0) {
    Write-Host "Prior application(s) found:"
    $priorMatches | ForEach-Object { Write-Host "  $_" }
    if (-not $Force) {
        Write-Host "Stopping. Check with the user, then rerun with -Force if this is a different role."
        exit 1
    }
}

# --- Create the folder ---
$today = Get-Date -Format 'yyyy-MM-dd'
$appDir = Join-Path $resumesDir (Join-Path $Category "$Company`_$RoleTitle`_$today")
if (Test-Path $appDir) {
    Write-Error "$appDir already exists."
}

# Master preamble and header: everything through the header's \end{center}.
$masterLines = [System.IO.File]::ReadAllLines($masterPath, $utf8NoBom)
$headerEnd = -1
for ($i = 0; $i -lt $masterLines.Count; $i++) {
    if ($masterLines[$i] -match '\\end\{center\}') {
        $headerEnd = $i
        break
    }
}
if ($headerEnd -lt 0) {
    Write-Error "Couldn't find the header's \end{center} in $masterPath"
}
$firstContentLine = 0
while ($masterLines[$firstContentLine] -match '^\s*(%.*)?$') { $firstContentLine++ }

$texLines = @(
    "%-------------------------"
    "% Tailored resume: $Company -- $RoleTitle"
    "% Generated from master/master_resume.tex"
    "% Template: Jake's Resume by Jake Gutierrez, based on https://github.com/sb2nov/resume (MIT)"
    "%------------------------"
    ""
) + $masterLines[$firstContentLine..$headerEnd] + @(
    ""
    "% Select and reorder content from master/master_resume.tex (CLAUDE.md section 2)."
    ""
    "\end{document}"
)

$postingLines = @(
    "# $Company - $RoleTitle"
    ""
    "- Role Category: $Category"
    "- Job Type:"
    "- Posting URL: $PostingUrl"
    "- Date Applied:"
    "- Date Opened:"
    "- Pay Range:"
    "- Start Date:"
    "- End Date:"
    ""
    "## Job Description"
    ""
    ""
    "## ATS Keywords"
    ""
    "### Required"
    ""
    ""
    "### Preferred"
    ""
    ""
    "## Tailoring Notes"
    ""
)

New-Item -ItemType Directory -Path $appDir -Force | Out-Null
[System.IO.File]::WriteAllLines((Join-Path $appDir "$resumeName.tex"), [string[]]$texLines, $utf8NoBom)
[System.IO.File]::WriteAllLines((Join-Path $appDir "job_posting.md"), [string[]]$postingLines, $utf8NoBom)

Write-Host "Created $($appDir.Substring($repoRoot.Length + 1))"
exit 0
