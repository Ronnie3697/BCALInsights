---
name: bc-al-autotests-infra
description: >-
  BC/AL autotesty – infrastruktura test appky (Business Central, Essence CI): app.json test appky
  (explicitní dependencies, AL0185), internalsVisibleTo v hlavní appce (PTE0012, AL0161 = nesedící GUID),
  test app bez permissionsetu, název souboru bez affixu (AppSourceCop mandatoryAffixes), plochá src/,
  test ruleset dědí hlavní + LC0015 (al.ruleSetPath folder-level), symboly Tests-TestLibraries mimo
  .alpackages, lokální kompilace ze sibling .alpackages / temp cache (tranzitivní vs explicitní deps,
  AL1022 smíchané minor verze MS knihoven, logo ..\app, #IF TESTS), spouštění testů (Run-AlPipeline
  v Dockeru, BcContainerHelper 6.1.18, verze deps jako CI, lokální testovací kontejner, AL Test Runner),
  čtení CI failů (Test Runs REST errorMessage, stejné Document No. = rollback). Načti při zakládání
  test appky, kompilaci a běhu testů a rozboru CI failů; psaní testů je ve skillu bc-al-autotests.
user-invocable: true
---

# BC/AL — Autotesty: infrastruktura test appky

**Zdroj pravdy:** `bc-al-autotests-infra.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen
wrapper. Vyčleněno z `bc-al-autotests.md` 2026-10-09 (1009 řádků / 77 KB, nevešel se do jednoho Read).

## Co udělat

1. **Přečti `bc-al-autotests-infra.md` z adresáře tohoto skillu celý** (vejde se do jednoho Read).
   Bez přečtení nejednej.
2. Povinnost testů, kanonický vzor a psaní testů (handlery, TestPage, `asserterror`, `Library - *`) jsou
   ve skillu `bc-al-autotests` — u psaní nebo opravy testů ho načti spolu s tímhle.
3. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli, nepřepisuj potichu.
   Nový poznatek → do souboru + commit + push (viz skill `bc-al`).
4. Sousední témata: symboly test frameworku z MSSymbols feedu, lokální testovací kontejner (7.23)
   a faily CI buildu → `bc-al-build`; alc z CLI a package cache → `bc-al-tools` (7.1); ruleset
   konvence → `bc-al-workflow` (12.4).

## TL;DR

- Test `app.json` deklaruje **explicitně každou appku, jejíž typy test používá** (tranzitivní dep přes hlavní
  appku nestačí, `AL0185`).
- Main appka s `Access = Internal` → `internalsVisibleTo` v jejím `app.json` **nemazat**, `id` musí přesně
  sedět s `test/app.json` (jinak `AL0161 … inaccessible`); `PTE0012` schovat v rulesetu. Test app **bez
  permissionsetu**.
- Struktura: plochá `test/src/`, affix v názvu souboru netřeba (AppSourceCop ho odečte). Test ruleset
  **dědí hlavní** (`includedRuleSets`) + `LC0015` Hidden; aby byl ve VS Code aktivní, `al.ruleSetPath` do
  `test/.vscode/settings.json` (folder-level), workspace-level se resolvuje na hlavní.
- Symboly `Tests-TestLibraries` nejsou v `.alpackages` → Local-DevEnv s `installTestLibraries` / `AL: Download
  Symbols` / MSSymbols feed (7.12 v `bc-al-build`). Lokální kompilace bez kontejneru: **celá** `.alpackages`
  sibling repa (tranzitivní deps) v `/packagecachepath` + build dir hlavní appky; MS test `.app` nemají
  zdrojáky → signatury přes al-mcp. MS test knihovny v cache z **jedné minor řady** (jinak `AL1022`).
- Kompiluj **kopii** `test/` ve scratchpadu (vedle ní `app/` s logem); testy za `#IF TESTS` ověř kopií
  s přepnutým symbolem.
- **Po každém vyžádaném push** testy v lokálním kontejneru (`Test-Repo.ps1`, 7.7b v `bc-al-tools`, 7.23
  v `bc-al-build`), jen kdo kontejner v setupu přijal. Verze Essence závislostí jako CI (NuGet
  `LatestMatching`), ne „co leží v `.alpackages`".
- Text chyby spadlého testu z CI: REST `_apis/test/Runs/<runId>/results?outcomes=Failed` v přihlášeném
  Chromu; stejné `Document No.` v chybách víc testů = každý spadl a odroloval se.
