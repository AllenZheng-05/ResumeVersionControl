#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Compiles a resume .tex file to PDF and reports its page count.

.DESCRIPTION
  Runs pdflatex twice (stable references/layout), then pdfinfo to read the
  page count. Scans the compile log for "Overfull \hbox" warnings -- LaTeX's
  signal that a line/cell ran past the margin, i.e. text is clipping off the
  side of the page -- and fails the build if any are found, regardless of
  -AllowAnyLength. Cleans up .aux/.log/.out afterward, leaving only the .tex
  and .pdf. Also exits non-zero if the PDF is not exactly one page, unless
  -AllowAnyLength is passed (used for the master resume, which is allowed to
  span multiple pages).

  Also extracts the compiled PDF text (pdftotext -layout) and flags bullets
  that wrap to a second/third line whose trailing line is much shorter than
  the page's wrap width -- a sign of wasted whitespace worth tightening or
  expanding -- and bullets spanning more than 2 lines outright. These print
  as warnings, not build failures, since judgment calls (fabrication risk,
  keyword tradeoffs) belong to a human, not the script.

  For single-page builds (not -AllowAnyLength), also reports how much
  vertical whitespace is left at the bottom of the page. This runs a
  throwaway second compile of the .tex with a `\typeout` probe injected
  right before `\end{document}`, reading TeX's own `\pagegoal`/`\pagetotal`
  (the target page height and the height of content placed so far) to print
  the difference in inches. Use this to decide whether a tailored resume has
  room for another bullet/project/section before it would overflow to a
  second page.

  Finally runs layout_check.ps1 for defects that compile cleanly but look
  wrong on the page. They fail the build unless -AllowAnyLength is passed.

.PARAMETER TexPath
  Path to the .tex file to compile (e.g. resumes/software-engineer/Acme_SWE_2026-08-04/Jane_Doe_Resume.tex).

.PARAMETER AllowAnyLength
  Skip the one-page enforcement (use for master/master_resume.tex).

.EXAMPLE
  ./scripts/build.ps1 -TexPath resumes/software-engineer/Acme_SWE_2026-08-04/Jane_Doe_Resume.tex

.EXAMPLE
  ./scripts/build.ps1 -TexPath master/master_resume.tex -AllowAnyLength
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$TexPath,

    [switch]$AllowAnyLength
)

$ErrorActionPreference = "Stop"

$resolvedTex = Resolve-Path -Path $TexPath -ErrorAction Stop
$texDir = Split-Path -Path $resolvedTex -Parent
$texFile = Split-Path -Path $resolvedTex -Leaf
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($texFile)

Push-Location $texDir
try {
    for ($i = 1; $i -le 2; $i++) {
        & pdflatex -interaction=nonstopmode -halt-on-error "$texFile" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "pdflatex failed on pass $i for $TexPath. See $baseName.log for details."
        }
    }

    $pdfPath = Join-Path $texDir "$baseName.pdf"
    if (-not (Test-Path $pdfPath)) {
        Write-Error "Expected PDF not found at $pdfPath"
    }

    $pdfInfoOutput = & pdfinfo "$baseName.pdf"
    $pagesLine = $pdfInfoOutput | Where-Object { $_ -match "^Pages:\s*(\d+)" }
    $pageCount = [int]($Matches[1])

    $logPath = Join-Path $texDir "$baseName.log"
    $overfullLines = @()
    if (Test-Path $logPath) {
        $overfullLines = Select-String -Path $logPath -Pattern '^Overfull \\hbox' |
            ForEach-Object { $_.Line }
    }

    foreach ($ext in @("aux", "log", "out", "fls", "fdb_latexmk", "synctex.gz")) {
        $artifact = Join-Path $texDir "$baseName.$ext"
        if (Test-Path $artifact) {
            Remove-Item $artifact -Force
        }
    }

    Write-Host "Compiled $TexPath -> $baseName.pdf ($pageCount page(s))"

    if ($overfullLines.Count -gt 0) {
        Write-Host "Overfull hbox warning(s) -- text is running past the right margin:"
        $overfullLines | ForEach-Object { Write-Host "  $_" }
        Write-Error "$TexPath has $($overfullLines.Count) Overfull \hbox warning(s); text is clipping off the page. Fix the offending line(s) before proceeding."
    }

    if (-not $AllowAnyLength -and $pageCount -ne 1) {
        Write-Error "$TexPath compiled to $pageCount page(s); tailored resumes must be exactly 1 page."
    }

    # Line-wrap efficiency check: group pdftotext output into bullet
    # paragraphs (a line starting with the itemize bullet U+2022, plus any
    # following continuation lines -- identified by deeper indentation than
    # the bullet itself, since pdftotext's blank-line paragraph heuristic is
    # unreliable with this template's tight \vspace tweaks), then flag short
    # trailing lines and 3+ line bullets as wasted-whitespace candidates.
    $wrapWarnings = @()
    $bulletChar = [char]0x2022
    # Read through a file, not stdout: Windows PowerShell decodes piped output
    # with the console code page, which turns the bullet into something else.
    $textFile = [System.IO.Path]::GetTempFileName()
    & pdftotext -layout -enc UTF-8 "$baseName.pdf" "$textFile" 2>$null
    $textLines = Get-Content -Path $textFile -Encoding UTF8
    Remove-Item $textFile -Force
    if ($textLines) {
        $groups = @()
        $current = $null
        $bulletIndent = 0
        foreach ($rawLine in $textLines) {
            $trimmed = $rawLine.Trim()
            if ($trimmed.Length -eq 0) { continue }
            $leading = $rawLine.Length - $rawLine.TrimStart().Length
            $hasWideGap = $trimmed -match '\s{3,}'
            if ($trimmed.StartsWith($bulletChar)) {
                if ($current) { $groups += , $current }
                $bulletIndent = $leading
                $current = @($trimmed.TrimStart($bulletChar).Trim())
            }
            elseif ($current -and $leading -gt $bulletIndent -and -not $hasWideGap) {
                $current += $trimmed
            }
            else {
                if ($current) { $groups += , $current }
                $current = $null
            }
        }
        if ($current) { $groups += , $current }

        # Sample from every bullet's first line (not just ones that wrapped) so
        # the width estimate stays stable as bullets get tightened over time.
        $fullLineSamples = $groups | ForEach-Object { $_[0].Length }
        if ($fullLineSamples.Count -gt 0) {
            $baselineWidth = ($fullLineSamples | Measure-Object -Maximum).Maximum
            foreach ($g in $groups) {
                if ($g.Count -ge 2) {
                    $lastLen = $g[-1].Length
                    if ($lastLen -lt ($baselineWidth * 0.5)) {
                        $preview = $g[0].Substring(0, [Math]::Min(55, $g[0].Length))
                        $wrapWarnings += "short trailing line ($lastLen/$baselineWidth chars) -- `"$preview...`" -> `"$($g[-1])`""
                    }
                }
                if ($g.Count -ge 3) {
                    $preview = $g[0].Substring(0, [Math]::Min(55, $g[0].Length))
                    $wrapWarnings += "spans $($g.Count) lines (style guide max is 2) -- `"$preview...`""
                }
            }
        }
    }

    if ($wrapWarnings.Count -gt 0) {
        Write-Host "Line-wrap efficiency warning(s) -- review for wasted whitespace:"
        $wrapWarnings | ForEach-Object { Write-Host "  $_" }
    }

    # Page-fill check: how much vertical whitespace is left at the bottom of
    # a single-page resume. Injects `\typeout{PAGE-REMAINING-PT:...}` right
    # before `\end{document}` in a throwaway copy and reads TeX's own
    # \pagegoal (page target height) minus \pagetotal (content height placed
    # so far) from the log. Only meaningful for exactly-one-page builds.
    if (-not $AllowAnyLength -and $pageCount -eq 1) {
        $originalContent = Get-Content -Path $resolvedTex -Raw
        if ($originalContent -match '\\end\{document\}') {
            $probeBase = "$baseName.pagecheck"
            $probeTexPath = Join-Path $texDir "$probeBase.tex"
            $probeContent = $originalContent -replace '\\end\{document\}', "\typeout{PAGE-REMAINING-PT:\the\dimexpr\pagegoal-\pagetotal\relax}`n\end{document}"
            Set-Content -Path $probeTexPath -Value $probeContent -NoNewline

            & pdflatex -interaction=nonstopmode -halt-on-error "$probeBase.tex" | Out-Null

            $probeLog = Join-Path $texDir "$probeBase.log"
            if (Test-Path $probeLog) {
                $remMatch = Select-String -Path $probeLog -Pattern 'PAGE-REMAINING-PT:(-?[0-9.]+)pt' |
                    Select-Object -Last 1
                if ($remMatch) {
                    $remainingPt = [double]$remMatch.Matches[0].Groups[1].Value
                    if ($remainingPt -lt 2000) {
                        $remainingIn = [math]::Round($remainingPt / 72.27, 2)
                        Write-Host "Page fill: ~$remainingIn in of whitespace remaining at the bottom of page 1"
                    }
                    else {
                        Write-Host "Page fill: could not determine (page builder never set \pagegoal -- document too short)"
                    }
                }
            }

            foreach ($ext in @("aux", "log", "out", "fls", "fdb_latexmk", "synctex.gz", "pdf", "tex")) {
                $artifact = Join-Path $texDir "$probeBase.$ext"
                if (Test-Path $artifact) {
                    Remove-Item $artifact -Force
                }
            }
        }
    }

    # Layout check: defects that compile cleanly but look wrong on the page.
    # They fail one-page builds and only warn under -AllowAnyLength.
    & (Join-Path $PSScriptRoot "layout_check.ps1") -PdfPath $pdfPath -Strict:(-not $AllowAnyLength)
    if ($LASTEXITCODE -ne 0) {
        Write-Error "$TexPath has layout defects. Fix them before proceeding."
    }
}
finally {
    Pop-Location
}
