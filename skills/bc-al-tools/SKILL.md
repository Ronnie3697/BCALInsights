---
name: bc-al-tools
description: >-
  BC/AL nástroje, build, git a Azure DevOps z praxe (Business Central, AL,
  sekce 7): alc.exe kompilace z CLI (absolutní cesty, analyzery, Git Bash
  MSYS2_ARG_CONV_EXCL, více package cache), al-mcp-server (studený start
  al_packages load, jen signatury → těla procedur na GitHubu, MCP
  CONNECT_TIMEOUT fix), BC source StefanMaron/MSDyn365BC.Code.History (větve
  w1-/cz-<major>, core.longpaths), AL-Go, nová appka v multi-app repu (GUID,
  idRanges, affix, workspace, permission sety, git worktree), source závislé
  appky (sibling repo v C:\WorkTasks, extrakce z .app), git commit/push/PR
  nikdy sám + upstream past + ForcePush, verzování app.json, Azure DevOps MCP
  (org essencebs, PAT read-only záměrně, search_code blob, IPv6 reset),
  case-only rename složky, NuGet earliest match / dedupe minim per GUID, test
  symboly z MSSymbols feedu, kolize object ID po merge, major version bump
  checklist, faily testů shazují build, squash merge a two-dot diff,
  Subcontracting ≥ 28.3 + BC_ARTIFACT, Deploy Staging sync_mode Add /
  ForceSync / obsolete dvoufázově, smíchané verze MS symbolů (falešné
  AL0132). Načti při kompilaci, CI/build failech, práci s git / PR / Azure
  DevOps, dependencies, symbolech, zakládání appky, upgrade BC majoru.
user-invocable: false
---

# BC/AL — Nástroje, build, git & Azure DevOps (sekce 7)

**Zdroj pravdy:** `../../bc-al-tools.md` (lokální klon
`C:\WorkTasks\BCALInsights\bc-al-tools.md`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, příkazy, URL feedů, GUIDy a diagnostika
build logů jsou v souboru.

## Co udělat

1. **Přečti `../../bc-al-tools.md` celý.** Je to nejdelší z notes (~950
   řádků) — Read ho **ořízne**, pokračuj přes `offset`, dokud nemáš 7.19.
   Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`). Soubor se blíží limitu 1000 řádků → při dalším větším doplnění
   ho rozděl (pravidlo ve skillu `bc-al`).
3. Sousední témata: analyzery a ruleset → `bc-al-workflow` (12); test
   appka a její symboly → `bc-al-autotests`; ID objektů a affixy →
   `bc-al-style` (1.2, 1.12).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **7.1** `alc.exe` z `~/.vscode/extensions/ms-dynamics-smb.al-*/bin/win32/`,
  **absolutní cesty** (`/project:`, `/packagecachepath:` — víc cache čárkou),
  analyzery `/analyzer:<bin/Analyzers/…dll>`; v Git Bash
  `MSYS2_ARG_CONV_EXCL="*"`. Externí ruleset alc odmítne.
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
- **7.11** NuGet earliest match + **dedupe minim per GUID (vyhrává první
  app.json)** → sdílenou dependency deklaruj **stejnou verzí ve všech
  app.json**; verze dependency = ta, kde člen vznikl. Kompatibilitu ověřuj
  proti balíčku z feedu, ne z lokálních `.alpackages`.
- **7.12** Test symboly z veřejného MSSymbols feedu (flat2 index.json, `curl -L`);
  sandbox package cache + 4 CI analyzery.
- **7.13** Kolize ID po merge: přečísluj **nenasazenou** stranu — zeptej se,
  co běží s daty.
- **7.14** Major bump: všechny `app.json` (version/platform/application
  `N.0.0.0`, runtime +1, dependencies minima `N.0.0.0`), `azure-pipelines.yml`
  (`BC_ARTIFACT`, `Version.Major`), ověř externí deps na feedu.
- **7.15** Faily testů shazují build (od 2026-07-15) — červený master po
  nesouvisejícím PR = zpřísněná šablona, faily jsou reálné.
- **7.16** Squash merge → falešné konflikty a **three-dot diff lže**; co větev
  přináší = `git diff origin/master HEAD` (two-dot) / `--cached` uprostřed merge.
- **7.17** Microsoft Subcontracting: minimum `28.3.0.0` ve **všech** app.json
  **a** `BC_ARTIFACT` na `28.3/cz/…` (MajorMinor constraint; jinak matoucí
  AL0118/AL0132). Downstream repa: stačí bump artifactu.
- **7.18** Deploy Staging má `sync_mode: 'Add'` natvrdo → destruktivní schema
  změna padá; ForceSync **nenávratně maže data** (jde i na SaaS produkci) →
  u live zákazníka `ObsoleteState = Pending/Removed` dvoufázově.
- **7.19** Smíchané řady MS symbolů v `.alpackages` (CZ pack 28.4 + Application
  28.3) → falešné AL0132 bez AL1022; ověř `Application=` v `NavxManifest.xml`,
  drž jednu řadu.
