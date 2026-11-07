# Resume Version-Control Pipeline

This repo tracks the user's resume history: one comprehensive **master resume**
that every application-specific resume is generated from. Read this file fully
before doing any resume work — it's the only memory of how this pipeline works
across sessions.

## 0. Setup (fill in once)

- **Resume file name:** `Jane_Doe_Resume`
  <!-- Replace with <FirstName>_<LastName>_Resume. Every tailored resume is
       saved as <this>.tex / <this>.pdf, and that PDF filename is what
       recruiters see when you upload it. -->

Throughout this file, `<ResumeName>` means the value above.

**First-run check:** if `master/master_resume.tex` still contains the
placeholder "Jane Doe" / "Example Corp" content, the user hasn't set up their
master yet. Before doing anything else, offer to build it with them: ask for
their existing resume (pasted text, a PDF/.docx/.tex file path, or a LinkedIn
export) and transcribe it into the template's macros. Then ask follow-up
questions for each entry to fill out extra bullets and `\resumeNotes` (metrics,
stack, team size, dates). The usual approval gate in section 1 still applies.
Also update the Setup value above if it's still `Jane_Doe_Resume`.

## Repo structure

```
/master/
  master_resume.tex                 # single source of truth, ALL content, no 1-page limit
/resumes/
  <role-category>/                  # kebab-case, e.g. software-engineer, data-science,
                                     # product-management, quant-finance
    <Company>_<RoleTitle>_<YYYY-MM-DD>/
      <ResumeName>.tex
      <ResumeName>.pdf
      job_posting.md                # record of the posting itself
  archive/
    <role-category>/
      <Company>_<RoleTitle>_<YYYY-MM-DD>/   # archived applications, moved here intact
/scripts/
  build.ps1                         # compile a resume .tex, verify page count
  layout_check.ps1                  # visual defects in a compiled PDF (run by build.ps1)
  ats_check.ps1                     # local ATS-parseability + JD-keyword-match check
  new_application.ps1               # prior-application check + new application folder
```

Category folders and application folders are created on demand — don't pre-create
empty ones.

## 1. Updating the master resume

When the user describes a new accomplishment, or points at a repo/project they
built, add it to `master/master_resume.tex` in the matching section (Experience,
Projects and Awards, Leadership, Skills, etc.):

- Reuse the existing macros: `\resumeSubheading` (jobs), `\resumeProjectHeading`
  (projects), `\resumeSubheadingTwo` (leadership), `\resumeItem` (bullets),
  `\resumeNotes` (dense raw-material paragraph per entry, see below).
- `\resumeSubheading` heading layout/argument order (also used in every
  tailored resume, since they share this preamble):
  ```
  \resumeSubheading
    {\textbf{<Job Title>} $|$ <Company/Organization>}{<Date Range>}
    {<Comma-separated skills/tech list, no \emph -- the macro italicizes it>}{<Location>}
  ```
  i.e. row 1 is Title | Company with the date at the right; row 2 is the
  skills list with the location at the right. The left column is a
  `tabularx` `X` column, so it wraps instead of overflowing/clipping if the
  skills list is long.
- **Master headings carry the full tech list.** List everything truthfully used,
  however long it runs, and don't trim it to fit. Tailored resumes pick the subset
  relevant to the posting. Headings wrapping or running into their dates in the
  master PDF is expected, since it's never submitted.
- **Tailored headings must fit.** `\resumeProjectHeading`'s `@{}X r@{}` columns
  have no gap between them, so a project heading has to fit on one line or it runs
  into the date ("GitHub ActionsSept 2026"). A job's tech line must not end in a
  hyphenated word or a single leftover word.
- **Ordering:** within every section (master and tailored resumes alike),
  order entries by most recent **start** date first — not by end date, and
  "Present" doesn't jump an entry to the top. A single-date entry like a hackathon
  uses that date as its start.
- **Write entries to sound as impressive as truthfully possible**: lead with
  system-level impact, not a dry list of duties. If it's unclear how work on a team
  project was split, ask rather than guessing what the user can claim. Every claim
  and metric still has to be true.
- Follow the **bullet-writing style guide** below for every bullet.
- The master resume has no length limit — always add the fullest, most detailed
  version of an achievement here (as many bullets per item as needed). Tailored
  resumes trim it down later, not the other way around.
- **Don't turn every fact into its own bullet.** A tailored resume caps each item
  at 4 bullets, so a job/project entry with 8-10 master bullets mostly just
  creates choices that get discarded, not material that gets used. Reserve real
  `\resumeItem` bullets for the entry's strongest, most broadly-relevant
  achievements. For everything else — a detail that's only relevant to specific
  job descriptions, a fact that's naturally part of a larger idea (e.g. "wrote
  unit tests" doesn't deserve its own line), or an alternate phrasing of an
  existing bullet for a different angle — put it in that entry's **Notes**
  subsection instead (see below).

### Notes subsection (raw material for tailoring)

Each `\resumeSubheading` / `\resumeProjectHeading` / `\resumeSubheadingTwo` entry
may have a `\resumeNotes{...}` block directly after its `\resumeItemListEnd`,
rendered as a small italicized paragraph (still visible in the compiled master
PDF, but visually distinct from real bullets so it doesn't read as a bullet
list). It's a dense, semicolon-separated bank of facts, metrics, and
alternate phrasings for that entry — not meant to be copied verbatim into a
tailored resume, but pulled from and reworded into a proper bullet when a
specific job posting calls for it.

- Still never fabricate a metric or detail — the same honesty rule applies
  inside Notes as it does for bullets.
- When generating a tailored resume (section 2), read both the bullets *and*
  the Notes for every entry you're pulling from — a JD-relevant fact often
  lives in Notes rather than in an existing bullet, and should be promoted
  into a real one-line `\resumeItem` at that point, not pasted in as-is.
- Notes are exempt from the bullet-writing style guide's verb/format rules
  (they're not sentences meant to ship) but should still be truthful and
  specific enough to write a real bullet from later.
- Never fabricate a metric or detail. If the user's description doesn't have
  enough specifics (numbers, dates, stack) to write a strong bullet, ask.
- **Before writing anything to `master/master_resume.tex`, show the proposed
  bullet/section text in chat and get the user's approval, rejection, or edit
  first.** This gate is specific to the master resume — tailored-resume
  generation (section 2 below) does not require it. It's fine to test-compile
  drafts in a scratch file outside the repo to check line-wrap/length before
  presenting, since that doesn't touch the tracked file.
- After the user approves and the edit is made, compile to sanity-check it
  still builds (page count doesn't matter for the master):
  ```
  ./scripts/build.ps1 -TexPath master/master_resume.tex -AllowAnyLength
  ```
- Commit: `git add master/master_resume.tex` and commit as
  `Add <achievement> to master resume`. `master/master_resume.pdf` is gitignored,
  since it's rebuilt on every compile and never submitted.

### Bullet-writing style guide

1. **Lead with a strong past-tense verb** (Built, Engineered, Architected,
   Designed, Implemented, Increased, Reduced, Automated, Migrated, Launched,
   Delivered). Never open with "Worked on," "Helped," "Responsible for,"
   "Assisted with."
2. **Achievement over duty** — describe the outcome/what changed, not the
   assignment. ("Cut deploy time to 5 minutes," not "Was responsible for
   deployments.")
3. **Quantify honestly** — latency, scale, counts, percentages, dollar
   amounts, version numbers. If a real number isn't known, ask rather than
   invent one.
4. **One idea per bullet.** If a sentence needs "and" to stitch two distinct
   achievements together, split it into two bullets — the master resume has
   no bullet-count limit per item.
5. **Bold sparingly** — key technologies/platforms and the standout metric
   only, not whole phrases. Over-bolding dilutes emphasis and widens lines.
6. **No inline project-name labels** inside a bullet (e.g. "MyApp
   (Kotlin, Android): ..."). Let the verb + tech convey context; the
   heading's `\emph{...}` tech line already sets it.
7. **Cut filler/buzzwords**: responsible for, helped, assisted, in order to,
   utilized, leveraged, various, successfully, cutting-edge, state-of-the-art,
   passionate, detail-oriented, synergy.
8. **Line length**: tailored bullets are **one line, never wrapped**. Master
   bullets may run to 2 lines, since they're raw material. Bullet *count* differs
   too: the master resume allows unlimited bullets per item; tailored/application
   resumes (section 2) allow at most 4 bullets per item.
9. **Fill the line**: pack each one-line bullet with as much real detail as
   fits, to roughly 96-100% of the line width. Treat anything above ~99.9% as
   risky, since it can create a phantom blank line. Never shorten a bullet that
   already fits on one line: that frees no vertical space and just throws away
   detail. Save space by cutting whole bullets that don't show off an important
   skill.

## 2. Generating a tailored resume for a job application

Inputs from the user: job posting URL and/or JD text, role category, and
ideally company/role title. Fill in whatever else is available (pay range,
job type, start/end dates) — leave the rest blank in `job_posting.md`.

**Always generate fresh from the master resume — never start from a
previously generated resume in that category**, even a very similar one. This
keeps every resume in sync with the latest master content and avoids carrying
over tailoring choices that were specific to a different job. If a wording or
selection choice turns out to work well across applications, fold that
improvement into the master resume itself (or note it below), not into just
one derived file.

**Never edit a submitted application's folder.** It's the record of what was
sent, so systemic fixes go only in new resumes and the master. A folder whose
`Date Applied` is blank hasn't been submitted and can still be edited.

**Credentials from before college** stay out of the college Education entry, so
they don't read as earned there. List them in Skills or in their own labeled entry.

Steps:

0. Set up the folder, which also checks for a prior application:
   ```
   ./scripts/new_application.ps1 -Company <Company> -RoleTitle <RoleTitle> -Category <category> -PostingUrl <url>
   ```
   It searches `resumes/` and `resumes/archive/` by company and posting URL, and
   stops if either matches. Tell the user and don't build a new resume unless they
   say to; a different role at the same company is fine, so mention the earlier
   one and rerun with `-Force`. Also check `job_posting.md` for the req ID if the
   posting has one.
1. Get the JD: `WebFetch` the URL if given, or use pasted text.
2. Read the full `master/master_resume.tex`.
3. Select and reorder: pick the subset of experience, projects, and skills
   most relevant to this JD and role category. Reword bullets to mirror the
   JD's language/keywords **only where it stays truthful** — never invent a
   skill, technology, or metric that isn't in the master.
4. Fill in the two files step 0 created in
   `resumes/<category>/<Company>_<RoleTitle>_<YYYY-MM-DD>/`:
   - `<ResumeName>.tex` — already has the master's preamble and header; add the
     trimmed content, with no `\resumeNotes` blocks.
   - `job_posting.md`:
     ```markdown
     # <Company> — <Role Title>

     - Role Category: <category>
     - Job Type: Internship | Co-op | Full-time
     - Posting URL: <url if given>
     - Date Applied: <blank until the user confirms it's submitted>
     - Date Opened: <if known>
     - Pay Range: <if listed>
     - Start Date: <if internship/co-op>
     - End Date: <if internship/co-op>

     ## Job Description

     <pasted or summarized JD text>

     ## ATS Keywords

     ### Required

     <list of exact-phrase hard skills, tools, certs, and requirement terms
     from the JD's Basic/Required Qualifications -- see step 8>

     ### Preferred

     <same, from the JD's Preferred Qualifications; if the JD doesn't separate
     them, use one flat list with no subheadings>

     ## Tailoring Notes

     <see below>
     ```
5. Cap each item at **4 bullets max**, each **exactly one line** — see the
   bullet-writing style guide in section 1. Then compile and enforce exactly
   one page:
   ```
   ./scripts/build.ps1 -TexPath resumes/<category>/<application>/<ResumeName>.tex
   ```
   - **Over one page**: trim the least-relevant bullet or project first.
     Don't shrink fonts/margins to force a fit.
   - **Noticeable trailing whitespace** (whole section is sparse): add back a
     relevant bullet, project, or skill from the master before resorting to
     spacing tweaks.
   - **Page-fill metric (the "Page fill: ~X in remaining" line `build.ps1`
     prints)**: this is informational only, not a target to hit or a ceiling
     to stay under. A negative value (content running past TeX's page goal)
     is fine as long as `build.ps1` still reports exactly 1 page with no
     Overfull \hbox errors — don't trim real, relevant content just to pull
     the number back toward zero.
   - **Line-wrap efficiency warnings** printed by `build.ps1` (a bullet whose
     wrapped line is mostly empty, or that spans 3+ lines): fix each one by
     tightening the wording to fit on one line. If that would sacrifice a real
     detail or read awkwardly, cut the bullet or swap in a different one. Never
     pad with filler (see the style guide's filler rule). Re-run the build after
     each edit; the warning list — and its width baseline, which is resampled
     from the remaining bullets — updates each time.
   - **Visual check**: `build.ps1` runs `layout_check.ps1` automatically, but
     passing it isn't enough. Render the PDF (`pdftoppm -r 80 -png`), open the
     image, and look for these defects before running ATS or committing:
     - A Courses or Skills row wrapping onto a second line that holds only one
       or two items.
     - A project heading's tech list running into the date, or hyphenated
       against it ("Genera-tion").
     - An experience tech line ending in a hyphenated word or a single leftover
       word ("Opti-mization", "React").
     - A phantom blank line under a bullet or Courses row that fills the full
       width, which shows up as an unexplained vertical gap.
   - Iterate until it's exactly one page, reasonably full, every bullet is one
     line, and the visual check is clean.
6. Fill in the `## Tailoring Notes` section of `job_posting.md`: which
   experience/project entries were selected (and what got cut and why),
   which bullets were promoted from a `\resumeNotes` block or reworded to
   mirror JD keywords (and which JD keyword each maps to). This is what makes
   the tailoring decisions legible later — the `.tex` diff alone doesn't say *why* a bullet
   was chosen over the master's other options for that entry.
7. Gap check: compare the JD against the master resume. Tell the user about
   any skills/experience the posting wants that aren't in the master, and ask
   whether those are genuine and worth adding (loop back to section 1
   above if so).
8. ATS check (final step, run against the finished `.tex`/`.pdf`, after
   everything above has settled): there's no way to submit to the real ATS a
   given company uses (Workday, Greenhouse, iCIMS, Taleo, etc. are
   proprietary and only reachable through an actual application) or to drive
   a third-party resume-scanner site (no file-upload capability), so this is
   a local approximation instead of the genuine article -- treat its output
   as a useful signal, not a guarantee of a real ATS's behavior.
   - Populate `## ATS Keywords` in `job_posting.md`: pull exact-phrase hard
     skills, tools, certs, and requirement terms from the JD's Basic/Preferred
     Qualifications section -- the literal strings an ATS keyword-matcher
     would search for (e.g. "Kubernetes", "PCI DSS", "computer architecture"),
     not paraphrases.
   - Run:
     ```
     ./scripts/ats_check.ps1 -TexPath resumes/<category>/<application>/<ResumeName>.tex
     ```
     It extracts the PDF's text the crude way most ATS parsers do (linear,
     no layout/columns) to catch real parseability failures (garbled text,
     unrecognized section headers, missing contact info), then reports which
     `## ATS Keywords` phrases were found vs. missing in that text, with a
     match score. The exact score is the one to compare across applications.
     A second score counts singular/plural and hyphen/space variants ("agents"
     for "AI-agent"), which a strict ATS may not accept. `### Required` and
     `### Preferred` lists each get their own score.
   - Report the score and any missing keywords to the user. Never fabricate a
     skill/tool just to raise the score -- a genuine miss is either a gap to
     flag back to step 7, or a keyword to reach for the next time the master
     resume gains that capability for real.
9. Commit the new application folder: `Add resume for <Company> <Role>`.

## 3. Archiving applications

When the user asks to archive a batch (e.g. "archive all Summer 2027
internship applications" after accepting an offer):

1. Search `job_posting.md` under every `resumes/<category>/*/` (not just one
   category) for matches on the given criteria — job type, start/end date
   range, company, etc.
2. `git mv` each matching application folder to the mirrored path under
   `resumes/archive/<category>/`.
3. Commit: e.g. `Archive Summer 2027 internship applications`.

Archived applications keep all three files intact — nothing is deleted, they're
just moved out of the active view. When listing/browsing current applications,
skip `resumes/archive/` unless the user asks to include it.

## Naming conventions

- Category folders: kebab-case role type (`software-engineer`,
  `data-science`, `product-management`, `quant-finance`, ...).
- Application folders: `<Company>_<RoleTitle>_<YYYY-MM-DD>`. The date is the
  day the folder was created and is never renamed. The submission date goes in
  `Date Applied` in `job_posting.md`, which stays blank until the user confirms
  it's submitted.
- Files inside an application folder are always named exactly
  `<ResumeName>.tex`, `<ResumeName>.pdf`, `job_posting.md`.
- Commit messages: `Add <achievement> to master resume`,
  `Add resume for <Company> <Role>`, `Archive <batch description>`.

## Compiling

Requires a LaTeX distribution's `pdflatex` (MiKTeX or TeX Live) plus Poppler's
`pdfinfo`, `pdftotext`, `pdftohtml`, `pdffonts`, and `pdftoppm` on PATH, and
PowerShell to run the scripts. Always
compile through `scripts/build.ps1` rather than calling `pdflatex` directly,
so the page-count check, the overfull-hbox (text clipping off the page) check,
the line-wrap efficiency check, and artifact cleanup all happen consistently.
A build failing on an "Overfull \hbox" warning means some line/cell is running
past the margin — fix the content (or rely on the `X`-column wrap in the
heading macros) rather than shrinking margins/fonts to hide it.

`build.ps1` also prints (non-fatal) line-wrap efficiency warnings: it runs
`pdftotext -layout` on the compiled PDF, groups wrapped bullet text back
together, and flags bullets whose trailing line is under ~50% of the page's
typical line width, plus any bullet spanning 3+ lines. These are wasted
whitespace that could otherwise hold more relevant content — see step 5 of
section 2 for how to act on them.

For single-page (non-`-AllowAnyLength`) builds, `build.ps1` also reports how
much vertical whitespace is left at the bottom of the page: it injects a
`\typeout` probe reading TeX's own `\pagegoal`/`\pagetotal` right before
`\end{document}` in a throwaway copy, and prints the difference in inches.
Use this during step 5 of section 2 to decide whether a tailored resume has
room for another bullet/project/section before it would overflow to page 2.

`build.ps1` ends by running `scripts/layout_check.ps1`, which reads text positions
from `pdftohtml -xml` and fonts from `pdffonts`. It fails one-page builds on a
heading running into its date, a wrapped project heading, Type 3 bitmap fonts, or
a Courses or Skills row wrapping onto a short leftover line. It also warns about
tech-line wraps, phantom blank lines, wrapped bullets, and bullets under 90% of
the line. Under `-AllowAnyLength` the failures are only warnings, and the heading,
tech-line, and bullet checks are skipped because the master allows them. It only
reads the PDF, so it's safe on submitted resumes; just don't run `build.ps1` on
those, because that recompiles them.

`scripts/ats_check.ps1` (step 8 of section 2) is separate from `build.ps1`:
it runs after the resume is otherwise finished, extracting the compiled
PDF's text without layout reconstruction (closer to how ATS parsers actually
ingest a resume) and checking it against `job_posting.md`'s `## ATS
Keywords` list.

The scripts in `scripts/` are safe, routine steps, so run them without asking
first. That covers only these scripts: git operations and file deletion still
need normal judgment.

### LaTeX and tooling gotchas

- Write dollar signs as `$\$$`, never `\$`. On some LaTeX setups `\$` pulls in a
  Type 3 bitmap font, which can look rough in print and is less reliable for ATS
  text extraction. The build fails if one appears.
- Don't write LaTeX through Bash heredocs: `\\` can collapse to `\`, which silently
  merges the Skills rows onto one line. Use the Write or Edit tools instead.
