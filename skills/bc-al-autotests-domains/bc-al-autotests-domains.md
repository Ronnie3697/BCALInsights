# Business Central / AL – autotesty: doménové recepty a pasti (plánování, CZZ, CZB, projekty, doklady, Job Queue, výroba)

Vyčleněno z `bc-al-autotests.md` ve dvou vlnách (zdroj pokaždé přesáhl 1000 řádků): 2026-10-01 recepty pro
sešit požadavků / Calculate Plan / Carry Out, nákupní zálohy CZZ s navázanou platbou a párování bankovních plateb
`Match Bank Payment CZB`; 2026-10-09 doménové gotchas — projekty (Job, Job Planning Line, deník projektů), prodejní
a nákupní doklady, Job Queue / task scheduler, výroba a konvence cust-soitron-bc. Obecná pravidla, handlery,
TestPage, `asserterror` a Setup Storage zůstávají v `bc-al-autotests.md`, kompilace a běh test appky
v `bc-al-autotests-infra.md`. Pravidla jsou závazná stejně jako v hlavním souboru.

## Plánování / sešit požadavků, zálohy CZZ, párování CZB

### Carry Out Action Message v testu bere CELÝ list sešitu — každý carry-out test si zakládá vlastní batch

`LibraryPlanning.CarryOutReqWksh(ReqLine, …)` → report 493 → `Req. Wksh.-Make Order.Code()`
filtruje jen `Worksheet Template Name` + `Journal Batch Name` (+ `Accept Action Message = true`)
podle předaného řádku — filtry na záznamu se sice kopírují (`ReqLine.Copy`), ale test je
typicky nemá. A **každý řádek sešitu založený přes `Validate("No.")` má `Accept Action
Message = true`** (`Requisition Line.CopyFromItem()` nastaví `Accept Action Message := true`
a `Action Message := New`). Kombinace s AutoCommit (data dřívějších testů téhož codeunitu
v DB zůstávají): carry-out ve **sdíleném** batchi (`FindFirst` na existující jméno listu)
zpracuje i řádky, které tam nechaly předchozí testy — vzniknou další nákupky, vyskočí jejich
confirmy (jiní dodavatelé/rámcovky → jiné cache klíče), případně to spadne na jejich datech.
Typický příznak: assert na počet confirmů (`Expected 2, Actual 6`) nebo „záhadné" faily
závislé na pořadí testů (první carry-out test v codeunitu projde, pozdější ne).

**Fix:** carry-out test si vždy založí vlastní batch
(`LibraryPlanning.CreateRequisitionWkshName(NewName, TemplateName)`) a řádky dává do něj;
sdílený list nechat jen testům, které carry-out nevolají. Zachyceno 2026-08-28,
cust-sonnentor-bc PR 9380 build 27993 (`ReqCarryOutRechecksRemainingQuantity`).

**Calculate Plan do vlastního batche:** `LibraryPlanning.CalcRequisitionPlanForReqWksh*` batch
neberou (jedou do defaultního listu z `SelectRequisitionWkshName`), takže Calculate Plan + Carry Out
test pusť report 699 přímo: `CalculatePlanReqWksh.SetTemplAndWorksheet(Template, Batch)` →
`InitializeRequest(StartDate, EndDate)` → `Item.SetRange("No.", …)` + `SetTableView(Item)` →
`UseRequestPage(false)` → `RunModal()`; řádky pak filtruj na Template + Batch + `"No."`. Report 699
procedury al-mcp nevidí (`Procedures: []` u reportů) — signatury ověří kompilace. (2026-09-14,
cust-alumistr-bc 65774, `Planning Transfer Tests ALU/PMALU` po code review.)

**Calculate Plan + Carry Out: poptávka na `WorkDate()` = „There is nothing to create."** `Inventory Profile
Offsetting.SetAcceptAction` nastaví `Accept Action Message := false` každému řádku, který má planning warning
(`PlanningTransparency.ReqLineWarningLevel(ReqLine) <> 0`); poptávka na WorkDate s nulovým lead time dá order
date před planning starting date (Emergency/Exception). `Req. Wksh.-Make Order` bere jen `Accept Action Message
= true` → report 493 skončí `Message('There is nothing to create.')` → „Unhandled UI: Message" (bez handleru).
Fix: poptávku datovat do budoucna (`SalesLine.Validate("Shipment Date", CalcDate('<+2W>', WorkDate()))`,
`ProductionOrder.SetUpdateEndDate()` + `Validate("Due Date", …)` **před** `RefreshProdOrder` — bez
`SetUpdateEndDate` Validate z kódu (`CurrFieldNo = 0`) Starting/Ending Date hlavičky nepřepočítá, `Create Prod.
Order Lines` je zkopíruje na řádek a komponenta zůstane na WorkDate → Emergency; build 28226) a před carry-out
`Assert.IsTrue(ReqLine."Accept Action Message", …)`, ať fail mluví. Zdroj: `Inventory/Tracking/
InventoryProfileOffsetting.Codeunit.al` (sparse clone `--filter=blob:none --sparse -b w1-28`, api.github.com
z Claude Code sandboxu nejede — `http 000`; raw.githubusercontent ano). (2026-09-14, cust-alumistr-bc build 28223.)

**`TestPage "Req. Worksheet"` na konkrétním listu: `ReqJnlManagement.TemplateSelectionFromBatch(RequisitionWkshName)`
po `ReqWorksheet.Trap()`, ne `Page.Run(Page::"Req. Worksheet", ReqLine)` s vyplněným Template + Batch.** Druhý způsob
funguje až od BC **28.4** (`OnOpenPage` → `GetCurrentJnlBatchName`). V 28.0–28.3 projde přes `WkshTemplateSelection` +
`OpenJnl` s prázdným `CurrentJnlBatchName` a `CheckTemplateName` otevře **první list šablony**. Řádky zadané přes TestPage
pak skončí v cizím listu: dotazy se položí a handler je spočítá, ale assert na řádky v testovacím listu najde 0. Lokální
kontejner 28.4 to nechytí, CI na 28.1 ano. `TemplateSelectionFromBatch` jde přes větev `OpenedFromBatch` (Template '' +
Batch na záznamu + filtr šablony ve filter group 2), kterou mají všechny verze 28.x, a stejně stránku otevírá
i přehled listů. Jiné sešity (`Planning Worksheet`…) neověřeny, ale mají stejný vzor `OnOpenPage`, tak si na to dej pozor. (2026-10-06, cust-sonnentor-bc
build 28705, `ReqWorksheetPageNewLinesAreAskedPerLine`; zdroj w1-28 `ReqWorksheet.Page.al` 28.0.46665 vs 28.4.53241.)

**Testy volající `SL Action Cond. Mgt. COEBS.ExecuteSalesLineActions` potřebují `[HandlerFunctions('…MessageHandler')]`**
— procedura končí nepodmíněným `Message('Sales Line actions have been executed …')`. Konfigurátorové testy to řeší
`MessageHandler`, v cust-alumistr-bc `SLActionsExecutedMessageHandler` (před přidáním nového handleru grepni
codeunit — duplicitní název = AL0518/AL0440). (2026-09-14, cust-alumistr-bc build 28223.)


### CZZ nákupní záloha v testu, na kterou se má navázat platba — musí mít řádek a být VYDANÁ (release), jinak To Pay = 0

`Purch. Adv. Letter Header CZZ`."To Pay" je FlowField `-sum("Purch. Adv. Letter Entry CZZ".Amount)` přes typy Initial Entry |
Payment | Close — a **Initial Entry vzniká až při release** (`Rel. Purch.Adv.Letter Doc. CZZ`), ne založením hlavičky. Test helper,
který založí jen hlavičku a nastaví `Status := "To Pay"` napřímo (vzor `EF Banking Library EBS.CreatePurchAdvLetterHeader`),
dá zálohu s **To Pay = 0**; stačí pro testy párování/merge, ale `PurchAdvLetterManagementCZZ.PostAdvancePayment(...)` /
`Purch. Adv. Letter-Post CZZ.PostAdvancePayment` spadne na `Amount > "To Pay"` („ExceededAmountToPayErr"). Funkční recept
(`CreateReleasedPurchAdvLetter` tamtéž): hlavička (`Validate("Advance Letter Code")` → `Insert(true)` → `Validate("Pay-to Vendor No.")`,
datumy, `"Vendor Adv. Letter No."` — z něj release odvodí VS) **bez ručního Status**, řádek `Validate("VAT Prod. Posting Group",
<VAT Prod z LibraryERM.FindVATPostingSetup(Normal VAT)>)` (stejný setup, jaký `Library - Purchase.CreateVendor` dá dodavateli →
kombinace Bus/Prod existuje; řádek vyžaduje Status New) + `Validate("Amount Including VAT", X)`, pak
`Codeunit.Run(Codeunit::"Rel. Purch.Adv.Letter Doc. CZZ", Header)`. Šablona zálohy musí mít **"Advance Letter G/L Account"**
(`LibraryERM.CreateGLAccountNo()`) — účtování platby zálohy jde přes `"Use Advance G/L Account CZZ"` na tento účet místo účtu
závazků. `"Automatic Post VAT Document"` nechat false, jinak se při navázání účtuje i DPH doklad (potřebuje účty na VAT Posting
Setup, VAT Date…). **Transaction No. navázané zálohy** ber přes `PurchAdvLetterEntryCZZ."Vendor Ledger Entry No."` →
`Vendor Ledger Entry."Transaction No."`; položka zálohy typu Payment má `"Det. Vendor Ledger Entry No." = 0`
(`InitVendorLedgerEntry` plní jen VLE No., detailní položku plní až usage/VAT položky) → `DetailedVendorLedgEntry.Get(0)` spadne.
(2026-09-22, prod-ef-bank-bc `TestMergedPaymentFullFlow_MatchingAndPosting`, kontrola proti cz-28 source.)


### Test párování `Match Bank Payment CZB` z kódu

`Codeunit.Run(Codeunit::"Match Bank Payment CZB", GenJournalLine)` jako statement: řádek deníku potřebuje `"Search Rule Code CZB"`
(nebo sumární řádek banky), `"Bal. Account Type/No."` = banka (jinak hledá sumární řádek), nenulové `Amount (LCY)` a banku bez
`"Disable Automatic Pmt Matching"`. **Variabilní symbol čte párování přes `GenJournalLine.GetVariableSymbolCZB()`**, které vrací
`"Variable Symbol CZL"` jen při `"Variable S. to Variable S. CZB" = true` (alternativně z Ext. Doc. No. / Description podle
dalších dvou příznaků); v provozu je kopíruje `CreateJournal` z bankovního účtu, ručně založený řádek v testu má příznak false →
VS „prázdný", pravidlo s VS nic nenajde a párování tiše skončí bez chyby (`"Search Rule Line No. CZB" = 0`). V helperu nastav
`GenJournalLine."Variable S. to Variable S. CZB" := true`. Vlastní pravidlo: `LibraryBankDocCZBEBS.CreateSearchRule`
(+ `CreateDefaultLines`) a pak `DeleteAll` řádků + `Insert(false)` jediného řádku s testovaným `Search Scope`, aby výsledek
neovlivnily standardní řádky. Výsledek čti po `Get` řádku (`"Search Rule Line No. CZB"` ≠ 0 = spárováno; při nespárování se řádek
NEmodifikuje). Směr částky: odchozí platba dodavateli z výpisu má na řádku deníku **kladný** `Amount` (Bal. Account = banka;
`MatchBankPaymentCZB` filtruje `Positive := Amount < 0` a toleranci z `-Amount (LCY)`).
- **`Issue Payment Order CZB` volá `Message`:** u příkazu s řádkem dodavatele jde přes `PaymentOrderHeaderCZB.ImportUnreliablePayerStatus()`
  (kontrola nespolehlivých plátců „vypršela" = nový příkaz vždy), import ze služby v test DB selže bez error textu →
  `Message('Unreliable Payer Status was not loaded.')` → test bez `[HandlerFunctions('MessageHandler')]` padá „Unhandled UI: Message".
  Confirm větve (neveřejný/cizí účet, nespolehlivý plátce) hrozí jen když `PaymentOrderLine.IsUnreliablePayerCheckPossible()`
  (CZ dodavatel s DIČ), což dodavatelé z `Library - Purchase` nesplňují. Test, který příkaz vydává, MessageHandler mít musí;
  test, který ho nevydává, ho mít nesmí (nevyužitý handler = fail). Párování ani `Vend. Entry-Edit` UI nevolají.
- **Defaultní řádky `Search Rule CZB.CreateDefaultLines` se liší podle verze BC** (CI 28.0.46665 má mezi Balance/Both řádky
  i jiné řádky, cz-28 HEAD = 28.3+ má 6× Balance/Both) — test na pořadí/vkládání řádků nesmí předpokládat konkrétní sadu;
  projdi všechny standardní řádky, očekávání odvozuj z předchozího řádku **jakéhokoli typu** a ověř i „žádný vložený řádek
  před ne-Balance řádkem" (spadlo 2026-09-22: Expected 20000, Actual 25000). Obecně: zdroják z GitHubu StefanMaron je HEAD
  dané major řady, CI kontejner může jet starší minor — chování defaultních dat si ověř až během. Konkrétní build najdeš
  přes commits API (`commits?sha=cz-28&path=<soubor>` → message `cz-28.0.46665.48549` → raw URL se SHA commitu).
- **Test symboly 28.3 z MSSymbols:** stejný set a package ID jako u 28.4 (viz výše), verze `28.3.52162.52273`, proti Base App
  `28.3.52162.52754` alc 17.0 čistě (2026-09-22, prod-ef-bank-bc/Test).
(2026-09-22, prod-ef-bank-bc `BankEBSTestsEBS`.)

## Projekty (Job, Job Planning Line, deník projektů)

- **`Job.Validate(Status, …)` má v base dialogy na obě strany (w1-28 `Job.Table.al`):** přechod **na Completed** →
  `Validate(Complete, true)` → `ChangeJobCompletionStatus` → `Message(EndingDateChangedMsg)` (→ `[MessageHandler]`);
  přechod **z Completed** → `ConfirmManagement.GetResponseOrDefault(StatusChangeQst, true)` („This will delete any unposted
  WIP entries…") a po něm `Message(ReverseCompletionEntriesMsg)` (→ `[ConfirmHandler]` Reply true **+** `[MessageHandler]`).
  Bez ConfirmHandleru reopen spadne na „Unhandled UI: Confirm", s handlerem `Reply := false` se stav tiše vrátí na Completed.
  Vlastní kontrola s `[ErrorBehavior(ErrorBehavior::Collect)]` + `Show Errors SOI` (Page.Run `Error Messages` + `Error('')`)
  se testuje přes `asserterror` + `[PageHandler]` na `TestPage "Error Messages"` (`First()` + `.Description.Value()` do globální
  proměnné, pak `Close()`), `Commit()` po GIVEN; `ExpectedError` nepoužívat (hláška je prázdná). (2026-10-01, cust-soitron-bc
  `Job Cancel Test SOI`, 66504 — kompilace čistá, CI běh po PR.)
- **`LibraryJob.UseJobPlanningLine(JPL, UsageLineType, Fraction, var JobJnlLine)` řádek deníku projektu rovnou ÚČTUJE**
  (`CreateJobJournalLineForPlan` + `PostJobJournal` = codeunit `Job Jnl.-Post` s Confirm „Do you want to post the journal
  lines?") → bez `[ConfirmHandler]` „Unhandled UI: Confirm", a navazující `Validate`/`Modify` na vráceném řádku sáhne na už
  smazaný řádek. Když potřebuješ řádek před účtováním upravit nebo si přečíst `Total Cost (LCY)`, postav ho sám:
  `LibraryJob.GetJobJournalTemplate` + `CreateJobJournalBatch` + `Job Transfer Line.FromPlanningLineToJnlLine(JPL, WorkDate(),
  Template, Batch, JobJnlLine)` + `Get` (vloží s `Job Planning Line No.` jen při usage linku → `Validate` explicitně, doplň
  `Document No.`) a zaúčtuj `Job Jnl.-Post Line.RunWithCheck(JobJnlLine)` — bez dialogu, přesně to, co dávka dělá per řádek.
  (2026-10-07, cust-soitron-bc `JPL Doc. Amounts Test SOI`, běh v lokálním kontejneru.)
- **`Job.Validate("Sell-to Customer No." | "Bill-to Customer No.")` na existujícím projektu = Confirm „Do you want to change…?"
  (default No).** `SellToCustomerNoUpdated` / `BillToCustomerNoUpdated` se ptají, jakmile `xRec` zákazníka má a `GuiAllowed()`
  (v test runneru true) — bez handleru „Unhandled UI: Confirm", s handlerem `Reply := false` se změna tiše vrátí a navazující
  logika (vlastní dotaz, propagace) se vůbec nespustí. Sell-to navíc kaskáduje do Bill-to = druhý dotaz. Řešení v testu:
  `Job.SetHideValidationDialog(true)` před Validate (skryje jen standardní dotazy, vlastní `ConfirmManagement` dotaz appky
  zůstane testovatelný), nebo zákazníka dát rovnou `LibraryJob.CreateJob(Job, CustomerNo)` místo pozdějšího přepisu
  (`LibraryJob.CreateJob(Job)` si zákazníka založí sám a nastaví Sell-to i Bill-to). (2026-10-01, cust-soitron-bc
  `Job Segment Test SOI` / `QB Buffer Test SOI`; zdroj Base App w1-28 `Job.Table.al`.)
- **Účtování nákupního dokladu s řádkem projektu bez plánovací řádky a s prázdným `Job Line Type` = Confirm „There are
  purchase lines without a Job Planning Line No. and with a Job Line Type of blank. Do you want to continue posting?"**
  (`Purch.-Post`, ještě před `OnBeforePostPurchaseDoc`). Test, který dává `Purchase Line."Job No."` jen přiřazením, nastaví
  i `"Job Line Type" := Budget` (nebo přidá ConfirmHandler), jinak „Unhandled UI: Confirm" dřív, než se dostane ke slovu
  vlastní kontrola. Prodejní řádky tenhle dotaz nemají. (2026-10-01, cust-soitron-bc build 28579, `Job Close Test SOI`.)
- **Default Dimension projektu, který už má úkoly (Job Task) → Confirm „You have changed a dimension. Do you want to update
  the lines?"** — `DimensionManagement.UpdateJobTaskDim` (volané z `DefaultDimOnInsert/OnModify/OnDelete`) se ptá přes
  `Confirm Management`, jakmile `Job Task` projektu není prázdný. Test, který `LibraryDimension.CreateDefaultDimension` /
  `Validate("Dimension Value Code") + Modify(true)` / `Delete(true)` na projektu s úkoly dělá, potřebuje `[HandlerFunctions('ConfirmHandler')]`;
  bez úkolů (default dim založená před `CreateJobTask`) dialog nevyskočí a registrovaný handler by naopak shodil test
  jako nevyužitý. (2026-10-01, cust-soitron-bc build 28562, `Job Type Posting Test SOI`.)
- **Copy Document maže vazbu na projekt, Get Shipment Lines ji drží.** `Copy Document Mgt.CopySalesDocLine` → `UpdateSalesLine`
  → `SetDefaultValuesToSalesLine` → `InitJobFieldsForSalesLine` nuluje `Job No.`, `Job Task No.` i `Job Contract Entry No.`
  (bez i s Recalculate Lines; kopíruje je jen `CopyJobData` = opravné dobropisy). `Sales Shipment Line.InsertInvLineFromShptLine`
  naopak dělá `SalesLine := SalesOrderLine` → řádek faktury z Get Shipment Lines nese `Job Contract Entry No.` i vlastní pole
  řádku objednávky. Test logiky „dohledej projekt z řádku" musí u Copy Document dát projekt do hlavičky (`Job No. EPEBS`),
  jinak se fallback přes řádek nikdy nespustí; u Get Shipment Lines se naopak testuje cesta přes contract entry.
  (2026-10-01, cust-soitron-bc `Sales Aggregation Test SOI`, zdroj Base App w1-28 `CopyDocumentMgt.Codeunit.al` 1818/7761.)

## Prodejní a nákupní doklady

- **Částečné zaúčtování (jen příjem / dodávka) doklad VYDÁ** — `Purch.-Post` / `Sales-Post` volají release, takže
  následná změna řádku (`TestPage.Quantity.SetValue`, `Validate`) spadne na `TestStatusOpen` („Status must be equal to
  'Open'") dřív, než se dostane ke slovu testovaná logika v `OnAfterValidateEvent`. Po `PostPurchaseDocument(…, true, false)`
  / `PostSalesDocument(…, true, false)` dej `Get` hlavičky + `LibraryPurchase.ReopenPurchaseDocument` /
  `LibrarySales.ReopenSalesDocument` (tak to dělá i uživatel). (2026-10-06, cust-sonnentor-bc 64046,
  `Purch/SalesPartly…LinkedLineQtyBeyondRemainingFails`, zelené v kontejneru.)
- **Negativní test `TestStatusOpen` po `ReleaseSalesDocument` — validuj na NOVÉ instanci recordu.** `Sales Line`
  si hlavičku cachuje v globální proměnné instance (`GetSalesHeader` znovu nečte, když sedí Document Type + No.);
  `SalesLine` proměnná, kterou prošel `LibrarySales.CreateSalesLine`, tak drží hlavičku se Status Open i po
  release a `asserterror SalesLine.Validate(pole)` nespadne. Fix: `ReleasedSalesLine.Get(SalesLine."Document Type",
  "Document No.", "Line No.")` a Validate na ní; chybu ověř `Assert.ExpectedTestFieldError(SalesHeader.FieldCaption(Status),
  Format(SalesHeader.Status::Open))` (MS Assert 130000, BC 24+). Undo dodávky v testu bez dialogu: `SalesShipmentLine.SetRecFilter()`
  + `UndoSalesShipmentLine.SetHideDialog(true)` + `.Run(SalesShipmentLine)` (bez `SetRecFilter` projde `Code()` celou
  tabulku); `LibrarySales.UndoSalesShipmentLine` existuje, ale tělo (dialog) z MCP nevidíš.
- **Undo dodávky označí `Correction = true` i na PŮVODNÍM řádku dodávky** (`Undo Sales Shipment Line.Code`: původní řádek
  dostane `Quantity Invoiced := Quantity`, `Correction := true`, `Modify`; teprve pak `InsertNewShipmentLine` vloží korekční
  řádek se záporným množstvím, taky `Correction = true`). `SetRange(Correction, true) + FindFirst` tedy vrátí původní řádek
  (+4) → `Expected -4, Actual 4`. Korekční řádek filtruj `SetFilter(Quantity, '<0')` (nebo `Line No.` > původní).
  (2026-09-15, cust-alumistr-bc build 28247, `UndoShipmentNegatesSKEndCustomerTotalOnCorrectionLine`.)
- **Zákaznická appka, která při Quote → Order dá objednávce ČÍSLO NABÍDKY (`OnBeforeInsertSalesOrderHeader`:
  `SalesOrderHeader."No." := SalesQuoteHeader."No."`), shodí `LibrarySales.QuoteMakeOrder` na *„The record in table Sales
  Header already exists. Document Type='Order', No.='1001'"*.** V CI firmě (CRONUS CZ) začínají řady nabídek i objednávek
  na 1001 a objednávku 1001 už založil dřívější test téhož codeunitu (AutoCommit). Lokálně ani jednotlivě to nespadne.
  Nabídku pro převod zakládej s unikátním číslem mimo řadu (`Init` + `"No." := <GUID kód>` + `Insert(true)`, v Zlomku
  `Library - Zlomek ZLK.CreateSalesHeader`). (2026-09-29, cust-zlomek-bc master build 28530,
  `Sales Comment Tests ZLK.MakingOrderFromQuoteCarriesComments`.)
- **`LibrarySales.CreateCustomer` si založí firemní kontakt + Contact Business Relation sám** (Marketing Setup v CRONUS má
  `Bus. Rel. Code for Customers`). Když v testu založíš k tomu zákazníkovi DALŠÍ kontakt přes `LibraryMarketing.CreateCompanyContact`
  + `CreateBusinessRelationBetweenContactAndCustomer` a použiješ ho jako Sell-to Contact dokladu, `Sales Header` OnInsert →
  `Bill-to Contact No.` OnValidate → `CheckContactRelatedToCustomerCompany` spadne *„Contact X is related to a different company
  than customer Y"* (`ContBusRel.FindByRelation(Customer, CustNo)` najde první relaci = auto-kontakt). Správně vezmi existující
  kontakt: `ContactBusinessRelation.FindByRelation(ContactBusinessRelation."Link to Table"::Customer, Customer."No.")` →
  `Contact.Get(ContactBusinessRelation."Contact No.")` (fallback na CreateCompanyContact jen když relace není).
  (2026-09-15, cust-alumistr-bc build 28247, `QuoteFromOpportunityIsBilledToOpportunityBillToCustomer`.)

### Doklad jen se záporným řádkem = „Celková částka faktury musí být 0 nebo větší" PŘED vlastní kontrolou

Test, který účtuje doklad obsahující **jen záporný řádek** (uplatnění poukazu, sleva, oprava),
spadne na standardní kontrole `The total amount for the invoice must be 0 or greater.` —
a to **dřív, než se dostane ke slovu vlastní kontrola** v `OnBeforeIsApprovedForPosting`
nebo jinde v posting flow. Negativní test pak selže na „Expected: <moje hláška>. Actual:
The total amount for the invoice must be 0 or greater." a vypadá to, jako že vlastní kontrola
nefunguje, přitom se jen nespustila.

**Fix:** dej do dokladu **kladný řádek běžného zboží** (`LibrarySales.CreateSalesLineWithUnitPrice(SalesLine,
SalesHeader, ItemNo, 1200, 1)`), ať je celková částka ≥ 0 — a to i u dobropisu, který vydává
nový poukaz. Reálný doklad tak taky vypadá (zákazník něco kupuje/vrací a poukazem platí část).
Prodejní (kladná) strana téhož scénáře projde bez zboží, takže „prodej funguje, uplatnění ne"
je typický příznak právě tohohle. (2026-09-15, cust-sonnentor-bc build 28270, `RedemptionWithWrongUnitPrice-
CannotBePosted` + `FullVoucherCycleWithReplacementKeepsValueAndExpiration`.)

## Job Queue a task scheduler v testech

- **Účtování / plánování v testu zakládá skutečný scheduled task** (`Job Queue Entry.ScheduleJobQueueEntryForLater`,
  `Codeunit.Run("Job Queue - Enqueue")`) → před ním `BindSubscription(LibraryJobQueue)` (`Library - Job Queue`, Manual) —
  jeho subscriber `OnBeforeJobQueueScheduleTask` nastaví `DoNotScheduleTask`, entry zůstane On Hold a dá se assertovat.
  Setup záznamy sdílené napříč testy codeunitu (např. `Shpfy Shop` s vlastním enable flagem) **vypni v `Initialize()`
  před `if IsInitialized then exit`** (`ModifyAll(Flag, false, false)`), jinak „počet řádků per povolený shop" počítá
  i shopy z předchozích testů (AutoCommit). (2026-09-22, cust-sonnentor-bc `Test Voucher Discounts SON`.)
- **`TaskScheduler.CanCreateTask()` je v Essence build kontejneru `false`** (`CreateBCContainer2.ps1` nevolá
  `New-BcContainer -enableTaskScheduler`; BcContainerHelper pak `EnableTaskScheduler` do konfigurace vůbec nezapíše).
  Vlastní pre-check před `ScheduleJobQueueEntryForLater` („zrcadlo `CheckRequiredPermissions`", 5.x14 v bc-al-objects)
  tak v CI **tiše přeskočí založení entry** a `Assert.RecordCount(JobQueueEntry, 1)` spadne s `Actual: 0`, zatímco přímé
  `Codeunit.Run("Job Queue - Enqueue")` s bindnutou `Library - Job Queue` projde (base `CanCreateTask` nekontroluje, jen
  publikuje `OnBeforeJobQueueScheduleTask`). Řešení: pre-check obal do `local procedure CanCreateTask()` s
  `[IntegrationEvent] OnBeforeCheckCanCreateTask(var CanCreateTask; var IsHandled)`; test codeunit dostane
  `EventSubscriberInstance = Manual`, subscriber nastaví `true` + `IsHandled` a test ho bindne přes proměnnou vlastního
  typu (`TestX: Codeunit "Test X"; BindSubscription(TestX)`) hned za `BindSubscription(LibraryJobQueue)`. Na dev
  prostředí se zapnutým task schedulerem to lokálně neuvidíš. (2026-09-22, cust-sonnentor-bc build 28396, 2 testy.)

## Výroba (kusovník, Low-Level Code, Library - Manufacturing)

- **Komponenta upravená po založení výrobku s kusovníkem → „The changes to the Item record cannot be saved because some
  information on the page is not up-to-date"** (Identification `No.` = komponenta). Při `Manufacturing Setup."Dynamic Low-Level
  Code" = true` (CI kontejner ho má) spustí `Item.Validate("Production BOM No.")` výrobku codeunit `Calculate Low-Level Code`
  a ten přes `SetRecursiveLevelsOnBOM` → `SetRecursiveLevelsOnItem` udělá `CompItem.Modify()` (Low-Level Code) na **každé komponentě**
  certifikovaného kusovníku. Proměnná komponenty z GIVEN (`CreateItem` + `Modify`) je pak zastaralá a pozdější `Modify` v testu spadne;
  lokálně s vypnutým Dynamic LLC projde. Před úpravou komponenty ji načti znovu (`ComponentItem.Get(ComponentItem."No.")`). Výrobek sám
  problém nemá (codeunit dělá `Rec.Copy(Item2)`). (2026-09-29, cust-alumistr-bc PR 9604 build 28526,
  `CreditMemoCopiedFromPostedInvoiceKeepsInvoicedPrice`; zdroj Base App 28.5 `CalculateLowLevelCode.Codeunit.al`, `MfgItem.TableExt.al`.)

### Cyklický Production BOM v testech

`ProdBOMHeader.Validate(Status, ProdBOMHeader.Status::Certified)` má vestavěnou cycle detection a vrátí error. Pro test cyklického BOM:

1. Vyrob BOM přímými `Insert(false)` (header + lines obě tabulky)
2. Status nastav přímo `ProdBOMHeader.Status := ProdBOMHeader.Status::Certified; Modify(false);`

Tím obejdeš certify routine a můžeš testovat `VisitedItems` cycle guard v aplikační logice.

### `Library - Manufacturing` není vždycky dostupné

Pokud chybí v `Tests-TestLibraries` build pro tvůj region (u některých CZ buildů chybělo; `prod-ess-configurator-bc/test` ho normálně používá — ověř v symbolech / na MSSymbols feedu, viz 7.12 v `bc-al-build.md`), Production BOM Header / Routing helper si musíš napsat sám:

```al
procedure CreateCertifiedProdBOMHeaderForItem(var ProdBOMHeader: Record "Production BOM Header"; ParentItem: Record Item)
begin
    ProdBOMHeader.Init();
    ProdBOMHeader."No." := CopyStr(LibraryUtility.GenerateRandomCode(...), 1, MaxStrLen(...));
    ProdBOMHeader."Unit of Measure Code" := ParentItem."Base Unit of Measure";
    ProdBOMHeader.Insert(true);
end;
```

## Konvence cust-soitron-bc

- **Odmítnutý Confirm v table triggeru: cust-soitron-bc má konvenci explicitní `Error(<Label>)` místo tichého `Error('')`**
  (komentář v `Replication Mgt. SOI`: tichý error TestPage i `asserterror` spolknou a odmítnutá změna vypadá jako provedená).
  Test pak jde přímočaře: `asserterror Page.Field.SetValue(...)` + `Assert.ExpectedError('... cancelled.')`, `Commit()` po GIVEN,
  `Page.Close()` až po assertu. `Rec.Delete(true)` z kódu má v runneru `GuiAllowed() = true` → Confirm v `OnBeforeDelete` vyskočí
  i bez stránky, test potřebuje `[ConfirmHandler]` (Reply z globální proměnné, otázku si ulož na assert). (2026-10-02)
- **cust-soitron-bc: `LibraryPurchase.CreateVendor` / `CreateVendorNo` padá na „Vendors can only be created from a customer using
  the Create Vendor action."** — `Cust. Vendor Mgt. SOI` (SingleInstance) blokuje přímý `Vendor.Insert` při `GuiAllowed()` (v runneru
  true); `Allow Manual Cust./Vend. SOI` v setupu na to nemá vliv (řídí jen zákazníky). Dodavatele v testu zakládej přes one-shot
  bypass: `CustVendorMgt.SetAllowVendorInsert(true); LibraryPurchase.CreateVendor(Vendor); SetAllowVendorInsert(false)` (vzor
  `BusinessUnitAssignTest`). Lokální kompilace to nechytí, až CI. (2026-10-05, build 28636, `QB Buffer Test SOI`.)
