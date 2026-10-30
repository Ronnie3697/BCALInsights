# BC/AL poznámky — Hromadné objednávky, sešit požadavků a přepočet ceny

> Vyčleněno z `bc-al-objects.md` 2026-10-19 (sekce 5.x5, 5.x9, 5.x21), když soubor přesáhl 1000 řádků.
> Načítej, když řešíš: hromadné objednávky HNO/HPO (vazba řádků NO/PO/sešitu, převzetí ceny, Recreate lines, změny z hlavičky),
> Requisition Line (`OnAfterGetDirectCost`, Req. Wksh.-Make Order / Carry Out, Calculate Plan bez dotazů), poptávka → Requisition Line
> → Purchase Line (přenos vlastních polí) a přepočet ceny z Množství bez ceníku (`IsPriceUpdateNeeded`, ruční sleva).
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **5.x5** Requisition Line — `OnAfterGetDirectCost`, Req. Wksh.-Make Order, Carry Out, Calculate Plan bez dotazů
- **5.x9** Poptávka → Requisition Line → Purchase Line (kde plánování tvoří řádek, přenos vlastních polí)
- **5.x21** Přepočet ceny bez ceníku (`IsPriceUpdateNeeded`, ruční sleva) a hromadné objednávky HNO/HPO (vazba řádků, Recreate lines, změny z hlavičky)

### 5.x5 Requisition Line — `OnAfterGetDirectCost` jako hook „po přecenění" + past v Req. Wksh.-Make Order (BC 28.3)

- `Requisition Line.GetDirectCost(CalledByFieldNo)` volá standard z OnValidate **8 polí**: `No.`
  (přes `CopyFromItem`), `Vendor No.` (jen když Type = Item, `No.` <> '' a není prod. order),
  `Variant Code`, `Location Code`, `Unit of Measure Code`, `Order Date`, `Currency Code`, `Quantity`.
  Uvnitř `PriceCalculation.ApplyDiscount + ApplyPrice` a `Rec := Line` (přepíše `Direct Unit Cost`
  i `Line Discount %` z ceníků) — jen pro `Replenishment System = Purchase` a ne subcontracting;
  event **`OnAfterGetDirectCost(var Rec, CalledByFieldNo)` se ale volá VŽDY na konci** (i mimo
  Purchase → filtruj sám). `OnBeforeGetDirectCost` s `IsHandled` → OnAfter se nevolá.
- `Quantity (Base)` je při `Validate(Quantity)` spočtené **před** `GetDirectCost` → v subscriberu už sedí.
- `Direct Unit Cost` (10) ani `Line Discount %` (7002) **nemají OnValidate** → `Validate` z subscriberu
  nezpůsobí rekurzi. Base app nemá na Requisition Line obdobu ochrany `BlanketOrderIsRelated`
  z Purchase Line → vlastní cenu musíš po každém `GetDirectCost` obnovit sám.
- ⚠️ `Req. Wksh.-Make Order`: `OnAfterInsertPurchOrderLine(var PurchOrderLine, var NextLineNo,
  var RequisitionLine, var PurchOrderHeader)` běží hned po `PurchOrderLine.Insert()` (bez následného
  Modify — vlastní změny ulož sám), ale **řádek sešitu se maže až ve `FinalizeOrderHeader`** po
  vložení všech řádků téže objednávky (stejný dodavatel/ship-to/měna/purchasing code). Logika, která
  z řádků sešitu počítá „rezervace" (čerpání rámcovky apod.), tak během carry-out vidí souběžně řádek
  sešitu i z něj vzniklý řádek NO → **dvojí započtení** pro další řádky téhož běhu. Fix: po přenosu
  rezervaci na řádku sešitu zrušit (`Modify(false)` na var parametru), nebo vést seznam už
  převedených RecordId.
- `Carry Out Action Msg. - Req.` filtruje jen Worksheet Template Name + Journal Batch Name (celý list,
  `Accept Action Message = true`) → v testech se sdíleným listem se provedou i cizí řádky s Accept.
- Plánování (`Inventory Profile Offsetting`) maže řádky listu po jednom `Delete(true)` →
  `OnAfterDeleteEvent` chodí per řádek (pattern „list prázdný → reset session stavu" funguje).

(2026-08-28, cust-sonnentor-bc PBI 64046 — review větve BlanketOrders_64046.)

- **„Během Calculate Plan se neptej" = manuální bind ve `reportextension` na report 699, ne SingleInstance příznak.**
  Plánuje se v `Item.OnAfterGetRecord` reportu (po `OnPreReport`, `Commit` per zboží); řádek vzniká v
  `MaintainPlanningLine` a `Validate(Quantity)` (→ `GetDirectCost`) běží ještě **před `Insert`** — `Line No.` už je
  přidělené, `"Planning Line Origin" := Planning` taky. Vzor: codeunit s `EventSubscriberInstance = Manual` odpovídá na
  `[InternalEvent]` publishera („auto-odpověď aktivní?"), reportextension drží jeho instanci v globální proměnné, `OnPreReport`
  → `BindSubscription`, `OnPostReport` → `UnbindSubscription`. Příznak v SingleInstance by po chybě plánu zůstal nastavený
  na celou relaci. ⚠️ Ani bind není neprůstřelný: **`Req. Worksheet` drží report v `protected var CalculatePlan` a `Clear`
  dělá až po úspěšném `RunModal`** → po chybě instance i vazba přežijí, dokud je stránka otevřená, a vazba platí **pro celou
  relaci** (jiné stránky taky). Proto: auto-odpověď konzultovat jen na cestách, které mají mlčet (řádek sešitu), a v
  `OnPreReport` nejdřív `if UnbindSubscription(X) then;` (opakovaný bind téže instance spadne). Test: report 699 přes
  `SetTemplAndWorksheet` + `InitializeRequest` + `SetTableView` + `UseRequestPage(false)` + `RunModal` **bez
  ConfirmHandleru** (dotaz test shodí), druhý test ruční změna po plánu s handlerem (vazba skončila). Ověřeno v lokálním
  kontejneru 28.4 (7.23 v `bc-al-build.md`). (2026-10-05, cust-sonnentor-bc PBI 64046, komentář PFIL 24. 9.)

### 5.x9 Poptávka → Requisition Line → Purchase Line: kde plánování tvoří řádek a jak přenést vlastní pole (BC 28.4)

Vlastní pole z poptávky (Sales Line / Prod. Order Component) se na řádek sešitu požadavků samy nedostanou — každá
cesta vzniku řádku má jiný hook. Ověřeno ve zdrojích Base App 28.4 (cust-alumistr-bc 65774, 2026-09-12):

| Cesta | Kde řádek vzniká | Hook | Vazba |
|---|---|---|---|
| Order Planning (page 5522, Make Orders / Copy to Req. Wksh) | `Requisition Line.TransferFromUnplannedDemand` | table event `OnAfterTransferFromUnplannedDemand(var ReqLine; UnplannedDemand)` — Sales: `Demand SubType` = doc type, `Demand Order No.`/`Demand Line No.`; Production: `Demand SubType` = status, `Demand Order No.` = VZ, `Demand Line No.` = řádek VZ, `Demand Ref. No.` = komponenta | 1:1 |
| Get Sales Orders (report 698, drop shipment / special order) | `InsertReqWkshLine` | `OnBeforeInsertReqWkshLine(var ReqLine; SalesLine; SpecOrder)` | 1:1 |
| Calculate Plan (report 699 / 99001017) | `Inventory Profile Offsetting.MaintainPlanningLine` | `OnMaintainPlanningLineOnBeforeReqLineInsert(var ReqLine; var SupplyInvtProfile; …; var DemandInvtProfile; …)` — poptávka v `DemandInvtProfile."Source Type/Order Status/ID/Ref. No./Prod. Order Line"` (Sales Line: Ref. No. = Line No.; komponenta 5407: Prod. Order Line + Ref. No.) | jen když `SupplyInvtProfile.Binding = "Order-to-Order"` (Reordering Policy Order nebo MTO planning level, `PrepareOrderToOrderLink` + `TransferAttributes`); Lot-for-Lot / ROP agregují víc poptávek → nekopírovat |
| Carry Out (sešit → NO) | `Req. Wksh.-Make Order.InsertPurchOrderLine` | `OnInsertPurchOrderLineOnAfterTransferFromReqLineToPurchLine(var PurchOrderLine; RequisitionLine)` | `Description`/`Description 2` kopíruje base sám v `InitPurchOrderLine`; `TransferFromReqLineToPurchLine` je v 28.4 prázdná obálka jen s eventem |

- `Copy to Req. Wksh` (`Carry Out Action.CarryOutToReqWksh`) dělá `RequisitionLine2 := RequisitionLine` → extension pole
  přejdou sama. Kontrolní guard na `SupplyInvtProfile."Action Message" = New` (jen nové řádky).
- Base Sales Order (42/46/99000883) **nemá** akci „Přenést do sešitu požadavků" — takové akce dodávají jiné appky;
  ptej se, kterou cestu volají, ne po captionu.
- **EPB Pricing Matrix 28.0.3.1** má `Requisition Line PMEBS` (Parameter A/B, Sales Price Var. Code) a v `Price Mgt. PMEBS`
  propagaci Sales Line → Req. Line pro Get Sales Orders + Order Planning (ne pro Calculate Plan) + reverse fill z UoM
  při `TransferFromPurchaseLine/TransLine`. Verze **28.0.3.0 to nemá** → dependency minimum zvedni na 28.0.3.1.
  Ověření obsahu symbolu bez MCP: python `zipfile` na `.app` od offsetu `PK\x03\x04`, `SymbolReference.json` →
  `TableExtensions[].Name` (MS test knihovny mají objekty vnořené v `Namespaces[]`, projdi rekurzivně).
- **EM Net Make to Order (NMEBS)** přidává na Sales Order akci *Transfer Lines to Plan* (CZ „Přenést do sešitu požadavků",
  za akcí Plánování) a na subform *Transfer Line to Plan*: report 64120 `CreateReqLineFromSales NMEBS` →
  `Manufacturing Mgmt. NMEBS.InsertRequisitionLineFromSalesLine` skládá řádek sešitu **sám** (`Insert(false)` + Validate
  No./Variant/Location/UoM/Quantity/Due Date, vazba `Target Order No./Line No./Type NMEBS` + `Sales Production Ref. NMEBS`;
  nákup → Req. template, výroba → Planning template z Manufacturing Setup / User Setup). Žádná standardní cesta výše se nevolá;
  do 28.0.3.0 jen `OnBeforeInsertRequisitionLineFromSalesLine` (IsHandled). Event
  `OnInsertRequisitionLineFromSalesLineOnBeforeRequisitionLineModify(var ReqLine; var SalesLine; var SalesHeader; var Item)`
  před `Modify(false)` přidán 2026-09-12 (větev `ReqLineFromSalesEvent`, čeká na release). Zdroj: sibling repo
  `prod-em-netMakeToOrder-bc`; NMEBS nemá žádné dependencies, takže závislost zákaznické appky na ní je levná.
- **EM MRP Replenishment (OREBS)** je další modul, který řádek sešitu skládá **sám** a standardní cesty výše obchází:
  reporty 64245 *Suggest Replenishment for Prod. Order* (CZ „Navrhni dozásobení pro výrobní zakázku“) a 64246 *… for Sales
  Order* → `Manufacturing Mgmt. OREBS.CreateRequisitionLineFromProdOrderComponent` / `…FromSalesLine` (`Init` + Validate
  Type / No. / Location / Bin / Quantity / Due Date / Dimension Set ID, vazba `Source Table No./Type/No./Line No./Ref. Line
  No. OREBS`, `Insert(true)`). Hook pro vlastní pole poptávky = **`OnBeforeInsertNewRequisitionLineFromProdOrderComponent(var
  NewRequisitionLine; var Item; var ProductionOrder; var ProdOrderLine; var ProdOrderComponent)`** / **`OnBeforeInsertNew
  RequisitionLineFromSalesLine(var NewRequisitionLine; var Item; var SalesLine)`** — běží po všech Validate (`Validate("No.")`
  už dal popis ze zboží, přiřazení v subscriberu vyhraje), obě jsou ve vydané 28.0.0.0, OREBS nemá dependencies. Test bez
  reportu: přímo `PlanItemProdOrderComponent(Item, ToDate, false, false, false, ReqLine, ProdOrder, ProdOrderLine, Comp,
  Template, Batch)` / `PlanItemSalesLine(...)` — `Item` musí mít `SetFilter("Date Filter", '..%1', ToDate)` (`CheckItemDateFilter`
  jinak spadne); report sám chce OREBS šablony / listy v Manufacturing Setup a `User Setup` uživatele a v GUI otevírá stránku
  řádků. Akce sešitu *Merge with Lot Accumulation Period* (CZ „Sloučit s Obdobím kumulace dávky“, report 64247) slučuje podle
  zboží / lokace / varianty / MJ / data bez eventu na filtr → vlastní pole sloučených řádků se ztratí (zůstanou z prvního).
  (2026-10-30, cust-alumistr-bc PBI 67394 — Poznámka / Barva / Parametr A/B z komponent VZ chyběly v sešitu.)
  **Ruční test reportu 64245 v sandboxu:** Nastavení výroby, záložka *MRP dozásobení Essence* — všechny čtyři *Výchozí šablona /
  list sešitu plánování / požadavků* (`TestField`, prázdné v čerstvém prostředí) a záznam *Nastavení uživatele* pro přihlášeného
  (`UserSetup.Get(UserId())`). *Ukládat chyby* na request page = dávkový režim (`HelpRunnerOREBS`), pro interaktivní cestu nech
  vypnuté. Hláška *„Žádné řádky plánování nebyly navrženy.“* není chyba: komponenta se plánuje jen při `Inventory − prodej + nákup
  − Qty. on Component Lines (všechny otevřené VZ) + … < Remaining Qty. (Base)` k datu potřeby. Zboží se zásobou z dřívějších
  testovacích dat pokryje malou komponentu → zvedni *Množství za*. Nákupní zboží jde do šablony požadavků, výrobní do plánování.
  Ve výsledné stránce *Řádky požadavků* (517) vlastní sloupce nejsou, akce *Zobrazit sešit* otevře 291 se vším. (2026-10-30,
  Alumistr BC-DEV.)
- Test knihovny BC 28: `Library - Planning` / `Library - Manufacturing` / `Library - Sales` jsou v **Application Test
  Library**, ne v Tests-TestLibraries (tam zbyla jen `Library - Manufacturing OnPrem`). Užitečné: `CalcRequisitionPlanForReqWkshAndGetLines(var ReqLine; var Item; From; To)`,
  `CarryOutReqWksh(var ReqLine; ExpirationDate; OrderDate; PostingDate; ExpectedReceiptDate; YourRef)`,
  `LibraryPurchase.CreateDropShipmentPurchasingCode`, `OrderPlanningMgt.PlanSpecificSalesOrder(var ReqLine; SONo)`,
  `OrderPlanningMgt.SetDemandType("Demand Order Source Type"::"Production Demand") + GetOrdersToPlan(var ReqLine)`.

### 5.x21 Přepočet ceny vyvolaný Množstvím bez ceníku cenu NEPŘEPÍŠE — odpojený řádek si nechá cenu hromadné objednávky (ruční slevu ale smaže)

`Purchase Line - Price` / `Sales Line - Price` / `Requisition Line - Price` `.IsPriceUpdateNeeded(AmountType, FoundPrice,
CalledByFieldNo)` (w1-28.4): když ceník nic nenajde (`FoundPrice = false`), cena se **nepřepíše**, pokud přepočet vyvolalo
pole **Quantity** (nákup navíc `Job No.`, `Job Task No.`; všude `Variant Code` bez SKU) — aby ruční cena přežila změnu
množství. Vazba na hromadnou objednávku přitom cenu jen drží (`BlanketOrderIsRelated` → cena z řádku HNO/HPO) a
`Validate("Blanket Order No.", '')` na ceně nic nemění. Důsledek: řádek odpojený od HNO/HPO po změně množství (nebo řádek
sešitu, kterému se zruší vazba v `OnAfterGetDirectCost` po změně Quantity) **zůstane s cenou a slevou z hromadné
objednávky**, pokud ceník na položku nemá řádek. `UpdateDirectUnitCost(FieldNo("No."))` na tomtéž řádku v UI nepomůže —
`UpdateDirectUnitCostByField` skončí na `(CalledByFieldNo <> CurrFieldNo) and (CurrFieldNo <> 0)`.

**Fix:** spočítat cenu na **temporary kopii** jako při zadání zboží a převzít ji:
`Temp := Line; Temp.UpdateDirectUnitCost(Temp.FieldNo("No."))` (prodej `UpdateUnitPrice(FieldNo("No."))`, sešit veřejné
`GetDirectCost(FieldNo("No."))` — vlastní `OnAfterGetDirectCost` subscriber temp kopii pustí díky `IsTemporary`), pak
`Line.Validate("Direct Unit Cost" / "Unit Price", Temp…)` + `Validate("Line Discount %", Temp…)`. Kopie má `CurrFieldNo = 0`,
takže výpočet doběhne. Zachyceno 2026-10-05 v lokálním kontejneru (test čekal Last Direct Cost 7.77 / Unit Price 55.55,
dostal 11.11 / 99.99 z HNO/HPO); s opravou zelené. Starý komentář „po přepočtu už řádek nese standardní cenu" platil jen
s řádkem ceníku. (cust-sonnentor-bc PBI 64046, `Blanket Purch./Sales Link Mgt. SON.ApplyStandardPrice`.)

⚠️ **Sleva se chová opačně — ruční `Line Discount %` změnu Množství / Varianty NEPŘEŽIJE.** `UpdateUnitPriceByField`
volá `PriceCalculation.ApplyDiscount()` **před** `ApplyPrice` a `Price Calculation - V16.ApplyDiscount` slevu nastaví vždy:
bez nalezené slevy v ceníku `FillBestLine` → `SetPrice(Discount, …)` = **0** (výjimka jen `IsDiscountAllowed() = false`,
tj. `Allow Line Disc.` vypnuté). `IsPriceUpdateNeeded` chrání jen cenu. Kód, který řádku z kódu mění `Quantity` /
`Variant Code` (dělení řádku, přepočet, kopie), musí slevu zapamatovat předem a po všech validacích vrátit
(`Validate("Line Discount %", …)` + `Modify`) — jinak uživatel ruční slevu tiše ztratí, cena přitom zůstane. Ověřeno na
BC-TEST2 (Alumistr, split 10 ks se slevou 15 % → oba řádky 0 %) a ve zdrojáku w1-28 (`SalesLine.Table.al`
`UpdateUnitPriceByField`, `PriceCalculationV16.Codeunit.al` `ApplyDiscount`, `SalesLinePrice.Codeunit.al`
`IsPriceUpdateNeeded`). (2026-10-06, prod-ess-configurator-bc PBI 66392, `Sales Line Split Mgt. COEBS`.)

**Vzor „ruční sleva přežije ruční změnu množství"** (prod-ess-configurator-bc PBI 66392 znovuotevřeno, 2026-10-27):
- `modify(Quantity)` v tableextension: `OnBeforeValidate` si uloží `Rec."Line Discount %"` do codeunitu v globální proměnné
  tableextension (Before i After běží na téže instanci `Rec`), `OnAfterValidate` ji vrátí `Validate("Line Discount %")`.
- Jen při `CurrFieldNo = FieldNo(Quantity)`: `Quantity` validované vnořeně z MJ / zboží / vazby HNO nese `CurrFieldNo` toho pole
  (viz níže), kód má 0 — volající z kódu (split, přepsání z konfigurace) si slevu řeší sám.
- Zdroj slevy `Rec` v `OnBeforeValidate`, ne `xRec`: na stránce je `xRec` stav před úpravou a slevu napsanou na tomtéž řádku těsně
  před množstvím nemusí obsahovat (úvaha, ověří test na TestPage — zatím jen zkompilovaný).
- `ValidateLineDiscountPercent` (w1-28) nemá bránu `Allow Line Disc.`, jen `TestJobPlanningLine` + `TestStatusOpen`.
- Řádky, které rozšíření při změně zdroje **maže a zakládá znovu**, slevu ztratí s řádkem — přenést ji při znovuvytvoření (temp
  buffer smazaných řádků před `DeleteAll`, párování typ + číslo + varianta + pořadí, aplikovat až po eventech, které řádek
  přeceňují). Množstevní slevy z ceníku (minimální množství) se na takových řádcích přestanou přepočítávat — před volbou „vracet
  vždy" ověř v ceníku zákazníka (stránka *Řádky ceníku* 7005, filtr `Line Discount %` <> 0, sloupec *Minimální množství*).

⚠️ **Ruční navázání přes `Blanket Order Line No.` spustí vnořené `Validate(Quantity)`.** Standardní `OnValidate` pole (Sales i
Purchase Line, w1-28) po `TestField`ech volá `Validate("Variant Code" / "Location Code" / "Unit of Measure Code")` a UoM trigger
končí `Validate(Quantity)` (prodej přes `UpdateQuantityFromUOMCode`) — teprve **potom** `Validate("Unit Price" / "Direct Unit Cost")`
+ `Validate("Line Discount %")` z řádku HNO/HPO. Subscriber na `OnAfterValidateEvent(Quantity)` tak běží i při ručním navázání:
řádek už nese novou vazbu, `CurrFieldNo` = pole vazby (≠ 0, „vypadá jako UI změna množství"), uložená verze v DB vazbu ještě nemá.
Když tam kód vazbu odpojí (`Validate("Blanket Order No.", '')`), standard po návratu stejně dopíše cenu a slevu z hromadné
objednávky → **řádek bez vazby s cenou HNO/HPO**. „Rekontrolu navázaného řádku" pouštěj jen na řádek, který tutéž vazbu měl
už v uložené verzi (`Get` + porovnat Blanket Order No./Line No.), ne na vazbu, která právě vzniká. (2026-10-06, cust-sonnentor-bc
PBI 64046, code review větve `BlanketOrders_64046_Feedback`; zdroj w1-28 `SalesLine.Table.al` / `PurchaseLine.Table.al`.)

⚠️ **Změnu `Variant Code` (ani `Location Code`) navázaného řádku standard nehlídá.** Vazba zůstane, cena taky
(`UpdateDirectUnitCostByField` / `UpdateUnitPriceByField` → `BlanketOrderIsRelated` → cena řádku HNO/HPO) a `Purch.-Post` /
`Sales-Post.UpdateBlanketOrderLine` testuje jen `Type`, `No.` a dodavatele / zákazníka → účtování čerpá řádek hromadné objednávky
**jiné varianty**. Hlídání = subscriber `OnAfterValidateEvent("Variant Code")` s podmínkou „vazba + varianta ≠ varianta řádku
HNO/HPO": vznikající vazba ji nikdy nesplní, standardní validace `Blanket Order Line No.` volá `Validate("Variant Code", <varianta
HNO>)` jako první krok (u Drop Shipment / Special Order jen `TestField`). Pak `Validate("Blanket Order No.", '')` + standardní cena
přes temp kopii (výš) + hledání HNO/HPO pro novou variantu. Odpojit jde jen nepřijatý / nedodaný řádek (`TestField("Quantity
Received" / "Quantity Shipped", 0)`) a standardní validace varianty navíc chce `Qty. Rcd. Not Invoiced` / `Qty. Shipped Not
Invoiced` = 0 a prázdné `Receipt No.` / `Shipment No.` → vlastní chyba „řádek už je přijatý" nastane jen u přijatého **a
vyfakturovaného** řádku a test ho musí zaúčtovat `PostPurchaseDocument(…, true, true)` (CRONUS CZ prošlo bez dalšího nastavení).
`Variant Code` je na `Purchase/Sales Order Subform` ve standardu `Visible = false` → testuj přes `Rec.Validate` a kontrolu proto
neomezuj na `CurrFieldNo <> 0`. (2026-10-09, cust-sonnentor-bc Task 66586; zdroj Base App 28.5 `PurchaseLine/SalesLine.Table.al`,
`PurchPost/SalesPost.Codeunit.al`.)
⚠️ **„Uživatel už to odsouhlasil" neber z cache odpovědí klíčované `SystemId` řádku.** `Purchase/Sales Order Subform` mají
`DelayedInsert = true` → řádek pořízený na stránce při validaci množství **ještě nemá SystemId**, klíč vyjde prázdný a odpověď
se neuloží; řádek z `Req. Wksh.-Make Order` má odpověď pod klíčem řádku sešitu, z Vytvořit objednávku z HNO/HPO nebo z ruční
vazby žádnou. Testy, které zakládají řádek přes `Library - Purchase/Sales` (`Insert` dřív než validace) a navazují kódem, cache
mají **vždy** → „převázání bez dotazu" prošlo v testech a v UAT by se ptalo. Odsouhlasení ber z dat (původní `Blanket Order No.`
uložené před odpojením, předané do rozhodování jako „accepted"), cache neplň (u klíče dokladu by pustila i další řádky) a přidej
test s vazbou standardní validací **bez ConfirmHandleru**. (2026-10-09, code review cust-sonnentor-bc Task 66586.)
Opačná past téže cache: uložené **Ano** („převzít X“, „pokračovat bez X“) pak řádek **potichu** přepíná mezi HNO a zapíná / vypíná
vazbu (hlášení PFIL „jakoby si to řádek pamatoval“). Pamatuj jen odpovědi, které stav řádku nemění (Ne na převzetí, Ano na „bez“
u řádku, který bez vazby zůstává), a před odpojením odpověď smaž. (2026-10-19, cust-sonnentor-bc Task 66948.)

⚠️ **Hlavička / pole řádku, které vazbu na HNO/HPO nehlídají (w1-28.5, Task 66948).** `Recreate{Purch,Sales}Lines` (změna dodavatele,
plátce, měny, zákazníka, střediska, DPH skupiny) s navázaným řádkem **spadne** na `TestField("Blanket Order No.", '')` v
`Test{Purch,Sales}LineFieldsBeforeRecreate` (PurchaseHeader 7630, SalesHeader 7264) – ten běží až **po** `OnBeforeRecreate…Lines`, takže tam
vazby ulož stranou (SingleInstance, klíč Line No.) a odpoj, po `OnAfterRecreate…Line` rozhodni znovu (`IsHandled` na `OnBeforeTest…` ne – vypne
všechny kontroly). Řádky se zakládají **bez** vazby a množství se validuje z kódu (`CurrFieldNo = 0`); prodej validuje `Location Code` ještě se
**starým** zákazníkem. Ověřeno testy v kontejneru (2026-10-19, 307/307); dřívější věta „vazba tiše zmizí“ byla omyl. Hooky s novým i původním řádkem: `Purchase Header.OnAfterRecreatePurchLine
(var PurchLine; var TempPurchLine temporary; var PurchaseHeader)` po `Insert`, `Sales Header.OnAfterRecreateSalesLine`; rámec změny
`OnBeforeRecreate…Lines(var Header)` / `OnAfterRecreate…Lines(var Header; ChangedFieldName: Text[100])`. Změna Buy-from recreatuje jednou
(Pay-to jen při stejném Buy-from). `Document Date` hlavičky na řádky nesahá (`Posting Date` ho validuje přes `ValidateDocumentDateWithPostingDate`, jen s *Link Doc. Date To
Posting Date*) – ⚠️ to dělá i účtování (hromadné s *Replace Posting/Document Date*, skladová příjemka/dodávka, WorkDate subscriber Essence
Distribution) nad **otevřeným** dokladem → kontroly řádků z hlavičky omez na změnu ze stránky (`CurrFieldNo <> 0` na hlavičce, vnořený Validate
z Posting Date ho nese; z codeunity přes `internal procedure` v tableextension, AL0161) a `GuiAllowed()`. Carry Out (`ReqWkshMakeOrder.
CopyOrderDateFromPurchHeader`) validuje `Order Date` na **kopii** řádku sešitu (zboží s nákupním ceníkem) → subscriber `OnAfterGetDirectCost`
by se ptal nad kopií; `OnBeforeCopyOrderDateFromPurchHeader` + výpočet na temporary kopii.
Header `Location Code` jen hlásí `MessageIf…LinesExist`. **`Variant Code` ani `Location Code` řádku nevalidují `Quantity`** (`No.` ano, přes
`Validate(UoM)`) → logika na `OnAfterValidateEvent(Quantity)` se po změně varianty / lokace nespustí. `Purchase Order Subform.Quantity`
`OnValidate` i `Sales Order Subform.QuantityOnAfterValidate` (Item) volají `CurrPage.SaveRecord()` → subscriber při dalším `SetValue(Quantity)`
v TestPage vidí v DB stav po předchozím kroku.
