#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Checks a compiled resume PDF for layout defects that compile cleanly but
  look wrong on the page.

.DESCRIPTION
  Reads text positions from `pdftohtml -xml` (MiKTeX's pdftotext has no -bbox
  option) and fonts from `pdffonts`. It only reads the PDF, so it's safe to run
  on any resume, including submitted ones. Positions are in pdftohtml's units:
  1.5 per PDF point.

  Failures (exit 1 with -Strict, otherwise printed as warnings):
    - a heading running into its date
    - a project heading wrapping onto a second line
    - Type 3 bitmap fonts
    - a Courses, Study Abroad, or Skills row wrapping onto a short leftover line

  Warnings:
    - a tech line ending in a hyphen, or wrapping onto a short leftover line
    - an unexplained vertical gap between one-line bullets (a phantom blank line)

  The heading and tech-line checks, plus these two, run with -Strict only,
  since the master allows them:
    - a bullet wrapping onto a second line
    - a one-line bullet filling under 90% of the line

  This doesn't replace looking at the rendered page; see CLAUDE.md section 2.

.PARAMETER PdfPath
  Path to the compiled PDF.

.PARAMETER Strict
  Exit 1 on failures and apply the one-line bullet rules. build.ps1 passes this
  for every build except -AllowAnyLength.

.EXAMPLE
  ./scripts/layout_check.ps1 -PdfPath master/master_resume.pdf
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PdfPath,

    [switch]$Strict
)

$ErrorActionPreference = "Stop"

$resolvedPdf = (Resolve-Path -Path $PdfPath -ErrorAction Stop).Path

$rowTolerance = 4        # fragments this close vertically share a row
$minDateGap = 6          # 4pt: anything tighter reads as touching the date
$leftTolerance = 6       # rows this close horizontally share a left edge
$rightColumnMargin = 40  # a fragment this close to the right edge is right-aligned
$leftoverRatio = 0.35    # a wrapped line under this share of the text width is a leftover
$minFillRatio = 0.90
$phantomGapRatio = 1.5

$monthPattern = 'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec|January|February|March|April|June|July|August|September|October|November|December'
$dateEndPattern = "(?:(?:$monthPattern)\.?\s+\d{4}|\b\d{4}|Present)\s*$"
$gluedDatePattern = "[a-z,;)](?:$monthPattern)\.?\s+\d{4}"
$bulletChar = [string][char]0x2022

function Get-Preview([string]$text) {
    $t = $text.Trim()
    return $t.Substring(0, [Math]::Min(60, $t.Length))
}

# --- Read text fragments ---
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("layout_check_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    & pdftohtml -xml -i -q -noframes "$resolvedPdf" (Join-Path $tempDir "out") | Out-Null
    $xmlPath = Join-Path $tempDir "out.xml"
    if (-not (Test-Path $xmlPath)) {
        Write-Error "pdftohtml produced no output for $PdfPath"
    }
    $xmlLines = Get-Content -Path $xmlPath -Encoding UTF8
}
finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

$fontFamilies = @{}
$fragments = New-Object System.Collections.Generic.List[object]
$page = 0
foreach ($line in $xmlLines) {
    if ($line -match '<page number="(\d+)"') {
        $page = [int]$Matches[1]
    }
    elseif ($line -match '<fontspec id="(\d+)".*family="([^"]*)"') {
        $fontFamilies[$Matches[1]] = $Matches[2]
    }
    elseif ($line -match '<text top="(-?\d+)" left="(-?\d+)" width="(\d+)" height="(\d+)" font="(\d+)">(.*)</text>') {
        $top = [int]$Matches[1]
        $left = [int]$Matches[2]
        $width = [int]$Matches[3]
        $fontId = $Matches[5]
        $text = [System.Net.WebUtility]::HtmlDecode(($Matches[6] -replace '<[^>]+>', ''))
        if ($text.Trim().Length -eq 0) { continue }
        $fragments.Add([pscustomobject]@{
                Page = $page; Top = $top; Left = $left; Right = $left + $width
                Text = $text; Font = [string]$fontFamilies[$fontId]
            })
    }
}

# --- Group fragments into visual rows ---
$rows = New-Object System.Collections.Generic.List[object]
$current = $null
foreach ($f in ($fragments | Sort-Object Page, Top, Left)) {
    if ($current -and $current.Page -eq $f.Page -and [Math]::Abs($f.Top - $current.Top) -le $rowTolerance) {
        $current.Frags += $f
    }
    else {
        $current = [pscustomobject]@{ Page = $f.Page; Top = $f.Top; Frags = @($f) }
        $rows.Add($current)
    }
}
foreach ($r in $rows) {
    $sorted = @($r.Frags | Sort-Object Left)
    $text = ($sorted | ForEach-Object { $_.Text }) -join ' '
    $r | Add-Member -NotePropertyMembers @{
        Frags    = $sorted
        Left     = $sorted[0].Left
        Right    = ($sorted | Measure-Object -Property Right -Maximum).Maximum
        Text     = $text
        IsBullet = $sorted[0].Text.Trim() -eq $bulletChar
    } -Force
}

$textLeft = ($rows | Where-Object { -not $_.IsBullet } | Measure-Object -Property Left -Minimum).Minimum
$textRight = ($rows | Measure-Object -Property Right -Maximum).Maximum
$textWidth = $textRight - $textLeft
$rightColumnEdge = $textRight - $rightColumnMargin

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

# --- Bitmap fonts ---
$fontLines = & pdffonts "$resolvedPdf" 2>$null
$type3Count = @($fontLines | Where-Object { $_ -match 'Type 3' }).Count
if ($type3Count -gt 0) {
    $failures.Add("$type3Count Type 3 bitmap font(s), usually from \$ (write dollar signs as `$\`$`$)")
}

# --- Row-by-row checks ---
$section = ''
$bulletRows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]
    $next = if ($i + 1 -lt $rows.Count -and $rows[$i + 1].Page -eq $row.Page) { $rows[$i + 1] } else { $null }
    $isSectionTitle = $row.Frags[0].Font -match 'CMCSC' -and $row.Frags.Count -eq 1
    if ($isSectionTitle) {
        $section = $row.Text.Trim()
        continue
    }

    if ($row.IsBullet) {
        $bulletRows.Add($row)
        continue
    }

    $last = $row.Frags[-1]
    $hasDate = ($last.Right -ge $rightColumnEdge) -and ($last.Text -match $dateEndPattern) -and ($last.Text -notmatch 'Graduation')

    # The master keeps full tech lists in its headings on purpose (CLAUDE.md
    # section 1), so the heading checks apply only to one-page builds.
    if ($hasDate -and -not $Strict) { continue }

    if ($hasDate) {
        # Fragments split by font, so a collision is a tiny gap between fragments.
        if ($row.Frags.Count -ge 2) {
            $gap = $last.Left - $row.Frags[-2].Right
            if ($gap -lt $minDateGap) {
                $failures.Add("Heading runs into its date: `"$(Get-Preview $row.Text)...`" (page $($row.Page))")
            }
        }
        # Same-font fragments merge, so also look for a word glued to a month.
        if ($last.Text -cmatch $gluedDatePattern) {
            $failures.Add("Heading runs into its date: `"$(Get-Preview $last.Text)...`" (page $($row.Page))")
        }
        # A wrapped project heading: the next line starts at the same left edge
        # and, unlike a job's tech line, has nothing right-aligned on it.
        if ($next -and -not $next.IsBullet -and [Math]::Abs($next.Left - $row.Left) -le $leftTolerance -and $next.Right -lt $rightColumnEdge) {
            $failures.Add("Project heading wraps: `"$(Get-Preview $row.Text)...`" -> `"$(Get-Preview $next.Text)`" (page $($row.Page))")
        }
        continue
    }

    # A job's tech line: two fragments far apart, with the location at the right.
    $hasLocation = $row.Frags.Count -ge 2 -and $last.Right -ge $rightColumnEdge -and ($last.Left - $row.Frags[-2].Right) -ge $minDateGap
    if ($hasLocation -and $row.Frags[0].Font -match 'CMTI') {
        if (-not $Strict) { continue }
        if ($row.Frags[-2].Text.TrimEnd() -match '-$') {
            $warnings.Add("Tech line ends in a hyphen: `"$(Get-Preview $row.Frags[-2].Text)...`" (page $($row.Page))")
        }
        if ($next -and -not $next.IsBullet -and [Math]::Abs($next.Left - $row.Left) -le $leftTolerance -and ($next.Right - $next.Left) -lt ($textWidth * $leftoverRatio)) {
            $warnings.Add("Tech line wraps onto a short leftover line: `"$($next.Text.Trim())`" (page $($row.Page))")
        }
        continue
    }

    # Label rows like "Courses: ..." or a Skills row, followed by a short leftover.
    $isLabelRow = ($section -match 'Skills' -and $row.Frags[0].Font -match 'CMBX') -or ($row.Text -match '^\s*(Courses|Honors|Study Abroad):')
    if ($isLabelRow -and $next -and -not $next.IsBullet -and [Math]::Abs($next.Left - $row.Left) -le $leftTolerance) {
        $nextIsLabelRow = ($next.Frags[0].Font -match 'CMBX') -or ($next.Text -match '^\s*[A-Z][A-Za-z /&]+:\s')
        if (-not $nextIsLabelRow -and ($next.Right - $next.Left) -lt ($textWidth * $leftoverRatio)) {
            $failures.Add("Row wraps onto a short leftover line: `"$($next.Text.Trim())`" (page $($row.Page))")
        }
    }
}

# --- Bullet checks: wrapping, fill, phantom gaps ---
if ($bulletRows.Count -gt 0) {
    $wrapped = @{}
    for ($i = 0; $i -lt $rows.Count - 1; $i++) {
        $row = $rows[$i]
        $next = $rows[$i + 1]
        if ($row.IsBullet -and $next.Page -eq $row.Page -and -not $next.IsBullet -and [Math]::Abs($next.Left - $row.Frags[1].Left) -le $leftTolerance) {
            $wrapped[$i] = $true
        }
    }

    $bulletRight = ($bulletRows | Measure-Object -Property Right -Maximum).Maximum
    $indexOf = @{}
    for ($i = 0; $i -lt $rows.Count; $i++) { $indexOf[$rows[$i]] = $i }

    $gaps = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $rows.Count - 1; $i++) {
        if ($rows[$i].IsBullet -and $rows[$i + 1].IsBullet -and $rows[$i].Page -eq $rows[$i + 1].Page -and -not $wrapped.ContainsKey($i)) {
            $gaps.Add([pscustomobject]@{ Row = $rows[$i]; Next = $rows[$i + 1]; Gap = $rows[$i + 1].Top - $rows[$i].Top })
        }
    }
    if ($gaps.Count -ge 3) {
        $sortedGaps = @($gaps | Sort-Object Gap)
        $typicalGap = $sortedGaps[[int]($sortedGaps.Count / 2)].Gap
        foreach ($g in $gaps) {
            if ($g.Gap -gt ($typicalGap * $phantomGapRatio)) {
                $warnings.Add("Unexplained gap after bullet (possible phantom blank line): `"$(Get-Preview ($g.Row.Text -replace $bulletChar, ''))...`" (page $($g.Row.Page))")
            }
        }
    }

    if ($Strict) {
        foreach ($b in $bulletRows) {
            $preview = Get-Preview ($b.Text -replace $bulletChar, '')
            if ($b.Frags.Count -lt 2) { continue }
            if ($wrapped.ContainsKey($indexOf[$b])) {
                $warnings.Add("Bullet wraps onto a second line: `"$preview...`"")
                continue
            }
            $bulletLeft = $b.Frags[1].Left
            $fill = ($b.Right - $bulletLeft) / ($bulletRight - $bulletLeft)
            if ($fill -lt $minFillRatio) {
                $warnings.Add("Bullet fills only $([Math]::Round($fill * 100))% of its line: `"$preview...`"")
            }
        }
    }
}

# --- Report ---
if ($failures.Count -gt 0) {
    Write-Host "Layout defect(s):"
    $failures | ForEach-Object { Write-Host "  $_" }
}
if ($warnings.Count -gt 0) {
    Write-Host "Layout warning(s):"
    $warnings | ForEach-Object { Write-Host "  $_" }
}
if ($Strict -and $failures.Count -gt 0) {
    exit 1
}
exit 0
