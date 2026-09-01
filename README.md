# BCALInsights — poznámky z BC/AL praxe

Sbírka poznámek (known limitations, patterny, gotchas) pro vývoj Business Central
extensions v AL. Slouží jako **povinný kontext pro AI asistenty** (Claude Code,
GitHub Copilot, Codex, Antigravity) před jakoukoliv AL prací. Router „typ úkolu →
soubor / skill" a startup checklist drží **skill `skills/bc-al/SKILL.md`** —
jediný zdroj; always-on soubory jednotlivých nástrojů na něj jen odkazují.

| Soubor | Obsah |
|---|---|
| `bc-al-style.md` | konvence, naming, ToolTipy, UI patterny, moderní patterny (sekce 1, 4, 10) |
| `bc-al-data.md` | database operace, event subscribery (sekce 2, 3) |
| `bc-al-objects.md` | specifické objekty/API, SaaS gotchas (sekce 5, 11) |
| `bc-al-workflow.md` | lokalizace/XLIFF, dokumentace, verifikace (sekce 6, 8, 9, 12) |
| `bc-al-tools.md` | nástroje (alc, al-mcp, BC source), nová appka, git/PR, Azure DevOps (sekce 7.1–7.10) |
| `bc-al-build.md` | NuGet dependencies, test symboly, kolize ID, major bump, Essence CI build & deploy gotchas (sekce 7.11–7.19) |
| `bc-al-autotests.md` | automatizované testy — codeunits, libraries, runner, povinnost |
| `ew-mobile-ui-notes.md` | UI poznámky k Essence Warehouse Mobile (čtečky) |
| `bc-al-notes.archived-2026-06-23.md` | archiv původního monolitu — **needitovat**, jen reference |

## Pravidla údržby

- Číslování sekcí (1–12) je napříč soubory původní kvůli odkazům „viz X.Y" — neměnit.
- Soubor nad **1000 řádků** rozděl (vyčleň ucelené sekce do nového `bc-al-*.md`,
  přidej skill-wrapper do `skills/`, aktualizuj Router ve `skills/bc-al/SKILL.md`
  + tento README; always-on soubory ostatních nástrojů Router nedrží).
  Prakticky: ~750+ řádků se už do jednoho Read (~25k tokenů) nevejde — děl dřív.
  Vzor: 7.11–7.19 → `bc-al-build.md` (2026-09-01).
- Každý nový poznatek = commit s krátkou zprávou, co a odkud (repo, PR, datum).

Lokální klon: `C:\WorkTasks\BCALInsights` (do 2026-08-28 žilo v OneDrive
`AI\BCALInsights`; `ShopifyConnector/` zůstal tam — má vlastní GitHub repo).

## Claude Code skilly (plugin `bcal-insights`)

Repo je zároveň **Claude Code plugin**: `.claude-plugin/plugin.json` +
`skills/<název>/SKILL.md`. Každý skill je tenký wrapper nad jedním notes
souborem — frontmatter `description` = trigger (Claude Code si skill načte
sám podle typu úkolu), tělo = „přečti `../../<soubor>.md` celý" + TL;DR
stabilních pravidel. **Notes soubory zůstávají zdrojem pravdy**, cesty pro
Copilot rozcestník se nemění.

| Skill | Soubor | Kdy |
|---|---|---|
| `bc-al` (`/bc-al`) | rozcestník = Router + startup checklist + pravidla údržby | první akce každé AL/BC seance |
| `bc-al-style` | `bc-al-style.md` | konvence, naming, ToolTipy, UI, moderní patterny |
| `bc-al-data` | `bc-al-data.md` | DB operace, event subscribery, propagace polí |
| `bc-al-objects` | `bc-al-objects.md` | No. Series, Item Tracking, SaaS/SecretText gotchas… |
| `bc-al-workflow` | `bc-al-workflow.md` | XLIFF, dokumentace, analyzery, ruleset |
| `bc-al-tools` | `bc-al-tools.md` | alc, symboly, nová appka, git/PR, ADO |
| `bc-al-build` | `bc-al-build.md` | NuGet, test symboly, kolize ID, major bump, CI build/deploy |
| `bc-al-autotests` | `bc-al-autotests.md` | testy + netriviální funkčnost |
| `ew-mobile-ui` | `ew-mobile-ui-notes.md` | mobilní čtečky, Control AddIn, JS |

Všechny skilly mají `user-invocable: true` — jdou spustit i ručně (`/bc-al-tools`…);
normálně si je agent načítá sám podle `description` (limit 1024 znaků dle spec
[agentskills.io](https://agentskills.io/specification), u `description` to hlídej).
Skilly odkazují na notes **absolutní cestou** `C:\WorkTasks\BCALInsights\…` — přes
junction by relativní `../../` nesedělo.

### Stejné skilly pro Copilot, Codex a Antigravity

`SKILL.md` je otevřený formát Agent Skills, který čtou i ostatní nástroje. Stačí
junctiony na tenhle adresář `skills/`:

```
mkdir "%USERPROFILE%\.agents"
cmd /c mklink /J "%USERPROFILE%\.agents\skills"        "C:\WorkTasks\BCALInsights\skills"   :: Copilot (VS Code) + Codex
cmd /c mklink /J "%USERPROFILE%\.gemini\config\skills" "C:\WorkTasks\BCALInsights\skills"   :: Antigravity
```

| Nástroj | Odkud čte | Ruční spuštění |
|---|---|---|
| Claude Code | `~/.claude/skills/bcal-insights` (plugin, viz výše) | `/bc-al` |
| Copilot (VS Code) | `~/.agents/skills/` (též `~/.copilot/skills/`, `~/.claude/skills/<skill>/`) | `/bc-al` |
| Codex CLI/IDE | `~/.agents/skills/` (+ `.agents/skills/` v repu) | `$bc-al`, `/skills` |
| Antigravity | `~/.gemini/config/skills/` (+ `.agents/skills/` v repu) | zmínit „bc-al" |

Povinnost startupu („první akce = skill `bc-al`") drží always-on soubor každého
nástroje: `~/.claude/CLAUDE.md`, Copilot `User/prompts/bc-al-notes.instructions.md`
(`applyTo: **/*.al`), Codex `~/.codex/AGENTS.md`, Antigravity `~/.gemini/GEMINI.md`.
Ty drží jen personu + odkaz na skill, **ne** Router.

**Instalace (osobní, bez marketplace — „skills-dir" auto-load):**

```
cmd /c mklink /J "%USERPROFILE%\.claude\skills\bcal-insights" "C:\WorkTasks\BCALInsights"
```

Příští seance Claude Code plugin načte jako `bcal-insights@skills-dir`.
Ověření: `claude plugin validate C:\WorkTasks\BCALInsights`,
`claude plugin details bcal-insights`.

**Údržba skillů:**

- Nové gotchas jdou **do notes souborů**, ne do `SKILL.md` — TL;DR ve skillu
  se mění jen, když se mění pravidlo samo.
- Při rozdělení notes souboru (> 1000 řádků) přidej nový wrapper do `skills/`
  a řádek do Routeru ve `skills/bc-al/SKILL.md`.
- Změna skillů → bump `version` v `.claude-plugin/plugin.json`.
