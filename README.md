# Resume Version Control

A Git-based workflow for keeping **one master resume** with everything you've
ever done, then generating a **tailored one-page resume for each job
application** from it. You do this with [Claude Code](https://claude.com/claude-code).

Every application gets its own folder with the exact resume you sent, a copy of
the job posting, and notes on why each bullet was chosen. That gives you a
searchable history of every application, and a new resume always starts from
your latest, most complete material.

```
master/master_resume.tex   ← everything, no length limit (you maintain this)
        │
        ▼  "Tailor my resume for <job posting URL>"
resumes/software-engineer/Acme_SoftwareEngineerIntern_2026-10-13/
    Jane_Doe_Resume.tex    ← exactly 1 page, picked and reworded for this JD
    Jane_Doe_Resume.pdf    ← what you upload
    job_posting.md         ← JD, ATS keywords, tailoring notes, dates, pay
```

## What's in here

| Path | Purpose |
| --- | --- |
| `CLAUDE.md` | Instructions Claude Code reads every session: workflow, bullet style guide, naming rules. **This is the workflow.** |
| `master/master_resume.tex` | Your master resume, in LaTeX ([Jake's Resume](https://github.com/sb2nov/resume) template). Starts with placeholder content. |
| `scripts/build.ps1` | Compiles a `.tex` and checks it. It fails if the resume isn't exactly one page, if text runs off the margin, or if `layout_check.ps1` finds a defect, and warns about bullets that waste a line. |
| `scripts/layout_check.ps1` | Catches defects that compile fine but look wrong: headings running into their dates, leftover words on Skills rows, bitmap fonts, phantom blank lines, and under-filled bullets. `build.ps1` runs it for you. |
| `scripts/ats_check.ps1` | A local approximation of an applicant tracking system (ATS) scan. It extracts the PDF text the way ATS parsers do, checks that your contact info and section headers survive, and scores how many of the job description's keywords appear, with exact and with-variants scores and separate required and preferred scores. |
| `scripts/new_application.ps1` | Checks for a prior application to the same company or posting, then creates the application folder with your current preamble and a `job_posting.md` template. |
| `.claude/settings.json` | Lets Claude run the scripts without asking each time. |

## Requirements

- **Claude Code** (CLI, desktop app, or VS Code/JetBrains extension)
- **PowerShell** (built into Windows; on macOS/Linux install
  [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell))
- **pdflatex**, from [MiKTeX](https://miktex.org/) (Windows) or
  [TeX Live](https://tug.org/texlive/)/MacTeX
- **pdfinfo**, **pdftotext**, **pdftohtml**, and **pdffonts**, from
  [Poppler](https://poppler.freedesktop.org/).
  MiKTeX ships them on Windows. On macOS run `brew install poppler`; on
  Debian/Ubuntu run `apt install poppler-utils`.
- **Git**

Check that they're all on your PATH:

```
pdflatex --version
pdfinfo -v
pdftotext -v
pdftohtml -v
pdffonts -v
```

## Setup

1. **Get your own copy** by cloning or forking this repo (or "Use this
   template" on GitHub), and **keep it private**. Your resume history includes
   your phone number and every company you applied to. If you downloaded a zip
   instead, turn it into a repo:
   ```
   git init
   git add -A
   git commit -m "Initial commit"
   ```
2. **Set your file name.** In `CLAUDE.md`, under *0. Setup*, change
   `Jane_Doe_Resume` to `<FirstName>_<LastName>_Resume`. That's the file name
   recruiters will see on every PDF you upload.
3. **Fill in your master resume.** The easiest way is to open Claude Code in
   this folder and say:
   > Set up my master resume from my current resume: `<paste text, or give a path to a PDF/.docx/.tex>`

   Claude converts it into the template's format, asks follow-up questions to
   get missing numbers and details, and shows you every change before writing
   it. You can also edit `master/master_resume.tex` by hand instead.
4. **Build it** to make sure it compiles:
   ```
   ./scripts/build.ps1 -TexPath master/master_resume.tex -AllowAnyLength
   ```

## Day-to-day usage

You run everything by talking to Claude Code from this folder. `CLAUDE.md`
tells it the rules, so short requests work.

### Add something to your master resume

> I just finished my internship at Acme. I built X, which cut Y from 3s to 200ms. Add it to my master.

> Add this project to my master resume: https://github.com/me/my-project

Claude drafts the bullets following the style guide (strong verb, a real
number, at most 2 lines). It **shows you the draft before writing**, then
compiles and commits once you approve. If you don't give it real numbers, it
asks for them. It won't make them up.

**Put everything in the master.** It has no length limit, headings can list your
full tech stack (tailored resumes pick what's relevant), and each entry has a
`\resumeNotes{...}` block for extra facts, metrics, and alternate wordings.
Notes aren't bullets yet, but they get turned into bullets when a job posting
calls for them. The more material is in the master, the better your tailored
resumes get.

### Tailor a resume for a job

> Tailor my resume for this posting: https://company.com/careers/12345 — software-engineer category

or paste the job description text if the link needs a login. Claude then:

1. Checks whether you've already applied there, then reads the posting and your
   **whole** master resume, notes included
2. Picks the most relevant experience and projects, reorders them, and
   rewords bullets to match the posting's language without inventing anything
3. Builds the one-page PDF with one-line bullets, iterating until it's exactly
   one page with no wasted lines, then renders it to check the layout by eye
4. Writes `job_posting.md` with the posting, its ATS keywords, and notes on
   what was chosen and why
5. Tells you what the posting asks for that your master doesn't have, so you
   can add it if it's real
6. Runs the ATS check and reports your keyword match score
7. Commits the new folder

Each resume is generated **fresh from the master**, never copied from an
earlier tailored resume, so it always uses your latest content.

`Date Applied` stays blank until you tell Claude you've submitted. After that the
folder is a frozen record of what you sent, and Claude won't edit it.

### Archive old applications

> Archive all my Summer 2027 internship applications

This moves the matching folders to `resumes/archive/` with `git mv`. Nothing is
deleted.

### Run the scripts yourself

```
./scripts/build.ps1 -TexPath resumes/<category>/<folder>/<YourName>_Resume.tex
./scripts/ats_check.ps1 -TexPath resumes/<category>/<folder>/<YourName>_Resume.tex
./scripts/layout_check.ps1 -PdfPath resumes/<category>/<folder>/<YourName>_Resume.pdf -Strict
./scripts/new_application.ps1 -Company Acme -RoleTitle SoftwareEngineerIntern -Category software-engineer -PostingUrl <url>
```

## Customizing

- **Rules and style:** edit `CLAUDE.md`. For example, change the
  4-bullets-per-entry cap, the one-line bullet rule, the bullet style guide, the `job_posting.md`
  fields, or the category names. Claude follows whatever it says.
- **Look of the resume:** edit the preamble (everything above
  `\begin{document}`) in `master/master_resume.tex`. Tailored resumes copy
  that preamble, so changes carry over to new resumes.
- **Sections:** add, remove, or rename `\section{...}` blocks in the master
  as needed, for example Publications, Certifications, or Volunteering.
- **Phone format:** `ats_check.ps1` checks for a US-style 10-digit phone
  number. If your number is formatted differently, change the regex near
  `Phone number not detected` in that script.

## Notes and limitations

- The ATS check is **an approximation**. Real ATS systems (Workday,
  Greenhouse, iCIMS, Taleo, …) can't be tested without actually applying.
  Treat the score as a guide, and never add a skill you don't have just to
  raise it.
- Claude follows a strict "never invent a metric or skill" rule, but you're
  the one applying. Read each resume before you send it.
#   R e s u m e V e r s i o n C o n t r o l  
 