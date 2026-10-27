---
name: bc-al-projects
description: >-
  BC/AL projekty (Job / Job Task / Job Planning Line, 5.x17–5.x27): Gen. Prod. Posting Group řádku plánování
  jako zdroj pravdy pro deník projektů, změna default dimenze projektu (xRec v OnAfterModifyEvent), Location
  Code z Job / Job Task jen pro nové řádky, vazba budget ↔ billable Purch. Job Cont.Entry No.IMEBS, dimenze
  řádku plánování do Job Journal Line (UpdateDimensions až po OnAfterCreateDim, Usage Link), návazné doklady
  projektu (Job Planning Line Invoice, Job No. EPEBS), guardy Job Planning Line.OnDelete, undo nákupní příjemky
  s projektem, spotřeba projektu z prodejní dodávky per šarže / SN / položka příjmu (OnAfterInsertShipmentLine),
  nákupní dobropis / vratka dodavateli u Skip projektu (kontrola spotřeby per tracking, Posting Preview JLE,
  Get Posted Doc. Lines to Reverse), spotřeba projektu z deníku zboží (list Spotřeba projektů, Item Jnl.-Check
  Line / OnAfterPostItemJnlLine, Job No. na Item Journal Line bez validace, nový rozpočtový řádek). Načti u
  plánovacích řádků, deníku projektů i zboží s projektem, návazných dokladů, příjemek, dodávek a vratek projektu.
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
3. Sousední témata: Job Queue a ostatní objekty → `bc-al-objects`; Requisition Line → `bc-al-blanket`; Job No. na dodávce vs.
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
  běží před `PostItemLine` a `Qty. to Handle (Base)` trackingu řádku NENÍ dodávané množství (řádek sledování na celý řádek
  se částečnou dodávkou nekrátí) → účtuj z `OnAfterInsertShipmentLine` podle položek zboží dodávkového řádku
  (`ItemTrackingMgt.CollectItemEntryRelation` / `Item Shpt. Entry No.`); položky příjmu = každý řádek příjemky × každá ILE.
  **Od 2026-10-21 usage per položka zboží DODÁVKY** (každá dodávka hned, rozděleno podle položek příjmu, ze kterých bere —
  jedna položka příjmu = zdroj nákladu usage; zbytek bez vazby). Dřívější 1 : 1 k položce příjmu (čekání na pokrytí) zrušeno.
  Nadspotřeba = `Job Link Usage` zvedne `Quantity` budget řádku. IMEBS `CreateItemTrackingForSalesLine`
  píše do 336, ne 337 (dodávka to nečte).
- **5.x26** `Purch.-Post` volá `OnPostItemJnlLineJobConsumption` i u vratek (před položkou zboží) — `IsHandled` pro Skip projekt vypne
  i standardní stop „nelze vrátit spotřebované“; IMEBS kontroluje vráceno ≤ přijato − usage − dříve vráceno per tracking a vrácené
  množství vyřazuje ze spotřeby při dodávce. Posting Preview JLE zobrazuje; Get Posted Doc. Lines to Reverse job pole u nákupu
  kopíruje, u prodeje maže.
