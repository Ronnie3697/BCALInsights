---
name: bc-al-build
description: >-
  BC/AL dependencies, CI build a deploy z praxe (Business Central, AL,
  Essence pipeline, sekce 7.11–7.21): NuGet v2-0 (MajorMinor +
  LatestMatching; dedupe minim per GUID → stejná verze deps ve všech
  app.json), symboly test frameworku z veřejného MSSymbols feedu,
  lokalizační MS appky (CZ packy) od BC 28 pod ID s .cz. infixem (staré
  končí u 27.0, hledej query2), Compile AL Apps failuje bez ##[error]
  (PTE0012 z internalsVisibleTo, CI jede jen PerTenantExtensionCop), kolize
  object ID po merge (rozhodují nasazená data), major bump checklist
  (app.json, BC_ARTIFACT), faily testů shazují build, squash merge →
  falešné konflikty a three-dot diff lže, Microsoft Subcontracting ≥
  28.3.0.0 + BC_ARTIFACT 28.3 (falešné AL0118/AL0132), Deploy Staging
  sync_mode 'Add' / ForceSync maže data / obsolete dvoufázově, smíchané
  řady MS symbolů v .alpackages (falešné AL0132 bez AL1022). Načti při
  CI/build failech, práci s dependencies a symboly z feedu, upgrade BC
  majoru, deploy na staging, merge konfliktech po squash.
user-invocable: true
---

# BC/AL — Dependencies, CI build & deploy (sekce 7.11–7.21)

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\bc-al-build.md`
(v repu `../../bc-al-build.md` relativně k tomuto skillu). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, příkazy, URL feedů, GUIDy a diagnostika
build logů jsou v souboru. Vyčleněno z `bc-al-tools.md` 2026-09-01, číslování
7.x je původní (7.1–7.10 zůstává ve skillu `bc-al-tools`).

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\bc-al-build.md` celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: alc, al-mcp, BC source, git/PR, verzování app.json (7.8),
   Azure DevOps MCP → `bc-al-tools` (7.1–7.10); analyzery a ruleset →
   `bc-al-workflow` (12); test appka, `Tests-TestLibraries`, canonical vzor →
   `bc-al-autotests`.

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **7.11** NuGet: šablona v2-0 jede `MajorMinor` range + `LatestMatching`
  (dřív earliest match) → minimum dependency drž ve **stejné minor řadě jako
  na feedu** (7.17). **Dedupe minim per GUID (vyhrává první app.json)** →
  sdílenou dependency deklaruj **stejnou verzí ve všech app.json**; verze
  dependency = ta, kde člen vznikl. Kompatibilitu ověřuj proti balíčku
  z feedu, ne z lokálních `.alpackages`.
- **7.12** Test symboly z veřejného MSSymbols feedu (flat2 index.json, `curl -L`);
  sandbox package cache + 4 CI analyzery. Lokalizační MS appky (CZ packy,
  Banking Documents…) mají od BC 28 ID s infixem `.cz.` — staré ID končí
  u 27.0.x; chybějící řadu hledej přes `…/MSSymbols/nuget/v3/query2/?q=<název>`.
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
