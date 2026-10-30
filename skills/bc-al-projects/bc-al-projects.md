# BC/AL poznámky — Projekty (Job, Job Task, Job Planning Line)

> Vyčleněno z `bc-al-objects.md` 2026-10-05 (sekce 5.x17–5.x20), když soubor přesáhl 1000 řádků.
> Načítej, když řešíš: řádky plánování projektu (účto skupina, dimenze, Location Code, vazba budget ↔ billable IMEBS),
> přenos do deníku projektů, návazné doklady projektu (prodej / nákup z plánovacích řádků) a mazání plánovacích řádků.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **5.x17–5.x27** Projekty (5.x24: spotřeba projektu z prodejní dodávky per tracking a per položka příjmu, pořadí v Sales-Post; 5.x25: přecenění položek projektu; 5.x26: nákupní dobropis / vratka u Skip projektu; 5.x27: spotřeba projektu z deníku zboží; 5.x28: kontrola množství z řádků plánování — standard zvedá Quantity sám, hooky Job Link Usage / OnBeforeUpdateRemainingQuantityFromUse, Σ při vydání dokladu)

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
- **Přemapování účto skupiny existujících řádků = vždy z KARTY (Item / Resource / G/L Account `Gen. Prod. Posting Group`), ne
  zpětným překladem přes setup.** První verze (alt skupina starého typu → default → alt nového typu) selhávala při řetězení typů
  (typ bez mapování, dvě default skupiny se stejnou alt, změněný setup nebo karta mezi změnami) a při smazání typu řádky
  nevracela na default — zákazník to reklamoval (PBI 63758, komentáře 2026-10-15: „stejná karta musí za stejný typ projektu dostat
  vždy stejnou účtoskupinu, bez ohledu na to kolikátý typ to byl"). Správně: `case Type of Item/Resource/"G/L Account"` → `Get`
  karty (`SetLoadFields`) → default → `GetMapped(NewType, default)`; prázdná skupina na kartě = řádek nesahat, `Text` řádky
  přeskočit. Stará hodnota typu je pak jen pro early exit `Old = New`. (2026-10-15, cust-soitron-bc, tamtéž.)

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
- **Kde projekt na dokladech JE a kde NENÍ (Essence Project Base 28.0.24, ověřeno al-mcp):** `Job No. EPEBS` (hlavička) mají
  `Sales Header`, `Sales Header Archive`, `Sales Invoice Header`, `Sales Cr.Memo Header`, `Purchase Header`, `Purch. Inv. Header`;
  **`Sales Shipment Header` a `Purch. Rcpt. Header` ho NEMAJÍ** (jen `Tender No. EPEBS`). Zaúčtované příjemky a dodávky projektu tedy
  dohledáš jen přes řádky: `Purch. Rcpt. Line."Job No."` (nákup řádkové `Job No.` nese), `Sales Shipment Line."Job No."` (ruční
  řádky) **nebo `Sales Shipment Line."Job Contract Entry No."`** (dodávky objednávek z QB / IMEBS billable řádků — řádkové `Job No.`
  je prázdné). Ani jedno z těch polí nemá na `Sales Shipment Line` klíč (Key1–7 = PK, Order No., Blanket, Item Shpt. Entry, Sell-to,
  Bill-to, Document Id) → oba filtry jsou scan; kontraktová čísla projektu slož do jednoho `SetFilter('1|2|3')` z `Job Planning Line`
  (`Job Contract Entry No. <> 0`), ne dotaz per řádek. Otevřené doklady z QB nesou projekt **jen na hlavičce** — kontrola přes
  `Sales Line."Job No."` je nevidí (tvrdá kontrola „nevyfakturovaná objednávka“ v `Job Close Mgt. SOI` je tak dodnes mine; vzor
  hlavička + řádky viz `QB Buffer Regenerate Mgt. SOI`). (2026-10-21, cust-soitron-bc 66504 — varování „existují nezaúčtované doklady“
  před stornem projektu, `Job Close Mgt. SOI.CollectUnpostedDocuments`; posted příjemky / dodávky z varování nakonec vyřazeny na přání
  uživatele, poznatek o jejich dohledání ale platí.)

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

### 5.x22 Vlastní pole hlavičky dokladu plněné z projektu u „Create Subcontract Purchase/Sales Order" (EPEBS / IMEBS)

- Akce *Create Subcontract Purchase Orders* (Job Planning Lines / Job Card, report `Job Trans.Purch.Orders EPEBS` →
  `Job Purch. Order Trans. EPEBS.GetPurchaseOrderForLine` → `Project Functions EPEBS.CreatePurchaseOrder`, **internal**) i *Create
  Sales Order* (IMEBS `Job Create Sales Order IMEBS` → `Project Item Management IMEBS.CreateSalesOrder`, public) zakládají
  hlavičku stejně: `Insert(true)` → `Validate("Purchaser Code" / "Salesperson Code", Job."Person Responsible")` →
  **`Validate("Job No. EPEBS", JobNo)` → `Modify(true)`**. Žádný IntegrationEvent na hlavičce není → vlastní pole hlavičky
  (Soitron `Logistic Officer SOI`, dřív `Technical Lead SOI` — přejmenováno 2026-10-12, Technical Lead zůstal jen na projektu) plň v tableextension přes **`modify("Job No. EPEBS") { trigger OnAfterValidate() }`**
  (modify pole cizí tableextension funguje, appka má přímou dependency na EP Project Base) — pokryje obě akce i ruční zadání
  projektu na dokladu; hodnotu jen přiřaď (ne `Validate`, ať smazaný prodejce z karty projektu neshodí založení dokladu).
- Test nákupní cesty bez UI: `JobTransPurchOrders.SetTableView(JPL s SetRecFilter)` + `SetCreateNewPurchaseOrder(true)` +
  `UseRequestPage(false)` + `RunModal()`; řádek plánování Item s `Vendor No. EPEBS` a `Create Purchase Order EPEBS = true`
  (eligibility = flag + bez objednávky + `Remaining Qty. <> 0`); `OnPostReport` otevře kartu objednávky (`[PageHandler]` na
  `Purchase Order`) a dá `Message` (`[MessageHandler]`). Prodejní cesta = přímé volání `CreateSalesOrder(JobNo, Bill-to, …)`.
  `Library - ERM.SetJournalTemplateNameMandatory` v W1 knihovně není (AL0132) — testy účtování v cust-soitron-bc ho
  nepotřebují. (2026-10-09, cust-soitron-bc `Logistic Officer Test SOI`, kompilace čistá, běh v kontejneru až při push.)
- **Prodejce / nákupčí na dokladech projektu (PBI 64804 bod 1, 2026-10-12):** `Job.GetDocumentSalespersonCodeEPEBS()` (EP Project Base)
  = `User Setup."Salespers./Purch. Code"` uživatele v `Job."Project Manager"` (standardní pole, relace User Setup), fallback
  `Person Responsible` (číslo zdroje — musí existovat i jako Salesperson, jinak `Validate("Purchaser Code")` spadne; testy
  zakládají Salesperson se stejným kódem jako Resource). Volá se ze všech generátorů (EPEBS `CreatePurchaseOrder`, tendr
  poptávka/objednávka, IMEBS `CreateSalesOrder`) **a** z `OnValidate` pole `Job No. EPEBS` na Purchase/Sales Header EPEBS
  (`UpdatePurchaserCodeFromJobEPEBS` / `UpdateSalespersonCodeFromJobEPEBS`, prázdný kód hlavičku nemění) → ruční zadání projektu
  přepíše prodejce. Tendr `Job No. EPEBS` na poptávku nenastavuje, proto helper i v `Tender Management`. Kompilace: EPEBS má
  AppSource range (AppSourceCop), IMEBS PTE range (PTE cop); test IMEBS chce EPEBS ≥ 28.0.24.0 → v temp cache přepsat verzi
  čerstvého EPEBS buildu v kopii `app.json`. `User Setup` v testu: `Init` + `"User ID" := GenerateGUID` + `Insert(true)`.

### 5.x23 Undo nákupní příjemky s projektem: standard předpokládá zaúčtovanou spotřebu projektu — „Skip Purchase Consumption" (IMEBS) ho shodí

- **Standard (w1-28 `Undo Purchase Receipt Line.PostItemJnlLine` + `Undo Posting Management`)** u řádku příjemky s `Job No.` nedělá
  prostou korekci (`Correction` + `Applies-to Entry` jen při prázdném Job No.), ale: položku zboží pošle s `Job Purchase = true`
  bez `Applies-to Entry` (v `PostItemJnlLineAppliedToList` je u Job No. <> '' `Applies-to Entry := 0`), `UndoPostingMgt.PostItemJnlLine`
  k ní přidá **druhou položku Negative Adjmt. s projektem** (reverz spotřeby, `PostItemJnlLineForJob`), pak `UndoValuePostingWithJob`
  a `ReapplyJobConsumption(ItemRcptEntryNo)` → `FindItemReceiptApplication`: `Item Application Entry` s `Inbound Item Entry No.` =
  položka příjmu a `Item Ledger Entry No.` <> ona (= vyrovnání příjem ↔ spotřeba projektu) + **`FindFirst()` bez guardu**.
  Když spotřeba při příjmu nevznikla, spadne to na „Neexistuje žádný Položka vyrovnání zboží ve filtru. Filtry: Číslo položky zboží:
  <>N, Vyrovnává položku číslo: N". Dvě cesty: bez trackingu (`Item Rcpt. Entry No.` vyplněno) přímo v `PostItemJnlLine`, s trackingem
  (Soitron šarže = číslo projektu → `Item Rcpt. Entry No. = 0`, Item Entry Relation) přes `CollectItemLedgEntries` →
  `ReapplyJobConsumptionFromApplyToEntryList` (else větev, kladná položka příjmu).
- **Kdo spotřebu vypne:** Essence Project Item Management `PurchPost_OnPostItemJnlLineJobConsumptionIMEBS` (`Purch.-Post.
  OnPostItemJnlLineJobConsumption`, `IsHandled` při `Job."Skip Purchase ConsumptionIMEBS"` a budget řádku navázaném z billable řádku
  přes `Purch. Job Cont.Entry No.IMEBS`) — zboží zůstane na skladě, spotřeba se účtuje až při dodávce prodejky (`PostConsumption`
  z položky příjmu). Undo takové příjemky standard neumí; IMEBS zatím hook na undo nemá (testy `PurchConsumptionTest` undo nepokrývají).
- **Oprava patří do IMEBS** (ne do zákaznické appky): pro řádek příjemky „skip + navázaný" udělat z undo obyčejnou korekci —
  `Undo Purchase Receipt Line.OnAfterCopyItemJnlLineFromPurchRcpt(var ItemJnlLine, …, PurchRcptLine, …)`: `Job No./Job Task No. := ''`,
  `Job Purchase := false`, `Correction := true`, `Applies-to Entry := PurchRcptLine."Item Rcpt. Entry No."` (list cesta si Applies-to
  nastaví sama, když je Job No. prázdné); dále `IsHandled` v `OnPostItemJnlLineOnBeforeUndoValuePostingWithJob` (cesta bez trackingu)
  a `OnBeforeReapplyJobConsumptionFromApplyToEntryList` (cesta s trackingem) — podmínky čtou `PurchRcptLine."Job No."`, ne ItemJnlLine.
  ⚠️ `CheckItemLedgEntries` u položek s `Job No.` **netestuje `Remaining Quantity = Quantity`** (jen bez projektu) → když už byla
  navázaná prodejka dodána (příjem vyrovnán dodávkou, usage z `PostConsumption` existuje), standard undo nezablokuje; vlastní guard
  `TestField("Remaining Quantity", Quantity)` na položce příjmu (`OnCheckItemLedgEntriesOnBeforeCheckTempItemLedgEntry` nebo před
  účtováním). Hook `Undo Posting Management.OnBeforeReapplyJobConsumption(ItemRcptEntryNo, var IsHandled)` sám nestačí — zůstala by
  druhá Negative Adjmt. položka a Applies-to 0. (2026-10-14, cust-soitron-bc: NO 106182 / příjemka 107358, Base App 28.4.)

### 5.x24 Spotřeba projektu z prodejní dodávky (IMEBS `CreateJobLedgerEntryFromSalesLine`): víc příjemek, víc položek zboží na příjemce, tracking

- ⚠️ **`Job Jnl.-Post Line.CreateJobLedgEntry` volané přímo (mimo `Code`/`RunWithCheck`) dá položce `Entry No.` 0 při `Jobs
  Setup."Use Legacy Posting"`** (w1-28: `if not JobsSetup.UseLegacyPosting() then NextEntryNo := JobLedgEntry.GetNextEntryNo()`;
  s legacy účtováním plní `NextEntryNo` jen `Code` → `GetNextEntryNo` + `LockTable`). První položka v DB se s číslem 0 vloží, každá další
  spadne na *„The record in table Project Ledger Entry already exists. … Entry No.='0'"* — v CI (BC 28.0.46665 cz, legacy = true) tak
  prošel jen první test, který usage účtoval, a **všech 18 dalších** (i v jiné test codeunitě, data zůstávají díky AutoCommit) padlo stejnou
  hláškou (build 29038, 2026-10-22); na BC-DEV / X-ESSENCE (sekvence) to nikdo neviděl. Fix v IMEBS: manuálně bindovaný subscriber
  `Job Ledg. Entry No. IMEBS` (65134) na `Job Jnl.-Post Line.OnBeforeJobLedgEntryInsert(var JobLedgerEntry, JobJournalLine)` — když
  `"Entry No." = 0`, dosadí `FindLast + 1` (`ReadIsolation UpdLock`); bind jen kolem `CreateJobLedgEntry` v `PostConsumption`. Vazba
  `JobLinkUsage.ApplyUsage` i návratová hodnota berou číslo z téhož `var` recordu. Nový codeunit → doplnit do `Projects OBJ. IMEBS`.
  Totéž hrozí každému, kdo `CreateJobLedgEntry` volá napřímo (konfigurátor, time sheets…) — v testech to odhalí až DRUHÝ zaúčtovaný usage
  v jednom běhu codeunity.
- ⚠️ **JPLI dobropisu z plánovacího řádku (standardní `Job Create-Invoice` se záporným řádkem):** `PostInvoiceContractLine` otevřený záznam
  `Job Planning Line Invoice` typu Credit Memo sám převede na *Posted Credit Memo* (Document No. = zaúčtovaný dobropis, Line No. řádku) ještě
  **před** `OnBeforeJobPlanningLineUpdateQtyToInvoice` — vlastní insert téhož typu pak spadne na duplicitní klíč (dřív IMEBS vkládal *Posted
  Invoice*, klíč se nekryl a chyba se maskovala). Před vlastním insertem `Get` na posted klíč → exit. (Test `CrMemoAmount_PostedCreditMemo_…`,
  tentýž build.)
- **`Sales-Post.OnBeforePostJobContractLine` běží z `UpdateSalesLineBeforePost`, tj. PŘED `PostItemTrackingLine` /
  `PostItemLine`** (w1-28 `SalesPost.Codeunit.al`: `PostSalesLine` → `UpdateSalesLineBeforePost` → `PostJobContractLine`
  → … → `PostItemLine` → `InsertShipmentLine`). V tom subscriberu ještě neexistují položky zboží dodávky ani `Item Entry
  Relation`. ⚠️ **Rezervační položky řádku (`Qty. to Handle (Base)` trackingu) NEJSOU dodávané množství:** řádek sledování
  na celé množství objednávky (šarže = číslo projektu u Soitronu, ručně zadaný tracking) se částečnou dodávkou neupraví —
  `Sales-Post.CheckTrackingSpecification` rovnost s `Qty. to Ship (Base)` hlídá jen u zboží, kde tracking na prodeji
  **není** vyžadovaný (`TrackingRequired()` → kontrola se přeskočí), u Lot/SN Specific si `Sales Line-Reserve.
  TransferSalesLineToItemJnlLine` prostě odebere dodávané množství z řádku sledování (5 na řádku, dodáno 2 → projde).
  První verze přepisu (2026-10-19 ráno) z toho u dodávky 2 z 5 zaúčtovala usage 5 a při druhé dodávce 3 celkem 8 →
  `Job Link Usage` zvedl množství budget řádku z 5 na 8 (ověřeno uživatelkou na BC-DEV). **Správně: spotřebu účtovat až
  z položek zboží dodávky** — subscriber `Sales-Post.OnAfterInsertShipmentLine(var SalesHeader, var SalesLine, var
  SalesShptLine, PreviewMode, xSalesLine)` (po `SalesShptLine.Insert` i `InsertShptEntryRelation`), položky =
  `ItemTrackingMgt.CollectItemEntryRelation(TempILE, Database::"Sales Shipment Line", 0, DocNo, '', 0, LineNo, 0)`
  (tracking → `Item Entry Relation`) a když je prázdné, `SalesShptLine."Item Shpt. Entry No."` (bez trackingu); Sale
  položky jsou záporné. `Sales Shipment Line.GetItemLedgEntries` v w1-28 není. Event dává skutečný `SalesLine` (ne kopii
  s přepsaným Document No. z 5.x25), usage tedy dál nese číslo objednávky.
- **Položky příjmu budget řádku:** všechny `Purch. Rcpt. Line` (Job No. / Job Task No. / `Job Planning Line No. EPEBS`,
  Type Item) × všechny ILE řádku (`Document Type = Purchase Receipt` + `Document No.` + `Document Line No.`, klíč Key9) —
  tracking rozdělí jeden řádek příjemky na položku per SN / šarže / zásilka. `FindFirst` na obou úrovních (původní kód)
  bral jen první příjemku a první položku.
- **Přepis 2026-10-19 (prod-ep-itemManagement-bc, větev `features/misc`) — požadavek PO (Honzík): JLE Usage : položka
  příjmu = 1:1** (jedna položka projektu na celé množství jedné položky příjmu, jinak se nedají dát dohromady náklady).
  Dodávané množství per tracking (SN, Lot, Package, Expiration Date) = Σ položek zboží **všech** dodávkových řádků
  objednávkového řádku (`Sales Shipment Line` klíč `Order No.` + `Order Line No.`, bez `Correction`), mínus usage už
  zaúčtované pro budget řádek (navázané na jeho položky příjmu + nenavázané přes `Job Usage Link`); položky příjmu se
  stejným sledováním (expirace jen když ji dodávka nese) se účtují v pořadí vzniku **celé a teprve když je dodané
  množství pokryje** — částečná dodávka přes hranici příjemky tedy spotřebu té položky odloží na dodávku, která ji dokončí
  (usage dodávku nikdy nepředběhne; příjem 2+3+1, dodávka 3+3 → usage 2 | 3+1). Při plně dodaném řádku (`"Quantity Shipped"
  + "Qty. to Ship" >= Quantity` — Quantity Shipped se aktualizuje až v `PostUpdateOrderLine`) se zbytek doúčtuje na
  blokující položku (částečně) nebo bez vazby (`Ledger Entry No.` 0, tracking z dodávky). Dodávka bez sledování bere
  libovolnou položku příjmu a přebírá její tracking (`JobJournalLine.CopyTrackingFromItemLedgEntry`). Mezisoučty v temp
  `Tracking Specification` (bucket) a temp `Item Ledger Entry` (`Remaining Quantity` = množství ještě nenavázané na usage).
  Varianta „eager" (spotřebovat celou položku příjmu, jakmile se z ní něco dodá) zamítnuta: projekt by spotřeboval zboží,
  které je fyzicky skladem a nemusí se už nikdy dodat. `Job Jnl.-Post Line.CreateJobLedgEntry` kopíruje SN / Lot /
  Package (`CopyTrackingFromJobJnlLine`) a přes `Job Link Usage.HandleMatchUsageSpecifiedJobPlanningLine` **přepíše Lot/SN
  na budget řádku plánování** (`CopyTrackingFromJobLedgEntry`) — po víc JLE zůstane poslední; a když Σ usage přesáhne
  `Quantity` řádku, `HandleMatchUsageSpecifiedJobPlanningLine` udělá `Validate(Quantity, Σ)` → množství i cena řádku
  plánování se „sama" změní (příznak nadspotřeby, ne feature). Testy `Purch. Consumption Test IMEBS` (dvě příjemky, dvě
  dodávky 1+4 proti 2+3, dvě šarže, nepřijatá šarže, řádek sledování 5 dodaný 2+3 → usage 2+3 a budget řádek zůstane 5).
- **Přepis podruhé (2026-10-21, tamtéž, rozhodnutí uživatele po testu na X-ESSENCE): usage = per položka zboží DODÁVKY, ne per položka
  příjmu.** Dodávka 600 + 400 musí dát spotřebu 600 + 400 hned při každé dodávce (původní 1 : 1 k položce příjmu dalo při jedné příjemce
  na 1000 jednu spotřebu až druhou dodávkou — uživatel to reklamoval jako chybu). Nová logika (`CreateJobLedgerEntryFromSalesLine` →
  `PostConsumptionForShippedTracking`): položky zboží **jen právě vloženého dodávkového řádku** (`CollectPostedLineItemEntries` přes `Item Entry
  Relation` / `Item Shpt. Entry No.`) → bucket per tracking → z položek příjmu rozpočtového řádku se stejným trackingem v pořadí účtování se
  bere `Remaining Quantity` kopie (přijato − netto usage navázaná na položku − vráceno dodavateli) → jedna usage per (dodávka × položka
  příjmu), zbytek hned bez vazby (dodáno dřív než přijato, šarže ze skladu). Žádné čekání na pokrytí položky příjmu, žádný
  `LineFullyShipped` / blokující položka / kumulace přes kontrakt — storno u dobropisu i opětovná dodávka vrácených kusů fungují přes netto
  usage per položka příjmu samy. Sale zůstává per řádek faktury (standard; dodávka výnos neúčtuje). Testy přepsány: 2+3 / 1+4 → usage
  1 | 1+3; 2+3+1 / 3+3 → 2+1 | 2+1; tracking řádek 5 dodaný 2+3 → 2 | 3 na téže položce příjmu (`VerifyUsageQtyLinkedToItemEntry` =
  počet + součet per položka příjmu).
- ⚠️ **IMEBS `CreateItemTrackingForSalesLine` (šarže / SN z řádku plánování na prodejní řádek) zapisuje do `Tracking
  Specification` (336), ne do `Reservation Entry`** — dodávka tracking z 336 nebere (336 čte jen `RetrieveInvoiceSpecification`
  pro fakturaci dodaného), takže řádek z plánovací řádky se šarží se pravděpodobně chová jako bez sledování. Neopraveno,
  jen zjištěno při přepisu výše (žádný test to nepokrývá).

### 5.x25 Přecenění položek projektu po adjustaci nákladů (`Update Job Item Cost`, 1095) — co standard umí a kde IMEBS spotřeba z dodávky vypadává

- **Kdy běží:** `Inventory Adjustment.PostItemJnlLine` sbírá `OrigValueEntry."Job No."` (ne ILE) do `JobsToAdjust`;
  `RunUpdateJobItemCost` po `MakeMultiLevelAdjmt` spustí report **jen při `Jobs Setup."Automatic Update Job Item Cost"`**
  (jinak ručně z karty projektu), per projekt `Job.SetRange("No.")`, jen Job Status Planning / Quote / Open.
- **Co report dělá (w1-28):** JLE `Type = Item`, `Entry Type = Usage`, `Ledger Entry Type = Item` → ILE z `Ledger Entry No.` →
  Value Entry filtr **`Job No.` + `Job Task No.` + `Job Ledger Entry No.` + `Item Ledger Entry Type = Negative Adjmt.` +
  `Document Type = Purchase Invoice`** (= standardní spotřeba projektu z nákupní příjemky). Když nic nenajde, bere
  **celou** `ILE."Cost Amount (Expected)" + "Cost Amount (Actual)"` a nastaví `JLE."Total Cost (LCY)" := -hodnota`
  (znaménko počítá se záporným Negative Adjmt.). Pořadí v `PostTotalCostAdjustment`: Total/Unit Cost → `Adjusted := true` →
  `OnPostTotalCostAdjustmentOnBeforeJobLedgEntryModify(var JLE, ILE)` → `Modify` → **`UpdatePostedTotalCost(delta)`** přes
  `Job Usage Link` → `JobPlanningLine.UpdatePostedTotalCost` (jen `Posted Total Cost (LCY)`, nikdy plánovaný `Unit Cost`).
  Plánovaný `Unit Cost (LCY)` řádku plánování report přepisuje **jen u `System-Created Entry`** řádků (vzniklých z
  `MatchUsageUnspecified`); ručně plánované řádky si cenu drží navždy. Standard tedy „přepočet částek na řádcích
  plánování" po adjustaci dělá jen v `Posted Total Cost (LCY)`.
- **IMEBS usage z prodejní dodávky** (`PostConsumption`, `Ledger Entry No.` = **kladná položka nákupního příjmu**, ne
  Negative Adjmt.): filtr VE nic nenajde → fallback = náklad celé příjemky se záporným znaménkem na usage s částí
  množství. První verze modulu (06/2026, přímý `JobLedgerEntry.Insert`) to nechaly běžet → „automatické přecenění", ale
  na špatná čísla. Od 374f10c (2026-08-24) subscriber na `OnPostTotalCostAdjustmentOnBeforeJobLedgEntryModify`
  vrátí JLE z DB (`JobLedgerEntry := OrigJobLedgerEntry`) → ceny z řádku plánování zůstanou. ⚠️ Blokovat **v tomhle
  eventu nestačí**: `Adjusted` zůstane false a `UpdatePostedTotalCost(delta)` za `Modify` se zavolá stejně → při
  každém běhu adjustace přičte deltu (celá příjemka − usage) do `Posted Total Cost (LCY)` budget řádku s usage linkem
  (od 4b6d257 jde JLE přes `Job Jnl.-Post Line.CreateJobLedgEntry` → `ApplyUsage` → link existuje). Správné místo je
  `OnBeforePostTotalCostAdjustment` (exit před výpočtem) nebo vlastní výpočet: Σ VE příjmové položky
  (`Item Ledger Entry No.` = `JLE."Ledger Entry No."`, Actual + Expected) / `ILE.Quantity` × `JLE.Quantity` + vlastní
  `UpdatePostedTotalCost`. (2026-10-19, prod-ep-itemManagement-bc, analýza zadání „ocenění položek projektu dle ILE".)
  **Opraveno tamtéž (2026-10-19, větev `features/misc`):** nový subscriber `UpdateJobItemCost_OnBeforePostTotalCostAdjustmentIMEBS`
  (`OnBeforePostTotalCostAdjustment(var JobLedgEntry, ItemLedgerEntry, …, var IsHandled)`, pro ILE typu Purchase `IsHandled := true`),
  původní subscriber ponechán jako pojistka s komentářem. Test `UpdateJobItemCost_UsageFromShipment_KeepsEntryAndPostedCostOfBudgetLine`
  (`Purch. Consumption Test IMEBS`): report puštěný 2× přes `SetTableView(Job s SetRecFilter)` + `UseRequestPage(false)` +
  `SetProperties(true)` (potlačí závěrečnou `Message`) + `RunModal()`; assert `Total Cost (LCY)` + `Adjusted = false` na JLE a
  `Posted Total Cost (LCY)` budget řádku. Bez `SetProperties(true)` by test potřeboval `[MessageHandler]`.
- **Sale JLE z fakturace** (`Job Transfer Line.FromPlanningSalesLineToJnlLine`): `Unit Price` = **`JobPlanningLine."Unit
  Price"`** (ne prodejní řádek!), `Line Discount %` = `SalesLine`, `Unit Cost` = `SalesLine."Unit Cost (LCY)"` (jen když
  `DoUpdateUnitCost` — Standard costing bez projektu ne), `Direct Unit Cost (LCY)` = planning line. Změna ceny na
  objednávce se tedy do položky projektu nepropíše — `Job Post-Line.ValidateRelationship` hlídá jen shodu `Unit Cost (LCY)`
  (event `OnValidateRelationshipOnUnitCostLCYDifferenceError`), cenu ne. Cena z dokladu = `OnAfterFromPlanningSalesLineToJnlLine`
  → `Validate("Unit Price", SalesLine."Unit Price")`. `Job Jnl.-Post Line.PostItem` u Usage náklad z VE **nečte**
  (`UpdateJobJnlLineTotalAmounts` = Unit Cost řádku × množství z VE), takže ani standardní spotřeba není „dle ILE" při
  účtování — až report 1095. `Job Planning Line Invoice."Invoiced Amount (LCY)"` = `CalcLineAmountLCY` z ceny řádku plánování.
- **Vlastní přecenění položek projektu reportem (IMEBS `Update Job Item Cost IMEBS`, 65131, 2026-10-19, větev `features/misc`):**
  zrcadlo 1095 pro položky, které standard neumí — Usage s `Ledger Entry No.` na kladnou položku nákupního příjmu: `Unit Cost (LCY)` =
  Σ VE příjmové položky (`ILE.CalcFields` Expected + Actual, u non-inventory Non-Invtbl.) / `ILE.Quantity` × `JLE."Quantity (Base)"`, FCY přes
  `ExchangeAmtLCYToFCY` s `JLE."Currency Factor"`, `Adjusted` + `DateTime Adjusted`, delta přes `Job Usage Link` →
  `JobPlanningLine.UpdatePostedTotalCost(AdjustJobCost, AdjustJobCostLCY)` + `Modify()` (CodeCop **AA0214** „record should be modified before
  saving" — změna je uvnitř table metody, `#pragma warning disable AA0214` kolem; Essence CI má failOn warning). Sale: cena z `Sales Invoice
  Line` / `Sales Cr.Memo Line` přes `Job Planning Line Invoice."Job Ledger Entry No."` (Key2 = Document Type, Document No., JLE No.; filtr jen
  na JLE No. jde přes PK prefix Job No. + Job Task No.), přepočet LCY ↔ měna položky, `Line Discount %` z dokladu, částky formulí
  `Quantity × Unit Price` (množství Sale záporné → záporné částky), ACY přes `ExchangeRate(date, ARC)`. Idempotentní: cílové hodnoty se
  počítají vždy znovu a `Modify` jen při rozdílu. Spouštění: akce na Job Card / Job List (`addafter("Create Job &Sales Invoice")` — na Job
  Card ani Job List **žádná akce `"Update Job Item Cost"` není**, AL0271; standardní report se spouští jen z adjustace / Tell me), Job
  Queue (Object Type Report, request page jen filtry `SaveValues`), a subscriber `Inventory Adjustment.OnBeforeRunUpdateJobItemCost(var
  JobsToAdjust: List of [Code[20]])` (event běží PŘED kontrolou `Jobs Setup."Automatic Update Job Item Cost"` → setup si zkontroluj sám,
  ať platí jeden vypínač), stejný způsob běhu jako standard (`SetTableView(Job)`, `UseRequestPage(false)`, `SetProperties(true)`, `RunModal`).
- **Vazba Sale JLE ↔ zaúčtovaný řádek faktury u objednávky fakturované z objednávky:** `Job Post-Line.UpdateJobLedgerEntryNoOnJobPlanLineInvoice`
  hledá JPLI podle `Job No.` + `Job Task No.` + **`Document No.` + `Line No.` z Job Journal Line** (bez Document Type). JJL `Document No.` =
  `SalesLine."Document No."` → u Order číslo objednávky, zatímco JPLI Posted Invoice (IMEBS `OnBeforeJobPlanningLineUpdateQtyToInvoice`) nese
  číslo zaúčtované faktury → `Job Ledger Entry No.` zůstane 0. Oprava v IMEBS `SalesPost_OnBeforePostJobContractLineIMEBS`: před
  `InvoicePostingInterface.PrepareJobLine(SalesHeader, SalesLine, …)` přepsat na kopii `SalesLine."Document No." := <posted invoice no.>`
  (z `OnAfterInsertPostedHeaders` → SingleInstance `Project Item Mgt. SI IMEBS`) — Sale JLE pak nese číslo faktury jako u Invoice dokladu a
  link se vytvoří. Testy: `Upd. Job Item Cost Test IMEBS` (65140; **název objektu max 30 znaků, AL0305** — „Update Job Item Cost Test IMEBS"
  má 31; soubor pak `UpdJobItemCostTest.Codeunit.al`, AA0215): nákup přijat → dodávka → `LibraryPurchase.ReopenPurchaseDocument` + jiný
  `Direct Unit Cost` + fakturace → report; změna `Unit Price` na objednávce → dodávka + faktura → report; `LibraryCosting.AdjustCostItemEntries`
  se zapnutým Automatic Update Job Item Cost (projekt se do `JobsToAdjust` dostane z VE prodejní dodávky, která u skip projektů nese Job No.
  — neověřeno během, jen ze zdrojů). `JobSalesPostTest.VerifySaleJobLedgerEntry` nově filtruje `Document No.` = posted invoice no.
- al-mcp `al_packages load` na složku bez `.alpackages` (temp cache ve scratchpadu): `autoDiscover: false` + `path` přímo na složku s `.app`.
  ⚠️ Přepis `Document No.` dělej na **lokální kopii** (`InvoiceSalesLine := SalesLine`): usage z dodávky
  (`CreateJobLedgerEntryFromSalesLine`, od 2026-10-19 odpoledne volaná z `OnAfterInsertShipmentLine`, 5.x24) bere z řádku
  `CalcFields("Posting Date")` (flowfield přes hlavičku) i `Document No.` usage položky — s číslem faktury na skutečném
  řádku by usage přišla o datum a nesla číslo faktury. Co kopii čte dál: `Job Post-Line` jen `Job Contract Entry No.` + `Line No.` (otevřený JPLI přes
  `SalesHeader."No."`), `Job Transfer Line` ji kopíruje do JJL (Document No., dimenze, texty, posting groups), G/L větev páruje
  temp JJL jen přes `Line No.`; EPEBS subscribery (`OnAfterFromPlanningSalesLineToJnlLine`, `OnBeforeJobLedgEntryInsert`) Document No.
  nečtou. Regresní test `ShipAndInvoiceInOneRun_SkipProject_UsageCarriesOrderNoAndSaleEntryCarriesInvoiceNo`. (2026-10-19)

### 5.x26 Nákupní dobropis / vratka dodavateli u Skip projektu s navázaným rozpočtovým řádkem — modul vypnul standard i pro vratky, kontrola spotřeby je vlastní

- ⚠️ **Druhá standardní kontrola nákupního dobropisu s projektem: `Job Post-Line.CheckItemQuantityPurchCredit`** — volá ji `Purch. Post
  Invoice.CheckCreditLine` z `Purch.-Post.PostPurchLine` u credit doc typů s `Job No.` (ne Purchase Line, ne Purch.-Post přímo; 2026-10-21
  jsem mylně napsal, že se nevolá odnikud). Vyžaduje `Job.GetQuantityAvailable(Item, Location, Variant, Usage, Both)` ≥ vrácené množství
  (netto Usage položky projektu na zboží) — *„You must post more usage or credit the sale of Item … before you can post purchase credit
  memo"*. U Skip projektu s navázaným řádkem spotřeba při příjmu není (zboží je skladem) → kontrola padá, pokud projekt nemá netto usage
  z dodávek alespoň ve výši vratky (CI build 29039: 3 testy; v GUI prošlo jen náhodou — netto usage 75 ≥ vratka 25). Fix: IMEBS
  `Job Post-Line.OnBeforeCheckItemQuantityPurchCredit(var PurchaseHeader, var PurchaseLine, var IsHandled)` → `IsHandled` pro Skip projekt
  s navázaným rozpočtovým řádkem (vlastní kontrola `CheckReturnedQtyOnInventoryForProject` zůstává). `Purch. Post Invoice` má ještě vlastní
  `PurchPostInvoiceEvents.RunOnBeforeCheckItemQuantityPurchCredit`, ale event na `Job Post-Line` stačí.
- **Standard u vratky s projektem** (`Purch.-Post.PostItemJnlLine`, w1-28: `PostJobConsumptionBeforePurch := ItemJnlLine.IsPurchaseReturn()`
  → `PostItemJnlLineJobConsumption` běží **před** zaúčtováním položky vrácení, `PurchItemLedgEntryNo = 0`) chce odúčtovat spotřebu z příjmu
  (kladná korekce s projektem + záporná Usage přes `PrepareJobLine`) a bez ní spadne na `Appl.-from Item Entry` — tj. zboží, které projekt
  spotřeboval, se dodavateli vrátit nedá. IMEBS subscriber `OnPostItemJnlLineJobConsumption` (`IsHandled` u Skip projektu s rozpočtovým
  řádkem navázaným z billable řádku) tuhle větev vypínal **i pro vratky** → dobropis prošel bez položky projektu a bez kontroly skladu
  (záporná zásoba / zboží jiného projektu), usage z dodávky zůstala (ověřeno uživatelem v Posting Preview, 2026-10-20).
- **Oprava (prod-ep-itemManagement-bc, větev `features/misc`, 2026-10-20):** v tomtéž subscriberu u `PurchHeader.IsCreditDocType()` kontrola
  **per sledování**: vráceno ≤ přijato pro rozpočtový řádek − usage navázané na položky příjmu − dříve vráceno − nenavázané usage
  (`CheckReturnedQtyOnInventoryForProject`, jinak `Error` „cannot be returned to the vendor… Post the sales credit memo of the customer
  return first“). Vrácené množství per tracking = `TempPurchReservEntry` eventu (Purch.-Post do něj sbírá tracking item jnl line,
  `CollectPurchaseLineReservEntries`; outbound `Quantity (Base)` záporné), bez trackingu `ItemJournalLine."Quantity (Base)"` (u credit
  doc typů záporné — `ReverseAmount`) → `Abs`. Event běží před položkou zboží → chyba zastaví i Posting Preview. Dřívější vratky se
  odečítají i v `CollectReceiptItemEntries` (`SubtractReturnedQuantities`): `Return Shipment Line` má standardní `Job Planning Line No.`
  (1019, TransferFields z Purchase Line; EPEBS pole na vratce/dobropisu **není**), položky `Document Type = Purchase Return Shipment`
  se záporným množstvím, nejdřív podle vyrovnání (`Item Application Entry` Key3 `Outbound Item Entry No.` + `Item Ledger Entry No.`,
  `Quantity` záporné → Abs), zbytek FIFO per tracking; `Remaining Quantity` kopie tedy = přijato − usage − vráceno, „už spotřebováno“
  z ní nejde odvodit (`GetUsageQtyBaseLinkedToItemEntry` znovu). Pozdější dodávka se na vrácenou položku příjmu nenaváže (usage bez
  `Ledger Entry No.`). Storno spotřeby patří k **prodejnímu** dobropisu (vratka od zákazníka) — dohodnuto jako další krok, zatím
  neimplementováno.
- **Posting Preview položky projektu zobrazuje** (`Posting Preview Event Handler` subscriber na `Job Ledger Entry.OnAfterInsertEvent`,
  page `Job Ledger Entries Preview`; `Job Jnl.-Post Line` sám nic nereguje) → chybějící „Položka projektu“ v náhledu = opravdu nevznikla.
- **Získat účtované řádky pro stornování:** nákup job pole **kopíruje** (`CopyPurchDocLine` → `CopyPurchaseJobFields`: `Validate` Job No. /
  Job Task No. / Job Planning Line No. / Job ceny), prodej je **maže** (`SetDefaultValuesToSalesLine` → `InitSalesLineFields` →
  `InitJobFieldsForSalesLine`; `CopySalesJobFields` jen s `CopyJobData` = Correct / Cancel). `Job Post-Line.CheckItemQuantityPurchCredit`
  se v w1-28 nevolá odnikud (ani Purchase Line, ani Purch.-Post).
- **Testy (`Purch. Consumption Test IMEBS`):** dobropisový řádek `LibraryPurchase.CreatePurchHeader(…, "Credit Memo", …)` + job pole jako u
  objednávky (Validate Job No. / Job Task No. / Job Planning Line No. / EPEBS pole); `Purchases & Payables Setup."Exact Cost Reversing
  Mandatory" := false` (jinak `TestField("Appl.-to Item Entry")`) — `LibrarySetupStorage.Save` **po** úpravě v suite initu, `Restore` hned
  po `OnTestInitialize`; šarže na dobropisový řádek `LibraryItemTracking.InsertItemTracking(ReservEntry, false, …, -Qty * QtyPerUoM, …,
  Database::"Purchase Line", DocType.AsInteger(), DocNo, '', 0, LineNo, "Expected Receipt Date")` (outbound, jako u prodejního řádku);
  vratku ověř `ILE Entry Type Purchase + Document Type Purchase Return Shipment`; zboží pro dodávku po vratce doplň `PostPositiveAdjustment`.
  Kompilace app i test čistá (alc 17.0 + CodeCop/PTE/UICop/ALCops), běh v kontejneru až při push. Uživatel ověřil na BC-DEV: nákupní
  dobropis po dodávce se zastaví hláškou (2026-10-20).
- **Prodejní dobropis = vratka od zákazníka → storno spotřeby per položka zboží (tamtéž, 2026-10-20):**
  - **Získat účtované řádky pro stornování u prodeje projektová pole MAŽE** (`CopySalesDocLine`: `"Job Contract Entry No." := 0` pro Credit
    Memo / Return Order ještě před `UpdateSalesLine`, pak `SetDefaultValuesToSalesLine` → `InitSalesLineFields` → `InitJobFieldsForSalesLine`
    smaže Job No./Task; `CopySalesJobFields` jen s `CopyJobData` = Correct/Cancel). Zpětné nasazení kontraktu: subscriber
    `Copy Document Mgt.OnCopySalesDocLineOnBeforeCopySalesJobFields(var ToSalesHeader, var ToSalesLine, var FromSalesHeader, var FromSalesLine,
    FromSalesDocType)` — běží po `UpdateSalesLine`, `FromSalesLine` je temp kopie účtovaného řádku (`TransferFields(FromSalesInvLine)`, kontrakt
    1002 nese); IMEBS tam pro Credit Memo z Posted Invoice / Posted Shipment dá Job No./Task/kontrakt původního billable řádku (jen Credit Memo —
    Return Order by při účtování spadl na `TestField("Job Contract Entry No.", 0)` v `PostJobContractLine`). Standard pak u dobropisu sám zaúčtuje
    Sale položku s kladným množstvím (`FromPlanningSalesLineToJnlLine` Credit Memo `-Quantity`), `ValidateRelationship` kontroluje Type/No./
    Location/Work Type/UoM/Variant/Gen. Prod./Line Discount %/Unit Cost (LCY) (IMEBS u Skip potlačí)/VAT % — kopie z faktury IMEBS objednávky
    sedí. Otevřená JPLI typu Credit Memo není třeba (`if Get`).
  - **Storno spotřeby z `Sales-Post.OnAfterReturnRcptLineInsert(var ReturnRcptLine, ReturnRcptHeader, SalesLine, ItemShptLedEntryNo, …,
    SalesCrMemoHeader, …, var SalesHeader)`** — řádek příjemky vratky i jeho `Item Entry Relation` (`InsertReturnEntryRelation` uvnitř
    `InsertReturnReceiptLineWhsePost`) už existují, bez trackingu `"Item Rcpt. Entry No."`. ⚠️ **Příjemka vratky u dobropisu vzniká jen se
    `Sales & Receivables Setup."Return Receipt on Credit Memo"`** (Sales-Post `if Credit Memo and SalesSetup."Return Receipt on Credit Memo"`);
    bez něj (X-ESSENCE CRONUS CZ, 2026-10-21, dobropis 104010 projektu PR01210) žádný dokument příjemky vratky není, položka zboží má
    `Document Type = Sales Credit Memo` a `Document No.` = číslo zaúčtovaného dobropisu, event nikdy nevystřelí a storno tiše neproběhne.
    Varianta nezávislá na nastavení = `Sales-Post.OnAfterPostItemJnlLine(var ItemJournalLine, SalesLine, SalesHeader, …, ShouldPostItemJnlLine,
    …)` (po `RunItemJnlPostLine` i tracking; `"Item Charge No."` = '' vyloučí poplatky) + položky zboží přes zaúčtovaný řádek deníku
    (`Document Type` + `Document No.` + `Document Line No.`, Key9, `Entry Type = Sale`, `Quantity > 0`) — implementováno a zkompilováno
    2026-10-21, ale **na přání uživatele vráceno** (rozhodnutí: nastavení se zapne, storno zůstává na řádku příjemky vratky; test appka
    nastavení zapíná v `Initialize`). IMEBS
    (`ReverseJobLedgerEntryFromSalesLine`) per tracking stornuje usage rozpočtového řádku: záporná Usage per položku příjmu, na kterou je usage
    navázaná (`GetUsageQtyBaseLinkedToItemEntry` = netto, pořadí účtování), zbytek z nenavázané usage; `PostConsumption` se záporným množstvím
    (`Job Link Usage.HandleMatchUsageSpecifiedJobPlanningLine` záporné `Use` zvládá — `Qty. Posted` klesne), `Document No.` = číslo zaúčtovaného
    dobropisu (`SalesCrMemoHeader` z eventu). Netto usage na položce příjmu klesne → další dodávka ji spotřebuje znovu a nákupní vratka
    projde kontrolou (5.x26 výše) — to byl požadavek PO (nejdřív prodejní, pak nákupní dobropis). Testy: `Initialize` dává `Return Receipt
    on Credit Memo := true` (Setup Storage Save po úpravě).
  - ~~„Dodáno" na úrovni kontraktu (`CollectShippedItemTracking` přes všechny dodávky kontraktu mínus vratky)~~ — **překonáno 2026-10-21**
    přepisem na usage per položka zboží dodávky (5.x24): dodávka bere jen své položky a konzumuje `Remaining Quantity` položek příjmu (netto
    po stornech), takže opětovná dodávka vrácených kusů funguje bez kumulace. Platí dál: `GetJPLQuantity` (množství k převodu do objednávky)
    přičítá otevřené i zaúčtované dobropisové řádky s kontraktem → vrácené množství jde znovu objednat.
  - **JPLI dobropisu:** IMEBS `OnBeforeJobPlanningLineUpdateQtyToInvoice` zakládal i pro Credit Memo JPLI typu Posted Invoice s kladným
    množstvím → nově `Posted Credit Memo` s **−Qty. to Invoice** (jak standard eviduje dobropis z plánovacího řádku; `Qty. Transferred to
    Invoice` je pak netto). `Job Planning Line.InitFromJobPlanningLine` (Copy Document faktury, Correct/Cancel) dělá `TransferFields` → kopíruje
    i `Purch. Job Cont.Entry No.IMEBS` na novou / stornovací řádku → `OnAfterInitFromJobPlanningLine(var ToJobPlanningLine, FromJobPlanningLine)`
    vazbu nuluje (1 : 1 budget ↔ billable). **Opravit / Stornovat fakturu (2026-10-21, doplněno na přání):** `Correct Posted Sales Invoice.
    CreateAndProcessJobPlanningLines` (volá se z `OnRun` = Cancel, `CreateCreditMemoCopyDocument` = Vytvořit opravný dobropis,
    `CreateCorrectiveCreditMemo` z notifikace) pro každý řádek s kontraktem zakládá stornovací plánovací řádek (`InitFromJobPlanningLine(From,
    -Quantity)` + JPLI Credit Memo) a přepíše `Sales Line."Job Contract Entry No."`; event `OnBeforeCreateAndProcessJobPlanningLines(var SalesHeader,
    var IsHandled)` → IMEBS `IsHandled := true`, řádek si nechá původní kontrakt (`CopySalesJobFields` s `CopyJobData` ho u Credit Memo kopíruje
    z faktury), účtování pak jde stejnou cestou jako dobropis z *Získat účtované řádky* (Sale storno na původní řádce, storno spotřeby z příjemky
    vratky, JPLI Posted Credit Memo −Qty). Test `JobSalesPostTest.CorrectiveCrMemo_*` přepsán (žádný záporný plánovací řádek v úloze), nový
    `CorrectiveCreditMemo_LinkedPurchaseShipped_KeepsContractEntryAndReversesUsage` v Purch. Consumption Test. `CreateCreditMemoCopyDocument`
    dává Confirm jen když objednávka faktury ještě existuje (po úplné fakturaci je smazaná → bez handleru).
  - **Vrátit dodávku (Undo Shipment) na řádku účtované dodávky (2026-10-22):** `Undo Sales Shipment Line.Code` per řádek: `PostItemJnlLine`
    (korekční ILE, kladná, vyrovnaná na dodanou, `Posting Date` = hlavička dodávky) → `InsertNewShipmentLine` (kopie řádku, `Quantity` záporné,
    `Correction = true`, `Item Shpt. Entry No.` = korekční ILE, `InsertItemEntryRelation` pro tracking) → **`OnAfterInsertNewShipmentLine(var
    SalesShipmentLine = PŮVODNÍ řádek, var PostedWhseShipmentLine, var PostedWhseShptLineFound, DocLineNo = číslo nového řádku,
    ItemShptEntryNo)`** → `UpdateOrderLine` (až potom, `Quantity Shipped` objednávky v eventu ještě nesnížené). IMEBS tam stornuje spotřebu
    stejně jako u vratky od zákazníka (`ReverseConsumptionForItemEntries`): položky korekčního řádku přes `CollectPostedLineItemEntries(Sales
    Shipment Line, DocNo, DocLineNo, ItemShptEntryNo)`, objednávkový řádek `SalesLine.Get(Order, "Order No.", "Order Line No.")` (při undo
    existuje, dodávka nesmí být fakturovaná), `Document No.` = číslo objednávky, `Posting Date` = datum dodávky (`PostConsumption` dostal
    parametr `PostingDate`, 0D = datum hlavičky prodejního dokladu). Test `UndoShipment_LinkedPurchaseShipped_…`: `SetRecFilter` +
    `SetHideDialog(true)` + `Run` (bez handleru), po undo `SalesHeader.Get` a znovu `PostSalesDocument(…, true, false)` → usage znovu na položku
    příjmu.
  - **Prodejní vratková objednávka (Return Order) s *Získat účtované řádky pro stornování* (2026-10-22):** stejný copy hook dá řádku
    kontrakt (+ EPEBS číslo řádku), ale **Job No. / Job Task No. nechá prázdné jako u objednávky** — `TestSalesLineJob` i `PostSalesLine`
    vyžadují prázdné Job No. u všech typů kromě Invoice / Credit Memo a `Whse.-Sales Release` zakládá skladové požadavky jen pro řádky bez
    Job No.; účtování Job No. doplní (`OnPostSalesLineOnBeforeUpdateSalesLineBeforePost` rozšířen o Return Order) a kontroly skipne přes
    `IsJobNoFromContractPlanningLine`. Sale storno: `PostJobContractLine` u Return Order dělá `TestField("Job Contract Entry No.", 0)` →
    IMEBS `OnBeforePostJobContractLine` (`IsHandled`) sám volá `PrepareJobLine` při `Invoice` s kopií řádku s číslem zaúčtovaného dobropisu
    (jako u Order s číslem faktury); `Job Transfer Line` nemá pro Return Order větev množství → IMEBS `OnFromPlanningSalesLineToJnlLineOnBeforeInitAmounts`
    `-Qty. to Invoice`; JPLI Posted Credit Memo −Qty (stejně jako Credit Memo); `JobLineChecked` i pro Return Order + Invoice. Storno spotřeby
    z `OnAfterReturnRcptLineInsert` (vratková objednávka příjemku vratky dělá vždy), `Document No.` = číslo vratkové objednávky. Skladové filtry
    (`Get Source Documents` Source Document *Sales Return Order*, `Whse.-Sales Release`) rozšířeny o Return Order, `GetJPLQuantity` bere otevřené
    řádky vratkové objednávky jako uvolněné množství. Test `ReturnOrderFromPostedInvoice_…` (receive → usage −; invoice → Sale +, JPLI).
  - ⚠️ **Řádek faktury / dobropisu se smluvní položkou NEúčtuje položky zboží:** `Sales-Post.PostItemJnlLine` má `ShouldPostItemJnlLine :=
    not JobContractLine` (`JobContractLine` nastaví `PostJobContractLine` u Invoice / Credit Memo; u Order ho IMEBS `OnBeforePostJobContractLine`
    `IsHandled` nechá false). Projektová faktura z plánovacích řádků zboží nehýbe, ale dobropis Skip projektu zboží fyzicky vrací → bez položek
    vratky by storno spotřeby nemělo z čeho jet (Posting Preview: Project Ledger Entry ano, Item Ledger Entry zmizely — BC-DEV 2026-10-20).
    Fix: `OnPostItemJnlLineOnBeforeIsJobContactLineCheck(var ItemJnlLine, SalesHeader, SalesLine, var ShouldPostItemJnlLine, var ItemJnlPostLine,
    QtyToBeShipped)` → pro Credit Memo + kontrakt + Skip projekt `ShouldPostItemJnlLine := true`. Stejná větev zřejmě platí i pro **fakturu přes
    Získat řádky dodávky** (řádek s kontraktem → fakturační value entry k dodávce se neúčtuje) — neověřeno, otevřená otázka.
  - Testy `CreditMemoFromPostedInvoice_*`: dobropis z faktury v testu = `CopyDocumentMgt.SetProperties(false, false, false, false, true, true,
    false)` + `CopySalesInvLinesToDoc(CrMemoHeader, SalesInvoiceLine s filtrem Document No., LinesNotCopied, MissingExCostRevLink)` (stejně
    jako page 5850); částečná vratka = `Validate(Quantity, menší)` na zkopírovaném řádku. Kompilace čistá, běh až v CI.

### 5.x27 Spotřeba projektu z deníku zboží (IMEBS `Item Jnl. Project Usage IMEBS`, list „Spotřeba projektů") — W1 bez CZ šablony pohybu zásob

- **Zadání (2026-10-27, prod-ep-itemManagement-bc, větev `features/misc`):** list deníku zboží s příznakem `Project Consumption IMEBS`
  (tableextension 65133 `Item Journal Batch`, jen šablony typu Item — `TestField(Type)`); řádek Výdej (`Negative Adjmt.`) zaúčtuje položku
  projektu Usage s kladným množstvím, Příjem (`Positive Adjmt.`) Usage se záporným (storno), obojí `Ledger Entry No.` = položka zboží
  korekce, Job No. / Job Task No. jdou do ILE i VE standardem (`Item Jnl.-Post Line` řádky ~2037 / 2612 je kopíruje vždy, žádná vlastní
  práce). Původní požadavek „Šablona pohybu zásob projektů v nastavení" = CZ `Invt. Movement Template CZL` (Core Localization Pack for
  Czech) — IMEBS je W1 appka bez CZ závislosti (`.alpackages` jen W1 + EPEBS) → místo šablony **dvě pole v `Essence Projects Setup EPEBS`:
  `Neg. Adjmt. Gen. Bus. PG IMEBS` / `Pos. Adjmt. Gen. Bus. PG IMEBS`** (obecná obchodní účto skupina pro výdej / příjem; rozhodnutí
  uživatele). Řádek ji dostane v `OnAfterSetupNewLine` (nový řádek flagovaného listu = Negative Adjmt. + skupina) a v `OnAfterValidateEvent
  "Entry Type"`; před účtováním `TestField("Gen. Bus. Posting Group", <setup>)`.
- **Izolace od dokladů:** všechno visí na `IsProjectConsumptionLine` = `Journal Template Name` + `Journal Batch Name` neprázdné + `Get`
  listu + flag. Řádky deníku zboží z účtování dokladů (Sales-Post, Purch.-Post, undo, `CalledFromAdjustment`) mají šablonu/list prázdné →
  nic se nespustí; stávající spotřeba z dodávek / dobropisů (5.x24–5.x26) nedotčena. Vlastní pole `Job Planning Line No. IMEBS` mimo
  flagovaný list = `FieldError` při kontrole (jinde by se ignorovalo).
- **Standardní pole `Item Journal Line."Job No."` (1000) a `"Job Task No."` (1001) nemají ani OnValidate, ani TableRelation** (w1-28:
  jen Caption) a na page 40 `Item Journal` nejsou. Validace přes tableextension `modify("Job No.") { trigger OnAfterValidate() }` (Job.Get +
  `TestBlocked`, změna maže úkol a řádek plánování, `CreateDimFromDefaultDim(FieldNo("Job No."))`), `modify("Job Task No.")` (Posting
  typ); lookup na pageextension přes **page-field `TableRelation = Job` / `"Job Task"."Job Task No." where("Job No." = field("Job No."))`**
  (property page fieldu, tabulkové pole se nemění). Default dimenze projektu na řádek přes `Item Journal Line.OnAfterInitDefaultDimensionSources`
  (`DimensionManagement.AddDimSource(DefaultDimSource, Database::Job, "Job No.")`), dimenze úkolu projektu až na JLE
  (`CreateDimSetFromJobTaskDim` + `GetCombinedDimensionSetID`, jako `Job Journal Line.UpdateDimensions`).
- **Kontrola před účtováním = `Item Jnl.-Check Line.OnAfterCheckItemJnlLine(var ItemJnlLine, CalledFromInvtPutawayPick, CalledFromAdjustment)`**
  (konec `RunCheck`, volá ji `Item Jnl.-Post Batch.CheckLines` i `Item Jnl.-Post Line.Code` → platí pro list i náhled účtování; `EmptyLine`
  řádky event nedostanou). `Item Jnl.-Check Line` sám žádnou kontrolu projektu nemá. Kontroluje: Entry Type ∈ {Negative, Positive Adjmt.}
  (`FieldError` s labelem „must be %1 or %2 in a batch with %3"), `Item Charge No.` = '', `Value Entry Type` Direct Cost, skupina ze setupu,
  Job No. / Job Task No. (Job `TestBlocked` + **`TestField("Apply Usage Link", true)`** — bez usage linku nejde vázat na řádek plánování ani
  zakládat nový), úkol typu Posting, vyplněný řádek plánování = Budget (`Schedule Line`) Item téhož zboží s Usage Link bez System-Created.
- **Účtování = `Item Jnl.-Post Line.OnAfterPostItemJnlLine(var ItemJournalLine, ItemLedgerEntry = GlobalItemLedgEntry, …, CalledFromAdjustment,
  …)`** — konec `PostItemJnlLine`, u řádku se sledováním běží per rozdělený řádek (SN / šarže) → jedna JLE na položku zboží, tracking přes
  `JobJournalLine.CopyTrackingFromItemLedgEntry`. Guardy: `CalledFromAdjustment`, Entry Type, `Item Charge No.`, `ILE."Entry No." <> 0`,
  `ILE.Quantity <> 0`, shoda `Item No.` + `Entry Type` s řádkem. JLE stejnou cestou jako `PostConsumption` (5.x24): `Job Journal Line` přiřazením
  (bez šablony/listu), `Validate("Qty. per Unit of Measure")`, `Validate(Quantity, −ILE.Quantity v MJ řádku)` s bindem `Skip Job Whse Pick
  Check IMEBS` (Validate(Quantity) → Validate("Job Planning Line No.") → whse pick check), pak **`Unit Cost (LCY)` := `ItemJournalLine."Unit
  Cost"`** (per MJ řádku v LCY = náklad, se kterým jde VE; `Validate(Quantity)` ho přepsal kartou zboží), cena z řádku plánování, ruční přepočet
  součtů (`UpdateTotalCost` + Total Price / Line Amount), `Source Code` = `Source Code Setup."Item Journal"`, `BindSubscription(Job Ledg. Entry
  No. IMEBS)` + `CreateJobLedgEntry`. `"Line Type" := Budget` nastavit vždy — `MatchUsageUnspecified` s prázdným Line Type dává Confirm.
- **Řádek plánování:** vyplněný → `Job Planning Line No.` na JJL → `MatchUsageSpecified`. Nevyplněný → **nový rozpočtový řádek založit sám
  před JLE** (`InitJobPlanningLine` + Validate Job No. / Job Task No. / Line No. (`GetNextLineNo` z EPEBS) / Line Type Budget → `Insert(true)`
  → Validate Planning Date / Type / No. / Variant / Location / Bin / UoM / Quantity (i záporné u storna) → `Modify(true)`, vzor
  `CreatePurchaseJobPlanningLines`), pak účtovat s jeho číslem. Důvod: standardní `MatchUsageUnspecified` by spotřebu napasoval na existující
  budget řádek stejného zboží (u Skip projektu rozpočtový řádek nákupu navázaný z billable řádku → dodávka by ho pak přespotřebovala a
  `HandleMatchUsageSpecifiedJobPlanningLine` zvedl množství); `OnAfterFindMatchingJobPlanningLine(…, var JobPlanningLineFound)` **vystřelí jen
  když standard nic nenašel** (`exit(true)` dřív), takže „vždy nový řádek" přes event nejde. Založený řádek je normální (ne System-Created) →
  jde vybrat na dalším řádku; `Unit Cost (LCY)` z deníku do něj **nevaliduj** (`Job Planning Line."Unit Cost (LCY)".OnValidate` u zboží se
  Standard costing = Error), cena / náklad zůstávají z karty (`Validate("No.")`). `CheckItemAvailable` řádku plánování se z kódu nespustí
  (`CurrFieldNo <> CalledByFieldNo`). Storno (Positive Adjmt.) bez kontroly na dříve zaúčtovanou spotřebu — místo pro ni je komentář
  v `PostProjectUsage` (porovnat s `Qty. Posted`).
- **Šarže = číslo projektu u sledovaného zboží (2026-10-29, tamtéž):** `Item Journal Line."Lot No."` (6501) `OnValidate` → `CheckItemTracking`:
  **bez `Item Journal Batch."Item Tracking on Lines"` tracking z polí řádku tiše smaže** (`ClearTracking` + `ClearDates`), s ním hodí
  `ItemTrackingExistsErr`, když řádek už má `Reservation Entry` (tracking zadaný přes 6510). Účtování dávky (`Item Jnl.-Post Batch.
  UpdateItemTracking` → `ItemJournalLine.CreateItemTrackingLines`) položky z polí řádku založí až v `PostLines`. Proto flag `Project
  Consumption IMEBS` při zapnutí sám dělá `Validate("Item Tracking on Lines", true)` a šarži plní `SetLotNoFromJob` (z `modify("Job No.")
  OnAfterValidate`, `OnAfterValidateEvent "Item No."` / `"Entry Type"`): guard `ItemJnlLineReserve.ReservEntryExist` (ruční tracking vyhrává),
  „vyžaduje šarži" = `Item Tracking Code."Lot Specific Tracking"` nebo per typ položky `"Lot Neg. Adjmt. Outb. Tracking"` (výdej) /
  `"Lot Pos. Adjmt. Inb. Tracking"` (příjem); změna projektu smaže šarži rovnou staré (`= xRec."Job No."`), ručně zadanou jinou nechá.
  `Lot No.` z ILE pak nese i JLE (`CopyTrackingFromItemLedgEntry`). Test: `LibraryItemTracking.CreateItemTrackingCode(Code, false, true)`
  + zboží `Validate("Item Tracking Code")`, naskladnění `CreateItemJournalLineInItemTemplate` + `CreateItemJournalLineItemTracking(…, LotNo,
  Qty)`; `LibraryItemTracking.CreateItemWithItemTrackingCode(Item, Code)` existuje (vrací No.).
- **Úkol projektu na řádku deníku zboží = jen nákupní (2026-10-30, tamtéž):** `Job Task."Line Type IMEBS"` (65130, enum `Job Planning Line
  Line Type`, Budget / Billable / Both, default Both — uživatelův návrh téže větve) omezuje typ plánovacích řádků úkolu; spotřeba z deníku
  zboží smí jen na úkol `Line Type IMEBS = Budget` („nákupní“; Both záměrně vyloučeno dle zadání). Lookup na page fieldu
  `TableRelation = "Job Task"."Job Task No." where("Job No." = field("Job No."), "Line Type IMEBS" = const(Budget))`, tvrdá kontrola
  `TestField("Line Type IMEBS", Budget)` v `ValidateJobTaskNo` i v kontrole před účtováním (`CheckJobTask`). Výběr řádku plánování zůstává
  bez filtru na typ úkolu (jen Budget / Both řádky s Usage Link). Testy musí úkol zakládat s `Validate("Line Type IMEBS", Budget)` —
  `LibraryJob.CreateJobTask` dá InitValue Both a validace řádku by spadla.
- ⚠️ `Job Journal Line.ValidateJobPlanningLineLink` (uvnitř Validate("Job Planning Line No.")): existuje-li v DB **jiný** řádek deníku projektů
  na tentýž řádek plánování, dá Confirm (bez GUI `Error('')`) — platí i pro `PostConsumption` z dodávky; nerozebráno, jen zjištěno.
- **Test appka:** `Item Jnl Usage Test IMEBS` (65139; test range rozšířen `from 65135`, hlavní appka má codeunity do 65135 — ID 65140–65149
  byly všechny obsazené). `LibraryInventory.CreateItemJournalLine(…, EntryType, …)` dělá `Validate("Entry Type")` → skupina ze setupu
  dorazí; `Validate("Job No.")` na Item Journal Line jde (tableextension trigger). General Posting Setup s inventory účty:
  `LibraryERM.FindGeneralPostingSetupInvtFull` → skupina pro výdej; pro příjem kopie setupu pod novou `CreateGenBusPostingGroup` (přímé
  přiřazení PK + `Insert(true)`), zboží `Validate("Gen. Prod. Posting Group", <z nalezeného setupu>)`. `LibrarySetupStorage.Save(Database::
  "Essence Projects Setup EPEBS")` po Get-or-Insert. `SetUpNewLine(LastLine)` z testu funguje na `Init` řádku s validovanou šablonou / listem
  (test defaultu Entry Type + skupiny). Chyby: `Assert.ExpectedTestFieldError(FieldCaption, '')` = „must have a value", s hodnotou =
  „must be equal to". Kompilace čistá, běh v CI.

### 5.x28 Kontrola množství z řádků plánování (Essence Projects Setup Never / Confirm / Always / Keep Original) — standard zvedá množství sám

- **Standard při přespotřebě navázaného řádku plánování zvedne `Quantity` SÁM, a to dvakrát nezávisle** (w1-28): `Job Link Usage.
  HandleMatchUsageSpecifiedJobPlanningLine` (`Validate(Quantity, Σ)` když Total > Quantity) a `Job Planning Line.Use` →
  `UpdateRemainingQuantityFromUse` (`Validate(Quantity, Q + Posted − Remaining)`, když Posted > Remaining). `Validate(Quantity)` z kódu
  (`CurrFieldNo = 0`) přitom **znovu tahá cenu i náklad**: `RetrieveCostPrice(0)` přeskočí filtr podle pole a u Item vrátí true při změně
  množství bez `BypassQtyValidation`, u Resource / G/L přes `IsQuantityChangedForPrice` (jen s extended price calc). To je ta „nežádoucí
  změna částek" z reklamace Soitronu (task 67360). Hooky: `OnHandleMatchUsageSpecifiedJobPlanningLineOnBeforeUpdateQuantity(var JPL, JJL,
  var UpdateQuantity)` vypne první zvednutí; **`Job Planning Line.OnBeforeUpdateRemainingQuantityFromUse(var JPL, xJPL, PostedQty, var
  IsHandled)` chytí VŠECHNY cesty usage** (standard, TSEBS override `OnBeforeMatchUsageSpecified`, IMEBS `PostConsumption`, deník
  projektů) — v `Use` je `Qty. Posted` už navýšené, Remaining ještě ne; po vlastním `Validate(Quantity)` dopočte `ControlUsageLink`
  Remaining = Quantity − Qty. Posted, proto `IsHandled := true`, jinak standard zvedne podruhé. Keep Original = `Validate("Remaining Qty.",
  Rem − Posted)` (záporné projde; `Qty. to Transfer to Journal` OnValidate hlídá jen Type Text). Ceny při zvednutí drží manuálně bindovaná
  codeunit s `IsHandled` v `OnBeforeFindPriceAndDiscount` + `OnBeforeUpdateUnitCost` (`Plan. Line Price Guard EPEBS`); v posting cestě
  před Validate `SetBypassQtyValidation(true)` jako standard (warehouse verify + CheckQuantityPosted).
- **Kontrola při vydání dokladu:** `Release Purchase Document.OnBeforeReleasePurchaseDoc(var PurchaseHeader, PreviewMode, var
  SkipCheckReleaseRestrictions, var IsHandled, SkipWhseRequestOperations)` / `Release Sales Document.OnBeforeReleaseSalesDoc(var SalesHeader,
  PreviewMode, var IsHandled, …)` — běží i z `Purch.-Post` / `Sales-Post` (účtování otevřeného dokladu ho vydá), v náhledu `PreviewMode`
  → bez Confirm. **Σ nákup = otevřené Purchase Line Order/Invoice (`Quantity (Base)` − `Qty. Invoiced (Base)`) − Credit Memo/Return Order
  + Purch. Inv. Line − Purch. Cr. Memo Line (vše přes standardní `Job Planning Line No.`), NE `Qty. Posted`** — u Skip projektu nákup usage
  neúčtuje a `Qty. Posted` je dodané množství (dalo by falešné překročení). Σ prodej = totéž přes `Job Contract Entry No.` (IMEBS); u Skip
  projektu navíc budget řádek z `Purch. Job Cont.Entry No.IMEBS`: posted usage (`Quantity (Base)` − `Remaining Qty. (Base)`) + nedodané
  otevřené objednávky kontraktu (`Quantity (Base)` − `Qty. Shipped (Base)`) — dodávka ho spotřebuje (5.x24).
- **`Sales Line.TestJobPlanningLine`** (OnValidate Quantity / No. / UoM / Variant …) → `Job Post-Line.TestSalesLine` = Error „cannot be
  changed" při `CurrFieldNo <> 0` → z UI se množství řádku s kontraktem změnit NEDÁ; z kódu (`Validate`, CurrFieldNo 0) projde. Prodejní
  přespotřeba billable řádku je tak prakticky jen z integrací; reálně hrozí budget řádek Skip projektu (dodávka 12 proti plánu 10).
- `ValuesAllowed = Never, Confirm, Always;` na enum poli tabulky funguje (alc 17, runtime 17) — pole Zboží bez „Keep Original". Default
  enum 0 = Never → po nasazení je kontrola nejpřísnější, dokud se setup nenastaví (rozhodnutí: strictní default, oznámeno uživateli).
- Testy bez dialogů: journal usage `LibraryJob.CreateJobJournalLineForPlan(JPL, UsageLineTypeBlank(), 1, JJL)` + `Validate("Job Planning
  Line No.")` + `Validate(Quantity, X)` + `Job Jnl.-Post Line.RunWithCheck(JJL)`; release `LibraryPurchase.ReleasePurchaseDocument` /
  `LibrarySales.ReleaseSalesDocument`; Confirm přes `[ConfirmHandler]` s odpovědí v globální proměnné; `LibrarySetupStorage.Save(Database::
  "Essence Projects Setup EPEBS")` po Get-or-Insert. (2026-10-27, prod-ep-projectBase-bc `features/salesQuotes` `Plan. Line Qty. Check
  EPEBS` + prod-ep-itemManagement-bc `features/misc` `Sales Plan. Qty. Check IMEBS`; kompilace čistá, běh v CI.)

### 5.x29 Typ řádku na úkolu projektu (`Job Task."Line Type IMEBS"`) — jaké řádky plánování úkol přijme; QB tasky Soitronu

- **IMEBS (prod-ep-itemManagement-bc `features/misc`, 2026-10-29):** tableextension 65135 `Job Task IMEBS`, pole `Line Type IMEBS`
  = standardní enum `Job Planning Line Line Type` (Budget / Billable / Both Budget and Billable), `InitValue = "Both Budget and
  Billable"` (nový ruční úkol nic neomezuje). Kontrola v `Job Planning Line IMEBS`: `OnBeforeInsert` + `OnBeforeModify` +
  `modify("Line Type") OnAfterValidate` → `CheckJobTaskLineTypeIMEBS()` (`IsTemporary` / prázdný úkol / neexistující úkol = exit;
  `JobTask.AllowsLineTypeIMEBS(LineType)` = Both nebo shoda). `OnValidate` pole na úkolu odmítne zúžení, když už má řádky jiného
  typu. Pole na `Job Task Lines` (1002), `Job Task Lines Subform` (1001), `Job Task Card` (1003) — všechny mají control
  `"Job Task Type"` pro `addafter`. **Automatický budget řádek z usage bez vazby (`MatchUsageUnspecified` → `Job Post-Line.
  InsertPlLineFromLedgEntry`) se na Billable úkolu NEblokuje, jen `Message`** (rozhodnutí uživatele 2026-10-29: účtování spotřeby
  nesmí spadnout): `Job Transfer Line.FromJobLedgEntryToPlanningLine` dělá `Validate("Line Type")` (ř. 534, w1-28) **dřív** než
  `"System-Created Entry" := true` (ř. 554) → kontrola ve `modify("Line Type") OnAfterValidate` jen při `CurrFieldNo =
  FieldNo("Line Type")` (ruční zadání), kód se kontroluje až v `OnBeforeInsert` (System-Created → `Message` při `GuiAllowed`) /
  `OnBeforeModify` (System-Created → tiše). Ruční `Validate("Line Type")` z kódu (QB, IMEBS) tak dostane chybu až při Insertu,
  text stejný. Report `Job Create Sales Order IMEBS` s *Create purchase lines* potřebuje úkol typu Budget / Both. Testy `Job Task
  Line Type Test IMEBS` (65179; usage bez řádku plánování: `LibraryJob.CreateJobJournalLineForType(UsageLineTypeSchedule(),
  ResourceType(), JobTask, JJL)` + `Job Jnl.-Post Line.RunWithCheck` + `[MessageHandler]`, projekt `Apply Usage Link` = true).
- **Existující řádky tabulky dostanou u nového enum pole hodnotu 0 = Budget, `InitValue` platí jen pro `Init()`** → upgrade
  codeunit 65137 `Job Task Line Type Upg. IMEBS` (`Access = Internal`, jinak ALCops **AC0007**; subscriber
  `OnGetPerCompanyUpgradeTags` uvnitř Upgrade codeunity alc 17 bere) volá per úkol `JobTask.UpdateLineTypeFromPlanningLinesIMEBS()`
  (table metoda, ať jde testovat bez `internalsVisibleTo`): jen úkoly s hodnotou Budget → podle řádků (jen Budget → Budget, jen
  Billable → Billable, mix / bez řádků → Both). Tag při čisté instalaci nastaví `Install IMEBS` (65160, `OnInstallAppPerCompany` →
  `UpgradeTag.SetAllUpgradeTags()`) — **bez vlastního Install codeunitu tag nikdo nenastaví** (System App `Upgrade Tag Install`
  jen při instalaci System App, `Company-Initialize` / `Company.OnAfterInsertEvent` jen u nové firmy) a při dalším upgradu by
  data fix proběhl znovu nad daty se správným schématem. IMEBS range 65130–65149 byla tímhle úkolem plná (hlavní appka
  65130–65137, testy 65138–65149 — test range sdílí namespace), uživatel přidal **65160–65179** (`idRanges` v app i test
  `app.json`); Install = 65160, test codeunit = 65179 (testy od konce range).
- **Soitron (cust-soitron-bc `features/replications`):** `QB Buffer Processing Mgt. SOI.EnsureJobTask(JobNo, TaskNo, Description,
  LineType)` dává nákladovému úkolu (`QB Cost Task Prefix`) Budget a výnosovému (`QB Revenue Task Prefix`) Billable; existující
  úkol se nemění. `QB Buffer Validation Mgt. SOI.ValidateJobTaskLineTypes` v kontrole bufferu: existující nákladový úkol musí
  povolit Budget a výnosový Billable (Aggregation řádek jen výnosový), jinak řádek `Error` s `TaskLineTypeLbl` — aby zpracování
  nespadlo v půlce na kontrole řádku plánování. `CostTaskNo` / `RevenueTaskNo` zveřejněny (volají `LoadSetup()`). Testy
  `QB Buffer Test SOI` (`ProcessBuffer_CreatedTasks_CarryLineTypeOfTheirSide`, `CheckBuffer_*TaskAllowsOnly*_SetsError`,
  `ProcessBuffer_ExistingTasksAllowingBothLineTypes_…`). Kompilace IMEBS i Soitron čistá proti IMEBS buildu ze zdrojáku; EP Base
  pro IMEBS `SalesPlanQtyCheck` (`Plan. Line Qty. Check EPEBS`) musel být taky zkompilovaný ze zdrojáku
  (`prod-ep-projectBase-bc features/salesQuotes`, verze v kopii `app.json` zvednutá na 28.0.34.0, aby test appka IMEBS s minimem
  28.0.24.0 prošla). Soitron závisí na IMEBS verzi s tímhle polem → IMEBS PR musí jít do feedu dřív než Soitron.
