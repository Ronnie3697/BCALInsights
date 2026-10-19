---
name: bc-al-projects
description: >-
  BC/AL projekty (Business Central, Job / Job Task / Job Planning Line, sekce 5.x17–5.x24): Gen. Prod. Posting
  Group řádku plánování jako zdroj pravdy pro deník projektů (Job Transfer Line bez Validate("No.")), změna
  default dimenze projektu (Default Dimension, xRec v OnAfterModifyEvent), Location Code z Job / Job Task jen pro
  nové řádky, vazba budget ↔ billable Purch. Job Cont.Entry No.IMEBS, dimenze řádku plánování do Job Journal
  Line (UpdateDimensions až po OnAfterCreateDim, SingleInstance mezi eventy, Usage Link, TSEBS placeholder),
  návazné doklady projektu (Job Planning Line Invoice, Job No. EPEBS, nákupní objednávka / příjemka), guardy
  Job Planning Line.OnDelete, undo nákupní příjemky s projektem (ReapplyJobConsumption, Skip Purchase
  Consumption IMEBS), spotřeba projektu z prodejní dodávky per šarže / SN / položka příjmu
  (CreateJobLedgerEntryFromSalesLine, OnBeforePostJobContractLine před PostItemLine). Načti u řádků plánování,
  deníku projektů, mazání plánovacích řádků, návazných dokladů, storna příjemky a spotřeby z dodávky.
user-invocable: true
---

# BC/AL — Projekty: Job, Job Task, Job Planning Line (sekce 5.x17–5.x24)

**Zdroj pravdy:** `bc-al-projects.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů a příklady jsou v souboru.
Vyčleněno z `bc-al-objects.md` 2026-10-05, číslování 5.x je původní.

## Co udělat

1. **Přečti `bc-al-projects.md` z adresáře tohoto skillu celý.** Je krátký (~100 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: Job Queue, Requisition Line a ostatní objekty → `bc-al-objects`; Job No. na dodávce vs.
   faktuře a propagace polí do dokladů → `bc-al-posting` (3.6f); subscribery, xRec v modify triggerech →
   `bc-al-data` (3.9); testy projektů (Confirm při změně zákazníka / default dimenze, Usage Link) → `bc-al-autotests-domains`
   (spolu s `bc-al-autotests`).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **5.x17** `Job Transfer Line.FromPlanningLineToJnlLine` kopíruje účto skupiny z řádku plánování přiřazením → mapování
  musí sedět na uloženém řádku plánování. Změna default dimenze projektu končí v `Default Dimension`; starou hodnotu
  ber v `OnBeforeModifyEvent`.
- **5.x18** `Location Code` na Job / Job Task se do existujících řádků plánování nepropisuje. Vazba budget ↔ billable
  = `Purch. Job Cont.Entry No.IMEBS` na billable řádku.
- **5.x19** Dimenze z řádku plánování do deníku projektů: merge v `OnAfterUpdateDimensions` (dimenze úkolu se mergují po
  `OnAfterCreateDim`); stav mezi eventy jen se `SingleInstance = true`.
- **5.x20** Prodejní doklad z plánovacích řádků = `Job Planning Line Invoice`; projekt na hlavičce IMEBS prodejky =
  `Job No. EPEBS`. `Job Planning Line.OnDelete` blokuje příjemky, fakturaci a usage, otevřenou nákupní objednávku ne.
- **5.x24** Spotřeba projektu z prodejní dodávky (IMEBS `CreateJobLedgerEntryFromSalesLine`): `OnBeforePostJobContractLine`
  běží před `PostItemLine` → dodávané sledování čti z rezervačních položek řádku (`Qty. to Handle (Base)`, `Item Tracking
  <> None`), položky příjmu = každý řádek příjemky × každá ILE; JLE per kombinace SN / Lot / Package / expirace s vazbou
  na položku příjmu. IMEBS `CreateItemTrackingForSalesLine` píše do 336, ne 337 (dodávka to nečte).
