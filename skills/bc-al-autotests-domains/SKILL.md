---
name: bc-al-autotests-domains
description: >-
  BC/AL autotesty – doménové recepty a pasti (Business Central, Essence CI): projekty (Job.Validate
  Status / Sell-to = Confirm, LibraryJob.UseJobPlanningLine rovnou účtuje, default dimenze s Job Task,
  Job Line Type, Copy Document maže Job No.), prodejní a nákupní doklady (částečné účtování doklad vydá,
  TestStatusOpen na nové instanci, undo dodávky bez dialogu a Correction, Quote → Order s číslem nabídky,
  kontakt z CreateCustomer, jen záporný řádek), Job Queue (Library - Job Queue, TaskScheduler.CanCreateTask
  v CI false), výroba (Dynamic Low-Level Code, cyklický BOM, Library - Manufacturing), cust-soitron-bc
  (CreateVendor, Error label), sešit požadavků (Carry Out vlastní batch, Calculate Plan report 699,
  „There is nothing to create", Req. Worksheet TestPage), CZZ záloha s platbou (release, To Pay), párování
  Match Bank Payment CZB (Search Rule, Variable S.). Načti spolu s bc-al-autotests u testů těchto oblastí.
user-invocable: true
---

# BC/AL — Autotesty: doménové recepty a pasti

**Zdroj pravdy:** `bc-al-autotests-domains.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen
wrapper. Vyčleněno z `bc-al-autotests.md` 2026-10-01 (plánování, CZZ, CZB) a 2026-10-09 (projekty, doklady,
Job Queue, výroba, cust-soitron-bc) — zdroj pokaždé přesáhl 1000 řádků.

## Co udělat

1. **Přečti `bc-al-autotests-domains.md` z adresáře tohoto skillu celý** (vejde se do jednoho Read).
   Bez přečtení nejednej.
2. Obecná pravidla testů (handlery, Setup Storage, asserterror rollback, TestPage) jsou ve skillu
   `bc-al-autotests` — načti ho vždy spolu s tímhle; kompilace a běh test appky → `bc-al-autotests-infra`.
3. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli, nepřepisuj potichu.
   Nový poznatek → do souboru + commit + push (viz skill `bc-al`).

## TL;DR

- Každý carry-out test má **vlastní batch** sešitu (`CreateRequisitionWkshName`); Calculate Plan přes report 699
  s `SetTemplAndWorksheet`; poptávku datuj do budoucna, jinak „There is nothing to create".
- CZZ záloha pro platbu: hlavička bez ručního Status + řádek + `Rel. Purch.Adv.Letter Doc. CZZ`; šablona s
  Advance Letter G/L Account; Transaction No. přes `Vendor Ledger Entry No.`.
- `Match Bank Payment CZB`: `Codeunit.Run` jako statement, `Variable S. to Variable S. CZB := true`,
  vlastní Search Rule s jediným řádkem, výsledek čti po `Get`; Issue Payment Order potřebuje MessageHandler.
- **Projekty:** změna stavu / zákazníka projektu a default dimenze projektu s úkoly = Confirm (+ Message) →
  handlery nebo `SetHideValidationDialog(true)`; `LibraryJob.UseJobPlanningLine` řádek deníku rovnou účtuje —
  k úpravě před účtováním ho postav sám (`Job Transfer Line.FromPlanningLineToJnlLine`).
- **Doklady:** částečné účtování doklad vydá → `Reopen…Document` před další změnou; negativní test po release
  validuj na **nové instanci** řádku (`Sales Line` cachuje hlavičku); undo dodávky bez dialogu `SetRecFilter()`
  + `SetHideDialog(true)` + `Run`, korekční řádek hledej přes `Quantity < 0`; doklad jen se záporným řádkem
  doplň kladným zbožím.
- **Job Queue:** před účtováním / plánováním `BindSubscription` na `Library - Job Queue` (lokální proměnná);
  `TaskScheduler.CanCreateTask()` je v CI `false` → pre-check za `IntegrationEvent`, který test přepne.
- **Výroba:** po validaci kusovníku na výrobku komponentu před úpravou znovu načti (Dynamic Low-Level Code).
