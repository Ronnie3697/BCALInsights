---
name: bc-al-workflow
description: >-
  BC/AL lokalizace, dokumentace a verifikace z praxe (Business Central, AL):
  NAB AL Tools XLIFF workflow ([NAB: NOT TRANSLATED] / [NAB: SUGGESTION],
  jeden target, Xliff Generator note nemazat, hromadné překlady), trans-unit
  ID hash (FNV-1a) a past u více extensionů na stejný objekt (LC0091), změna
  labelu s %n vyžaduje update <source> i <target> v XLF, duplicitní
  trans-unity po merge (AL0479), dokumentace requirementů PBI/Task →
  docs/*.md (struktura, konvence), co číst před editem AL objektu (hlavička,
  app.json idRanges/dependencies/target/runtime, .alpackages je binární ZIP →
  al-mcp, permission set), build a analyzery AA/CA/PTE/LC (lokální verifikace
  všech dotčených appek s CI analyzery, failOn warning), hledání významu
  pravidel, runtime errory bez spekulačních smyček, Essence ruleset per
  projekt (*Ruleset*.json vedle app.json). Načti při překladech / XLIFF,
  dokumentaci ticketu, před netriviálním editem, při řešení warningů,
  analyzerů a rulesetů.
user-invocable: true
---

# BC/AL — Lokalizace, dokumentace & verifikace (sekce 6, 8, 9, 12)

**Zdroj pravdy:** `../../bc-al-workflow.md` (lokální klon
`C:\WorkTasks\BCALInsights\bc-al-workflow.md`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, hash algoritmus, struktura dokumentace a
příklady jsou v souboru.

## Co udělat

1. **Přečti `../../bc-al-workflow.md` celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: kompilace z CLI, al-mcp, GitHub source, git/PR → `bc-al-tools`
  (7.1–7.3, 7.7); NuGet dependencies, CI build faily → `bc-al-build` (7.11+); moderní patterny a Cloud target → `bc-al-style` (10);
  CZ↔EN terminologie → `bc-al-objects` (5.z4).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **6.1** Po `Refresh XLIFF`: **jeden `<target>`** per trans-unit, smazat celý
  `[NAB: …]` prefix, note `Xliff Generator` **nikdy nemazat**. Hromadně →
  Python skript source → překlad, pak **zkompiluj**. Drž BC CZ konvence
  (Zboží, Přihrádka, Šarže, Sériové číslo).
- **6.2** Trans-unit ID = FNV-1a 32-bit přes UTF-16LE jména + 2147483647;
  rename pole/objektu ID mění, změna textu ne. **2.+ extension na stejný
  target objekt** má disambiguované ID → ber z `Translations/*.g.xlf`,
  nepřepočítávej (LC0091 tam dělá false positive; ID v `.cs-CZ.xlf` nesahat).
- **6.3** Změna zdrojového textu labelu (typicky nové `%n`) → uprav
  `<source>` **i** `<target>` v každém locale XLF, jinak CZ klient ukazuje
  starou hlášku.
- **6.4** Po každém merge, který sáhl na `.xlf`: `grep -o 'trans-unit
  id="[^"]*"' <soubor> | sort | uniq -d` + kompilace; AL0479 je warning →
  Essence CI (`failOn warning`) spadne.
- **8** Dokumentace ticketu: `docs/<PBI-ID> - <kód> - <popis>.md` v rootu repa
  (žádná podsložka), pořadí: meta → upravené appky → Description → AC → odkazy
  → příklad využití → technická dokumentace (jen když vznikly objekty/pole).
  Identifikátory EN, prózu CZ. Piš až po dokončení implementace; verzi appky
  nezmiňuj (7.8 v `bc-al-tools`).
- **9.1 / 9.2** Před editem: hlavička objektu (id, namespace, co rozšiřuje)
  a **`app.json`** (`idRanges`, `dependencies`, `target`, `runtime`,
  `platform`, `application`).
- **9.3** `.alpackages/*.app` je **binární ZIP** — nečíst přes Read/cat/grep.
  Symboly: al-mcp-server → VS Code AL → MS Learn MCP → StefanMaron GitHub.
  Procedura, kterou nejde potvrdit, **neexistuje**.
- **9.4** Změna permission-relevantního objektu → aktualizuj `permissionset`.
- **12.1** Po každé netriviální změně **build**. Před „kompilace čistá" /
  pushem: zkompiluj **každou dotčenou appku vč. test appky** se **stejnými
  analyzery jako CI** (`Analyzers.Common`, `CodeCop`, `PerTenantExtensionCop`,
  `UICop`); holý `alc` bez `/analyzer:` nic z AA/CA/PTE/LC neodhalí.
  `info` neshodí build, **každý warning oprav**.
- **12.2** Warning neopravuj naslepo — AA/CA/PTE přes MS Learn, LC přes
  LinterCop wiki. Pravidla si občas odporují (LC0082 vs AA0233) → nejmenší zlo
  v kontextu.
- **12.3** Runtime error → z hlášky a stacku nejpravděpodobnější fix → build →
  re-run na reálných datech. Žádné „co kdyby data vypadala takhle" smyčky.
- **12.4** Essence build bere **první `*Ruleset*.json` (case-insensitive)
  rekurzivně ve složce s `app.json`**; `ruleSetPath` v `app.json` = AL0124; `.vscode` je
  gitignored, `.code-workspace` řídí jen editor. `failOn = 'warning'`.
