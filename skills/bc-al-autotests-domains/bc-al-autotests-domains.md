# Business Central / AL – autotesty: doménové recepty (plánování, zálohy CZZ, banka CZB)

Vyčleněno z `bc-al-autotests.md` 2026-10-01 (překročil 1000 řádků). Obecná pravidla, handlery,
runner, Setup Storage a gotchas zůstávají tam; tady jsou **recepty pro konkrétní domény BC**:
sešit požadavků / Calculate Plan / Carry Out, nákupní zálohy CZZ s navázanou platbou a párování
bankovních plateb `Match Bank Payment CZB`. Pravidla jsou závazná stejně jako v hlavním souboru.

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

