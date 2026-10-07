# BC/AL poznámky — Projekty (Job, Job Task, Job Planning Line)

> Vyčleněno z `bc-al-objects.md` 2026-10-05 (sekce 5.x17–5.x20), když soubor přesáhl 1000 řádků.
> Načítej, když řešíš: řádky plánování projektu (účto skupina, dimenze, Location Code, vazba budget ↔ billable IMEBS),
> přenos do deníku projektů, návazné doklady projektu (prodej / nákup z plánovacích řádků) a mazání plánovacích řádků.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **5.x17–5.x20** Projekty

### 5.x17 Job Planning Line `Gen. Prod. Posting Group` = zdroj pravdy pro deník projektů; změna default dimenze projektu

- **`Job Transfer Line.FromPlanningLineToJnlLine` (w1-28) kopíruje `Gen. Bus./Prod. Posting Group` z řádku plánování přiřazením,
  bez `Validate("No.")`** — vlastní mapování účto skupiny zavěšené na `Job Planning Line.OnAfterCopyFromItem/Resource` (nové řádky)
  se do deníku projektů dostane jen přes uložený řádek plánování; sales/purchase řádky z planning line si skupinu naopak přepočítají
  (`Validate("Job No.")` → `CopyFromItem`). Pole 81 na Job Planning Line je `Editable = false` **bez OnValidate** (jen TableRelation)
  → oprava existujících řádků = přímé přiřazení + `Modify(false)` (žádný přepočet ceny, rezervací ani `OnModify` s `UpdateReservation`).
- **Změna default dimenze projektu (Job card shortcut dim 1–8 i `Job Default Dimensions`) končí VŽDY v tabulce `Default Dimension`**:
  `Job.ValidateShortcutDimCode` → `DimensionManagement.SaveDefaultDim` → `Get` + `Validate("Dimension Value Code")` + `Modify()` / `Insert()` /
  `Delete()` z kódu → v `OnAfterModifyEvent` je `xRec = Rec` (3.9 v `bc-al-data.md`). Starou hodnotu ber v **`OnBeforeModifyEvent`**
  `Get`-em uložené verze (`SetLoadFields("Dimension Value Code")`), Insert = `'' → nová`, Delete = `stará → ''`; filtr `Table ID =
  Database::Job` + `Dimension Code` ze setupu + `IsTemporary` exit. Rename (PK) hodnotu nemění → neřešit.
  (2026-09-30, cust-soitron-bc `Job Type Posting Mgt. SOI.UpdateJobPlanningLinesOnJobTypeChange`, testy `Job Type Posting Test SOI`.)

### 5.x18 `Location Code` na Job / Job Task NEpropisuje do existujících řádků plánování; vazba budget ↔ billable řádku (IMEBS)

- **Job (167) `Location Code` (35) i Job Task (1001) `Location Code` (30) při změně jen hlásí zprávu** (`MessageIfJobTaskExist` /
  `MessageIfJobPlanningLineExist`: „You have changed %1 on the project (task), but it has not been changed on the existing …")
  a `SetDefaultBin()` — žádná smyčka přes řádky, žádný Confirm „update lines?". Lokace z hlavičky teče jen **dolů při založení**:
  Job Task `InitLocation(Job)` přiřadí `Location Code`/`Bin Code` z Job, Job Planning Line `InitLocation()` dělá
  `Validate("Location Code", JobTask."Location Code")` jen když má úkol lokaci (OnInsert cesta přes `InitJobPlanningLine`). Vlastní
  „synchronizuj lokaci mezi řádky" tedy nemusí počítat s hromadným přepisem z hlavičky. (Zdroj w1-28 `Job.Table.al` 271–290,
  `JobTask.Table.al` 329–343 + 1310, `JobPlanningLine.Table.al` 407–432 + `InitLocation`; cust-soitron-bc 2026-10-01.)
- **`Job Planning Line."Location Code".OnValidate`** (w1-28): `ValidateModification` (TestField `Qty. Transferred to Invoice` = 0 při
  změně), `"Bin Code" := ''`, a jen u `Type = Item` dál `GetLocation` → `CheckItemAvailable` (dostupnostní dialog, v testech
  `LibrarySales.SetStockoutWarning(false)`) → `UpdateReservation` → `Validate(Quantity)` → `SetDefaultBin` → warehouse
  `JobPlanningLineVerifyChange` / `DeleteWarehouseRequest` + `CreateWarehouseRequest`. Resource/G/L/Text řádky mají validate
  prakticky bez vedlejších efektů.
- **Vazba budget ↔ billable řádku = pole `Purch. Job Cont.Entry No.IMEBS` (65130) na BILLABLE řádku** (Essence Project Item
  Management) = `"Job Contract Entry No."` budget řádku, jehož nákup ho zásobuje; klíč `Key65130IMEBS`. Opačný směr = `SetRange("Job No.")`
  + `SetRange("Purch. Job Cont.Entry No.IMEBS", Budget."Job Contract Entry No.")`. Plní ho QB processing
  (`QB Buffer Processing Mgt. SOI.LinkRevenueToCost`) i IMEBS `CreatePurchaseJobPlanningLines`; OnValidate pole
  (`ValidatePurchJobContractEntryNo`) hlídá typ Budget na druhé straně, stejný projekt, žádnou spotřebu/usage a 1:1 (jeden budget
  řádek ↔ jeden billable). `"Job Contract Entry No."` dostane každý řádek v OnInsert (`JobJnlManagement.GetNextEntryNo()`), takže
  před Insertem je 0 — subscribery na vazbu to musí brát jako „ještě není co hledat".

### 5.x19 Dimenze na Job Journal Line z řádku plánování — kde `OnAfterCreateDim` NEstačí (w1-28)

Vlastní dimenze řádku plánování (Soitron `Job Planning Line SOI."Dimension Set ID SOI"`) se do deníku projektů přes
subscriber na `Job Journal Line.OnAfterCreateDim` + `OnAfterValidateEvent "Job Planning Line No."` dostanou jen z ručně
vyplněného deníku. Tři generované cesty je minou (cust-soitron-bc 2026-10-01, reklamace „Line of business" v deníku):

- **`Job Transfer Line.FromPlanningLineToJnlLine`** (akce *Vytvořit řádky deníku projektů*): `"Job No."`/`"Job Task No."`/`Type`/
  `"No."` **přiřazuje**, ne validuje; `"Job Planning Line No."` nastaví **jen při `Usage Link = true`** (bez usage linku deník
  vazbu na řádek plánování vůbec nemá); dimenze dělá až na konci `JobJnlLine.UpdateDimensions()` = `CreateDimFromDefaultDim(0)`
  (→ `CreateDim` → `OnAfterCreateDim`) **a potom** `GetCombinedDimensionSetID([výsledek, CreateDimSetFromJobTaskDim, vyšší priority])`
  — dimenze úkolu projektu se tedy mergují **po** tvém `OnAfterCreateDim` a na stejném kódu dimenze tvoji hodnotu přepíšou.
  `GetTableValuePair(0)` vrací prázdný slovník a `IsDefaultDimDefinedForTable(prázdné)` = `true`, takže `CreateDim` se zavolá vždy.
  Event `OnAfterFromPlanningLineToJnlLine(var JobJnlLine, JobPlanningLine)` běží **před** `UpdateDimensions` → cokoliv tam do
  `"Dimension Set ID"` dáš, se přepočítá. Použitelné: **`OnAfterUpdateDimensions(var JobJournalLine, var DimensionSetIDArr)`**
  (fire i při `IsHandled` z `OnBeforeUpdateDimensions`) — tam merge zopakuj; pro řádky bez usage linku si řádek plánování
  z `OnAfterFromPlanningLineToJnlLine` zapamatuj (globální proměnné subscriber codeunitu + PK deníkového řádku jako klíč, smazat
  v `OnBeforeInsertEvent`). ⚠️ **Globály static-subscriber codeunitu mezi dvěma eventy NEDRŽÍ** — bez `SingleInstance = true`
  dostane každé volání eventu čerstvou instanci (CI build 28618: oba testy „bez usage linku" padly, zapamatovaná sada byla
  prázdná; s usage linkem prošly). Stav mezi eventy = `SingleInstance = true` na subscriber codeunitu (vzor TSEBS
  `Single Instance TSEBS`), pomocné `DimensionManagement` pak drž v lokálních proměnných, ne v globálu singletonu.
  Stejně tak „cache setupu v globálu" static subscriberu nikdy necachovala — jen to vypadalo, že funguje.
- **Essence Project TimeSheets** (`ExtTimeSheetJobJournalTSEBS` 71058700 / `Ext. TS Auto Post Line TSEBS` 71058713, větev
  `features/newEvent`): u řádku plánování s **placeholder resource** (`Resource."Placeholder Resource TSEBS"`) dělá
  `JobJournalLine."Job Planning Line No." := …` **přiřazením** (standardní `Validate` by spadl na `TestField("Usage Link", true)`
  a `TestField("No.")`), pak už jen `Validate("Location Code"/"Bin Code")` když jsou vyplněné → žádný `CreateDim` s vazbou
  v ruce. Stejně `Suggest Job Jnl. Lines.OnAfterTransferTimeSheetDetailToJobJnlLine` (TSEBS přiřadí
  `"Job Planning Line No. TSEBS"` z Time Sheet Line). Nezávisle na appce to chytí **`Job Journal Line.OnBeforeInsertEvent`**
  (`RunTrigger`, ne temporary) — merge podle `"Job Planning Line No."`; opakovaný merge téže sady je idempotentní.
- `Job Planning Line."Usage Link"` řídí `ControlUsageLink()`: při `Job."Apply Usage Link" = true` je na budget řádku **vždy** true
  (ruční `Validate("Usage Link", false)` se vrátí) → v testu „bez usage linku" nastav `Job.Validate("Apply Usage Link", false)`
  před založením řádků. `Job Task.OnInsert` → `DimMgt.InsertJobTaskDim` kopíruje default dimenze projektu do `Job Task Dimension`
  (založ default dim před `CreateJobTask`, jinak Confirm „update the lines?"). Řádek deníku bez usage linku má po transferu
  `"Job Planning Line No." = 0` — assertuj to jako precondition scénáře. Testy `JPL Dim. Transfer Test SOI` (54443).
- Cache setupu v globálu subscriber codeunitu (`SetupLoaded`) = změna setupu platí až v nové session **a** test, který setup
  přepíná, čte starou hodnotu → setup čti při každém volání (`Get` jedné věty platforma cachuje sama).

### 5.x20 „Má projekt už návazné doklady?" — kde to poznáš; co hlídá standardní `Job Planning Line.OnDelete` (w1-28.4)

- **Prodejní doklad z plánovacích řádků = `Job Planning Line Invoice` (1022)**, otevřený i zaúčtovaný. Standard (`Job Create-Invoice`)
  i IMEBS `GenerateSalesOrderJobLines` (→ `CreateTrackingEntryForSalesDocumentLine`) ho zakládají. Řádky prodejky z IMEBS **nemají
  `Sales Line."Job No."`** (jen `Job Contract Entry No.`), projekt nese hlavička `Sales Header."Job No. EPEBS"` (Essence Project Base).
- **`Job Planning Line.OnDelete`** sám blokuje: `PreventDeleteIfPurchaseExists` (Purch. Rcpt. Line s `Job No./Job Task No./Job Planning
  Line No.`), `ValidateModification` + `CheckRelatedJobPlanningLineInvoice` (převedeno/fakturováno), Usage Link → `JobUsageLink` neprázdný.
  `DeleteAttachedJobPlanningLines` smaže i řádky s `Attached to Line No.` → hromadné mazání dělej `while FindFirst() do Delete(true)`.
  Neblokuje otevřenou nákupní objednávku bez příjmu → tu hlídej sám (`Purchase Line` Order s `Job No.`).
- **Essence Project Base přidává `Job Planning Line EPEBS.OnBeforeDelete`** (prod-ep-projectBase-bc): `Tender No. EPEBS` <> '' →
  tender Won = `TestField`, jinak Confirm (default **No**); `Job Ledger Entry` s `Job Planning Line No. EPEBS` → `Error`; `Sales Line` /
  `Purchase Line` s `Job Planning Line No. (EPEBS)` → Confirm (default No) a po souhlasu odpojení řádků. Confirmy jdou přes
  `GetResponseOrDefault` → **bez GUI (API, Job Queue, test bez handleru) skončí tichým `Error('')`**. Hromadné mazání z kódu proto
  **pre-checkni sám** (tender, Job Ledger Entry projektu, Sales/Purchase Line libovolného typu s `Job No.`) a dej vlastní hlášku,
  jinak akce spadne uprostřed bez textu. (2026-10-05, cust-soitron-bc 66489 — přegenerování QB bufferu, `QB Buffer Regenerate Mgt. SOI`.)

### 5.x21 Vazba nákupních / prodejních dokladů na KONKRÉTNÍ řádek plánování (součty částek per řádek, w1-28)

- **Nákup: standardní pole `Job Planning Line No.` má na `Purchase Line`, `Purch. Rcpt. Line`, `Purch. Inv. Line` i `Purch. Cr. Memo Line`
  stejné field ID 1019** → `TransferFields` při účtování ho přenese do všech účtovaných řádků; filtr `Job No.` + `Job Task No.` +
  `Job Planning Line No.` tedy funguje na otevřené objednávce i na účtovaných dokladech. `Purchase Line."Job Planning Line No."`
  OnValidate vyžaduje `JobPlanningLine."Usage Link" = true` (→ `Job."Apply Usage Link"`), shodu `No.` a typu a nastaví
  `Job Line Type`. **Essence Project Base** má vedle toho vlastní `Job Planning Line No. EPEBS` (71058660, taky stejné ID napříč
  Purchase/Rcpt/Inv Line) a plní ho z `modify("Job Planning Line No.") OnAfterValidate` — EPEBS flowfieldy `Purchase Receipt/Invoice
  Exists EPEBS` filtrují přes EPEBS pole, `Purchase Order/Cr. Memo Exists EPEBS` přes standardní; pro vlastní součty ber standardní
  pole (zdroj pravdy, EPEBS je kopie).
- **Položky projektu: standard váže JLE na řádek plánování jen přes `Job Usage Link`** (Entry No. ↔ Job No./Task/Line No.); EPEBS
  navíc stampuje `Job Ledger Entry."Job Planning Line No. EPEBS"` z `Job Journal Line."Job Planning Line No."` (subscriber
  `Job Jnl.-Post Line.OnBeforeJobLedgEntryInsert`), takže součet nákladů per řádek = `SetRange(Job No., Job Task No., "Job Planning
  Line No. EPEBS")` + `CalcSums` bez joinu. ⚠️ **Platí jen pro Usage** — prodejní JLE z fakturace (`Job Post-Line.PostInvoiceContractLine`
  → `PostJobOnSalesLine`) vzniká z deníkového řádku **bez `Job Planning Line No.`**, EPEBS pole je tam prázdné (ověřeno na datech
  Soitron 2026-10-07). Vazbu prodejní položky drží standard v **`Job Planning Line Invoice`** (PK Job No./Task/Line No./Document
  Type/Document No./Line No.): po zaúčtování `Document Type` = Posted Invoice / Posted Credit Memo a **`Job Ledger Entry No.`**
  (`UpdateJobLedgerEntryNoOnJobPlanLineInvoice`) → `Get` JLE a seč `Line Amount (LCY)` (faktura záporně, dobropis kladně).
  `Invoiced Amount (LCY)` v téže tabulce je přepočet z ceny plánovacího řádku, ne z dokladu — pro „fakturováno" ber JLE.
  ⚠️ Ani `Job Planning Line Invoice` nepokryje všechno: zakládá ji jen faktura z řádků plánování (Job Create-Invoice, IMEBS
  objednávka); faktura přes **Získat řádky dodávky** ji nemá (`Sales-Get Shipment` ji netvoří, `Job Post-Line` ji jen `if Get`),
  položka projektu přesto vznikne → per řádek chybí (Soitron 2026-10-07: drill-down 4 položky vs. „Fakturováno" úlohy 7).
  Jediná vazba, která přežije všechny cesty, je `Sales Line."Job Contract Entry No."`; chceš-li ji na JLE, patří propis řádku
  plánování do EP Project Base přes `Job Transfer Line.OnAfterFromPlanningSalesLineToJnlLine(var JobJnlLine, JobPlanningLine, …)`
  (řádek plánování tam je k dispozici; standardní `JobJnlLine."Job Planning Line No."` u Sale neovlivní usage link — ten se aplikuje
  jen pro Entry Type Usage — ale raději vlastní pole, ať se nesahá do `PostItem` větve s `ApplyToJobContractEntryNo`).
  Rozhodnutí Soitron: prodej i spotřeba přes `Job Planning Line No. EPEBS`, EP ho doplňuje na prodejní položky; stará data nevadí.
  **Implementováno v EP (prod-ep-projectBase-bc, větev `features/salesQuotes`, 2026-10-07):** subscriber `Job Transfer Line.
  OnAfterFromPlanningSalesLineToJnlLine` → `JobJnlLine."Job Planning Line No." := JobPlanningLine."Line No."` (standard ho na
  prodejní cestě nenastaví, na nákupní ano — `FromPurchaseLineToJnlLine`; `Job Jnl.-Post Line` ho čte jen ve větvi Usage, Sale
  jen vloží JLE), existující `OnBeforeJobLedgEntryInsert` pak kopíruje do EPEBS pole. Test `Event Subscribers Test EPEBS`:
  prodejní faktura s `Sales Line."Job Contract Entry No."` přiřazeným přímo (bez `Job Planning Line Invoice`, jako přes Získat
  řádky dodávky) → `LibrarySales.PostSalesDocument` → JLE Sale nese task i číslo řádku. Kompilace EP appky s AppSource range:
  AppSourceCop místo PTE cop (7.1 v `bc-al-tools.md`). Znaménka: Usage `Total Cost (LCY)` kladné, Sale `Line Amount (LCY)` u faktury záporné,
  u dobropisu kladné → součet = náklady − výnosy; Soitron ho u řádků Billable / Both otáčí (zisk kladně), u Budget nechává náklady
  kladné (`JPL Doc. Amounts SOI.CalcJobLedgerEntryAmountLCY`). V testu `LibraryJob.UseJobPlanningLine(JPL, UsageLineTypeBlank(),
  1, JobJnlLine)` + explicitní `Validate("Job Planning Line No.")` + `LibraryJob.PostJobJournal`; prodejní JLE vznikne fakturací
  IMEBS objednávky a nese `Job Planning Line No. EPEBS` z `Job Post-Line`.
- **Prodej: `Job Contract Entry No.`** na `Sales Line`, `Sales Shipment Line`, `Sales Invoice Line`, `Sales Cr.Memo Line` = `Job
  Planning Line."Job Contract Entry No."` billable řádku. ⚠️ Každý prodejní řádek bez projektu má 0 → před `SetRange` guard
  `if "Job Contract Entry No." = 0 then exit(0)`, jinak sečteš celou firmu.
- Vzor „částky dokladů per řádek plánování ve factboxu" = kopie `Job Purch. Doc. Amounts EPEBS` / `Job Sales Doc. Amounts IMEBS`
  (page background task, výsledky `Format(x, 0, 9)` v Dictionary, `ToLCY` přes `Currency Exchange Rate.ExchangeAmtFCYToLCY`,
  příjemka/dodávka = `Quantity × Direct Unit Cost/Unit Price × (1 − Line Discount %)`): cust-soitron-bc `JPL Doc. Amounts SOI` +
  pageextension `Job Planning Line FactBox SOI` (`addfirst(Content)` na EPEBS CardPart 71058665), testy `JPL Doc. Amounts Test SOI`
  (účtování příjemka → faktura z jedné objednávky, prodejka přes IMEBS `CreateSalesOrder` + `GenerateSalesOrderJobLines`, dobropisy
  vložené přímo do účtovaných tabulek). (2026-10-06, cust-soitron-bc.)
