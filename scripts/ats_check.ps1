#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Local approximation of an ATS (applicant tracking system) scan: checks a
  compiled tailored resume for parseability issues and JD-keyword coverage.

.DESCRIPTION
  This is NOT a real ATS -- there's no way to submit to the specific ATS a
  given company uses (Workday, Greenhouse, iCIMS, Taleo, etc. are
  proprietary and only reachable through an actual application), and this
  script doesn't drive any third-party resume-scanner site either. It's a
  local stand-in that approximates the two things most ATS keyword-matchers
  actually do: extract the resume's text without any layout/column
  awareness, then substring-search it for expected keywords.

  Parseability: runs plain `pdftotext` (no -layout) on the PDF -- closer to
  how many ATS text-extraction libraries read a PDF (linear content order,
  no attempt to preserve visual columns) than `build.ps1`'s `-layout` mode.
  Flags missing contact info (phone/email) and any `\section{...}` heading
  from the .tex that doesn't turn up in the extracted text, since either
  is a sign the PDF isn't parsing the way it visually appears to.

  Keyword coverage: reads the `## ATS Keywords` list from the application's
  job_posting.md (see CLAUDE.md section 2, step 8) and checks each phrase
  against the extracted text using alnum-boundary matching (not plain
  substring, so e.g. "Go" doesn't false-positive inside "storage"; not
  regex \b either, since that mishandles keywords ending in symbols like
  "C++" or "C#"). Reports a match score plus the matched/missing lists.

  A keyword that misses exactly is retried in singular/plural and hyphen/space
  forms, so "agents" matches "AI-agent". Those are reported separately, next to
  the exact score, because a strict ATS may not count them. Optional `###`
  subheadings in the keyword list (e.g. `### Required`, `### Preferred`) get
  their own score lines.

.PARAMETER TexPath
  Path to the compiled application's .tex file (e.g.
  resumes/software-engineer/Acme_SWE_2026-08-04/Jane_Doe_Resume.tex).
  The PDF and job_posting.md are expected alongside it in the same folder.

.EXAMPLE
  ./scripts/ats_check.ps1 -TexPath resumes/software-engineer/Acme_SWE_2026-08-04/Jane_Doe_Resume.tex
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$TexPath
)

$ErrorActionPreference = "Stop"

$resolvedTex = Resolve-Path -Path $TexPath -ErrorAction Stop
$texDir = Split-Path -Path $resolvedTex -Parent
$texFile = Split-Path -Path $resolvedTex -Leaf
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($texFile)

$pdfPath = Join-Path $texDir "$baseName.pdf"
$jobPostingPath = Join-Path $texDir "job_posting.md"

if (-not (Test-Path $pdfPath)) {
    Write-Error "No compiled PDF at $pdfPath -- run build.ps1 first."
}
if (-not (Test-Path $jobPostingPath)) {
    Write-Error "No job_posting.md found at $jobPostingPath"
}

# --- Parse the '## ATS Keywords' section out of job_posting.md ---
$postingContent = Get-Content -Path $jobPostingPath -Raw
$keywordSectionMatch = [regex]::Match($postingContent, '(?ms)^##\s*ATS Keywords\s*$(.*?)(?=^##\s|\z)')
if (-not $keywordSectionMatch.Success) {
    Write-Error "No '## ATS Keywords' section found in $jobPostingPath. Add one (markdown list of exact-phrase skills/tools/requirements pulled from the JD) before running this check."
}
$keywordBlock = $keywordSectionMatch.Groups[1].Value

$keywords = New-Object System.Collections.Generic.List[object]
$group = ''
foreach ($line in ($keywordBlock -split "`r?`n")) {
    $t = $line.Trim()
    if ($t -match '^###\s+(.+)$') {
        $group = $Matches[1].Trim()
    }
    elseif ($t -match '^[-*]\s+(.+)$') {
        $keywords.Add([pscustomobject]@{ Text = $Matches[1].Trim(); Group = $group })
    }
}
if ($keywords.Count -eq 0) {
    # Fallback: comma-separated on one or more plain lines.
    $flat = ($keywordBlock -replace '[\r\n]+', ' ').Trim()
    if ($flat.Length -gt 0) {
        foreach ($piece in ($flat -split ',')) {
            $p = $piece.Trim()
            if ($p.Length -gt 0) { $keywords.Add([pscustomobject]@{ Text = $p; Group = '' }) }
        }
    }
}
if ($keywords.Count -eq 0) {
    Write-Error "Found a '## ATS Keywords' section in $jobPostingPath but couldn't parse any keywords from it. Use a markdown list ('- keyword') or a comma-separated line."
}

# --- Extract PDF text the crude, ATS-like way (no layout reconstruction) ---
$rawLines = & pdftotext -enc UTF-8 "$pdfPath" - 2>$null
$atsText = ($rawLines -join "`n")
$normalizedText = ($atsText -replace '\s+', ' ').ToLowerInvariant()

# --- Parseability checks ---
$parseIssues = @()

if ($normalizedText -notmatch '\(?\d{3}\)?[\s.-]*\d{3}[\s.-]*\d{4}') {
    $parseIssues += "Phone number not detected in extracted text"
}
if ($normalizedText -notmatch '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') {
    $parseIssues += "Email address not detected in extracted text"
}

$texContent = Get-Content -Path $resolvedTex -Raw
$sectionNames = [regex]::Matches($texContent, '\\section\{([^}]+)\}') | ForEach-Object { $_.Groups[1].Value }
foreach ($sec in $sectionNames) {
    $secPattern = "(?<![a-z0-9])" + [regex]::Escape($sec.ToLowerInvariant()) + "(?![a-z0-9])"
    if (-not [regex]::IsMatch($normalizedText, $secPattern)) {
        $parseIssues += "Section header '$sec' not found in extracted text (may be garbled or mis-ordered)"
    }
}

# --- Keyword coverage (alnum-boundary match, not \b -- handles C++/C#/.NET) ---
function Test-Phrase([string]$phrase) {
    $pattern = "(?<![a-z0-9])" + [regex]::Escape($phrase) + "(?![a-z0-9])"
    return [regex]::IsMatch($normalizedText, $pattern)
}

# Singular/plural and hyphen/space forms. Short keywords and ones with symbols
# (Go, AWS, C++, C#, .NET, CI/CD) are skipped: a variant of those is another word.
function Get-Variants([string]$phrase) {
    if ($phrase.Length -le 3 -or $phrase -notmatch '^[a-z0-9 -]+$') { return @() }
    $forms = New-Object System.Collections.Generic.List[string]
    foreach ($spaced in @($phrase, ($phrase -replace '-', ' '), ($phrase -replace ' ', '-'))) {
        $forms.Add($spaced)
        if ($spaced -match 's$' -and $spaced -notmatch 'ss$') {
            $forms.Add($spaced.Substring(0, $spaced.Length - 1))
        }
        else {
            $forms.Add($spaced + 's')
        }
    }
    return @($forms | Where-Object { $_ -ne $phrase } | Select-Object -Unique)
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($kw in $keywords) {
    $kwNorm = (($kw.Text -replace '\s+', ' ').Trim()).ToLowerInvariant()
    if ($kwNorm.Length -eq 0) { continue }
    $status = 'missing'
    if (Test-Phrase $kwNorm) {
        $status = 'exact'
    }
    elseif (@(Get-Variants $kwNorm | Where-Object { Test-Phrase $_ }).Count -gt 0) {
        $status = 'variant'
    }
    $results.Add([pscustomobject]@{ Text = $kw.Text; Group = $kw.Group; Status = $status })
}

function Format-Score([object[]]$items) {
    $count = $items.Length
    if ($count -eq 0) { return "0/0" }
    $exact = @($items | Where-Object { $_.Status -eq 'exact' }).Count
    $found = @($items | Where-Object { $_.Status -ne 'missing' }).Count
    $exactPct = [math]::Round(($exact / $count) * 100, 1)
    $score = "$exact/$count ($exactPct%)"
    if ($found -ne $exact) {
        $foundPct = [math]::Round(($found / $count) * 100, 1)
        $score += ", $found/$count ($foundPct%) with variants"
    }
    return $score
}

$results = $results.ToArray()
$exactMatches = @($results | Where-Object { $_.Status -eq 'exact' })
$variantMatches = @($results | Where-Object { $_.Status -eq 'variant' })
$missing = @($results | Where-Object { $_.Status -eq 'missing' })

Write-Host "ATS check (local approximation) for $TexPath"
Write-Host "----------------------------------------------------------------"
if ($parseIssues.Count -eq 0) {
    Write-Host "Parseability: OK -- contact info and all section headers found in extracted text"
}
else {
    Write-Host "Parseability issues:"
    $parseIssues | ForEach-Object { Write-Host "  - $_" }
}

Write-Host ""
Write-Host "Keyword match: $(Format-Score $results)"
foreach ($g in @($results | Where-Object { $_.Group } | Select-Object -ExpandProperty Group -Unique)) {
    Write-Host "  ${g}: $(Format-Score ($results | Where-Object { $_.Group -eq $g }))"
}
if ($missing.Count -gt 0) {
    Write-Host "Missing keywords:"
    $missing | ForEach-Object { Write-Host "  - $($_.Text)" }
}
if ($variantMatches.Count -gt 0) {
    Write-Host "Matched only through a variant (a strict ATS may not count these):"
    $variantMatches | ForEach-Object { Write-Host "  - $($_.Text)" }
}
if ($exactMatches.Count -gt 0) {
    Write-Host "Matched keywords:"
    $exactMatches | ForEach-Object { Write-Host "  - $($_.Text)" }
}
