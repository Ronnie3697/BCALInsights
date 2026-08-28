# BCALInsights — poznámky z BC/AL praxe

Sbírka poznámek (known limitations, patterny, gotchas) pro vývoj Business Central
extensions v AL. Slouží jako **povinný kontext pro AI asistenty** (Claude Code,
GitHub Copilot, Codex) před jakoukoliv AL prací — viz rozcestník
`bc-al-notes.instructions.md` ve VS Code `User/prompts`, který drží Router
„typ úkolu → soubor" a startup checklist.

| Soubor | Obsah |
|---|---|
| `bc-al-style.md` | konvence, naming, ToolTipy, UI patterny, moderní patterny (sekce 1, 4, 10) |
| `bc-al-data.md` | database operace, event subscribery (sekce 2, 3) |
| `bc-al-objects.md` | specifické objekty/API, SaaS gotchas (sekce 5, 11) |
| `bc-al-workflow.md` | lokalizace/XLIFF, dokumentace, verifikace (sekce 6, 8, 9, 12) |
| `bc-al-tools.md` | nástroje, build, git/PR, Azure DevOps, NuGet (sekce 7) |
| `bc-al-autotests.md` | automatizované testy — codeunits, libraries, runner, povinnost |
| `ew-mobile-ui-notes.md` | UI poznámky k Essence Warehouse Mobile (čtečky) |
| `bc-al-notes.archived-2026-06-23.md` | archiv původního monolitu — **needitovat**, jen reference |

## Pravidla údržby

- Číslování sekcí (1–12) je napříč soubory původní kvůli odkazům „viz X.Y" — neměnit.
- Soubor nad **1000 řádků** rozděl (vyčleň ucelené sekce do nového `bc-al-*.md`,
  aktualizuj Router v rozcestníku + tento README). Důvod: delší soubory se do
  jednoho readu AI nástrojů nevejdou.
- Každý nový poznatek = commit s krátkou zprávou, co a odkud (repo, PR, datum).

Lokální klon: `C:\WorkTasks\BCALInsights` (do 2026-08-28 žilo v OneDrive
`AI\BCALInsights`; `ShopifyConnector/` zůstal tam — má vlastní GitHub repo).
