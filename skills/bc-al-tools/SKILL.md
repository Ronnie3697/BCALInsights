---
name: bc-al-tools
description: >-
  BC/AL nástroje, git a Azure DevOps z praxe (Business Central, AL, sekce
  7.1–7.10): alc.exe kompilace z CLI (absolutní cesty, bez
  Analyzers.Common.dll (AL1003), Git Bash MSYS2_ARG_CONV_EXCL, více package
  cache, dočasná cache ze sibling rep, UTF-16 logy (falešné 0 errors), Bash
  heredoc pasti (backslash, apostrof), volné object ID BOM-aware),
  al-mcp-server (studený start al_packages load, jen signatury → těla
  procedur na GitHubu, MCP CONNECT_TIMEOUT fix), BC source
  StefanMaron/MSDyn365BC.Code.History (w1-/cz-<major>, core.longpaths),
  AL-Go, nová appka v repu (GUID, idRanges, affix, workspace, permission
  sety, git worktree), source závislé appky (sibling repo, extrakce z .app),
  git commit/push/PR nikdy sám + upstream past + ForcePush, verzování
  app.json, Azure DevOps MCP (org essencebs, PAT read-only záměrně,
  search_code blob, IPv6 reset), case-only rename složky. Načti při
  kompilaci z CLI, práci se symboly, git / PR / Azure DevOps, zakládání
  appky. (NuGet, CI build a deploy → skill bc-al-build.)
user-invocable: true
---

# BC/AL — Nástroje, git & Azure DevOps (sekce 7.1–7.10)

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\bc-al-tools.md`
(v repu `../../bc-al-tools.md` relativně k tomuto skillu). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, příkazy, URL a GUIDy jsou v souboru.
Sekce **7.11–7.19** (NuGet, test symboly, kolize ID, major bump, Essence
build/deploy) žijí od 2026-09-01 v `bc-al-build.md` → skill `bc-al-build`.

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\bc-al-tools.md` celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: dependencies, CI build, deploy → `bc-al-build` (7.11–7.19);
   analyzery a ruleset → `bc-al-workflow` (12); test appka a její symboly →
   `bc-al-autotests`; přidělování object ID → `bc-al-style` (1.12); affixy a
   permission sety nové appky jsou tady (7.5).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **7.1** `alc.exe` z `~/.vscode/extensions/ms-dynamics-smb.al-*/bin/win32/`,
  **absolutní cesty** (`/project:`, `/packagecachepath:` — víc cache čárkou),
  analyzery `/analyzer:` (AL 18: vše přímo v `bin/`); v Git Bash
  `MSYS2_ARG_CONV_EXCL="*"`. Externí ruleset alc odmítne. Sada = CodeCop, UICop,
  PTE + **šest `ALCops.*` a povinně `ALCops.Common.dll`** (bez ní `AD0001`
  a falešně čistý build); samostatný `BusinessCentral.LinterCop.dll` **už ne**.
  MS `Analyzers.Common.dll` do `/analyzer:` naopak **nedávat** (AL1003). Log alc z Git Bash i PS
  `*>` je **UTF-16** → před grepem dekóduj, jinak falešné „0 errors". Bash tool
  heredoc sráží `\\` a padá na apostrof v obsahu → AL/JSON s apostrofy či
  backslashy piš Write toolem. Volné object ID hledej BOM-aware (grep bez `^`).
  Prázdná `.alpackages` → dočasná cache z kopií sibling rep, jedna řada MS
  symbolů.
- **7.2** al-mcp: po startu seance `al_packages load` na **root repa**.
  Vrací **jen signatury** → tělo procedury vezmi z GitHubu
  (`ReferenceSourceFileName` → `gh api …/git/trees` → contents). MCP „není
  dostupný" = CONNECT_TIMEOUT (globální `npm i -g` + přímý shim,
  `MCP_TIMEOUT`).
- **7.3** StefanMaron větev podle `app.json` (`w1-28` / `cz-28` pro CZ
  legislativu). Sparse checkout: `git config core.longpaths true`.
- **7.4** AL-Go repo → CI je zdroj pravdy, nebypassuj ručním buildem.
- **7.5** Nová appka: kopie existující, **nový GUID**, unikátní `idRanges`
  (per typ objektu od začátku), affix v `.vscode/settings.json`
  (`CRS.ObjectNameSuffix`) **i** `AppSourceCop.json` (`mandatoryAffixes`;
  prod appky `xxEBS` + `mandatorySuffix`), do `.code-workspace`, permission
  set = X na codeunity/reporty + tabledata jen vlastní tabulky + 3
  `permissionsetextension` (D365 BASIC/READ/SETUP). Rozpracovaný klon →
  `git worktree` + `mklink /J .alpackages`.
- **7.6** Source závislé appky: sibling repo `C:\WorkTasks\prod-*` →
  extrakce `.app` (40B hlavička + ZIP) → al-mcp fallback.
- **7.7 ⛔** `git commit` / `push` / PR / merge do master **nikdy bez
  výslovného pokynu** (výjimka: notes repo BCALInsights). Nová větev z cizí
  upstream → `git branch --unset-upstream` nebo vždy `git push -u origin
  <větev>`. Dev nemá ForcePush → cizí větev zpět nevrátíš.
- **7.8** `version` v `app.json` neměnit sám; do PR `XX.0.0.0`.
- **7.9** ADO MCP: org `essencebs`, projekt `Projects`; repo odvoď z CWD /
  Area Path. **PAT je read-only záměrně — 401 na zápis neobcházet** jiným
  credentialem, PR zakládá uživatel. `search_code` vrací multi-MB blob →
  parsuj pythonem. IPv6 reset → `--dns-result-order=ipv4first`.
- **7.10** Case-only rename složky = obě cesty v merge → detekce
  `git ls-tree -r HEAD --name-only | sort -f | uniq -di`; rename dvoukrokově.
