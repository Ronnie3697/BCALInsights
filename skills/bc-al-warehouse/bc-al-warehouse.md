# BC/AL poznámky — Sklad (přihrádky, skladové doklady a aktivity, MJ ve skladu)

> Vyčleněno z `bc-al-objects.md` 2026-11-19 (soubor měl 1000 řádků); číslování 5.x22, 5.x26–5.x28 je původní kvůli odkazům „viz X.Y".
> Pozor: čísla 5.x22 / 5.x26–5.x28 mají i `bc-al-tracking.md` a `bc-al-projects.md` (jiný obsah, souběžné číslování) — odkazuj
> vždy i se jménem souboru.
> Načítej, když řešíš: přihrádku na řádcích SO/PO a její cestu do skladové příjemky / dodávky, skladový přesun / vyskladnění
> z kódu (čtečky), jinou MJ než základní ve skladu, nový řádek deníku zboží z kódu, skladový doklad v jiné MJ než zdrojový doklad.
> `VerifyOnInventory` a qty-per na Item Journal Line (5.x6) zůstávají v `bc-al-objects.md`; fyzická inventura se šaržemi
> (5.x26) → `bc-al-tracking.md`; vlastní pole Sales Line → Whse. Shipment → `bc-al-posting.md`.

Obsahuje:
- **5.x22** přihrádka (Bin Code) na řádcích SO/PO → skladová dodávka / příjemka
- **5.x26** skladový přesun / vyskladnění z kódu — `Validate("Bin Code")` na řádku Take, registrace jednoho páru Take/Place
- **5.x27** jiná MJ než základní ve skladu bez řízeného zaskladnění
- **5.x28** nový řádek deníku zboží z kódu v prázdném listu
- **5.x34** skladový doklad v jiné MJ než zdrojový doklad — co standard BC 29 unese
- **5.x35** nákup s projektem v lokaci s přihrádkami — standard odepíše skladovou položku příjmu za spotřebu projektu

## 5. Specifické objekty a API — sklad

### 5.x22 Přihrádka (Bin Code) na řádcích prodejní / nákupní objednávky a její cesta do skladové dodávky / příjemky (BC 28)

Ověřeno ve zdrojích w1-28 při PBI 65239 (cust-sonnentor-bc, 2026-10-09 — výchozí přihrádka zákazníka / dodavatele
na hlavičce → řádky → skladový doklad):

- **Kde standard přihrádku řádku dokladu počítá:** `Sales Line.GetDefaultBin()` (public) / `Purchase Line.GetDefaultBin()`
  (local) — volá se z validace `No.`, `Location Code` a `Variant Code` řádku zboží. Vynuluje `Bin Code`, u Drop Shipment
  skončí, jinak při `Location."Bin Mandatory" and not "Directed Put-away and Pick"` vezme **výchozí Obsah přihrádky**
  (`WMS Management.GetDefaultBin` = Bin Content s `Default = true`). **Prodejní řádek ji navíc vůbec nenastaví, když má
  lokace `Require Shipment` a existující `Shipment Bin Code`** (`IsShipmentBinOverridesDefaultBin`) — proto bývá na
  prodejních řádcích přihrádka prázdná, zatímco na nákupních je vyplněná. Hook pro vlastní default = **`OnAfterGetDefaultBin(var
  SalesLine)` / `(var PurchaseLine)`** na konci procedury (běží i ve větvi, kde base nic nenastavil; pro ne-Item řádky se
  nevolá). Přiřazení do `Rec` je jen v paměti, stejně jako base — žádný `Modify`, žádná `IsTemporary` výjimka.
- **Řádek skladové příjemky / dodávky z objednávky:** `Purchases Warehouse Mgt.PurchLine2ReceiptLine` / `Sales Warehouse
  Mgt.FromSalesLine2ShptLine` dají `Bin Code` z **hlavičky skladového dokladu** (= `Location."Receipt Bin Code"` /
  `"Shipment Bin Code"`, když lokace sedí) a přihrádku řádku objednávky jen jako fallback při prázdné; pak ještě
  `Whse.-Create Source Document.UpdateReceiptLine/UpdateShipmentLine` hlavičkovou přihrádku znovu `Validate`. Přihrádka
  z řádku objednávky se tedy do skladového dokladu **standardně nedostane**, když lokace má příjmovou / expediční
  přihrádku. Poslední místo před `Insert` = **`OnBeforeWhseReceiptLineInsert(var WarehouseReceiptLine)` /
  `OnBeforeWhseShptLineInsert(var WarehouseShipmentLine)`** (codeunit 5750) — zdrojový řádek tam není parametrem, dohledej
  `Purchase Line.Get(Order, "Source No.", "Source Line No.")`. Alternativa s řádkem v parametru:
  `OnAfterCreateRcptLineFromPurchLine` / `OnAfterCreateShptLineFromSalesLine` (po `Insert`, nutný `Modify(false)`).
- **`Validate("Bin Code")` na řádku objednávky z kódu / testu = `Message`**: `Bin Code.OnValidate` volá `CheckWarehouse(true)`
  a u typu Objednávka v lokaci s `Require Receive` (nákup) / `Require Shipment` (prodej) bez existujícího řádku skladového
  dokladu skončí `Message(WhseRequirementMsg)` → test potřebuje `[MessageHandler]`; s existujícím řádkem skladového dokladu
  je to `Error`. Prodejní řádek má navíc `TableRelation` na **Bin Content** (Order s `Quantity >= 0`) a `CheckBinCodeRelation`
  → přihrádka bez obsahu pro dané zboží se na prodejní řádek z kódu nedá zadat (`LibraryWarehouse.CreateBinContent` před
  `Validate`). Přímé přiřazení (`"Bin Code" := …` + `Modify`) žádnou z kontrol nespouští. `Validate(Quantity)` z kódu
  dialog nedává (`CheckWarehouseForQtyToShip` / `CheckLocationRequireReceive` jen při `CurrFieldNo <> 0`).
- **Hlavička → řádky:** `UpdatePurchLinesByFieldNo` / `UpdateSalesLinesByFieldNo` nejdřív udělají `Modify()` hlavičky a pak
  validují řádky; subscriber na `OnAfterValidateEvent("Location Code")` hlavičky běží **až po** nich, takže hodnota, kterou
  v něm na hlavičku dosadíš, se na řádcích při téže validaci ještě neprojeví — dorovnej řádky v tom subscriberu sám.
- **Sales Order Subform má sloupec `Bin Code` `Visible = false`** (Purchase Order Subform `true`) → bez `modify("Bin Code")
  { Visible = true; }` uživatel přihrádku na prodejním řádku nezmění ani nevidí. `TestPage` ji pak také nevidí (bc-al-autotests).
- Testovací setup: `LibraryWarehouse.CreateLocationWMS(Location, BinMandatory, PutAway, Pick, Receive, Shipment)` +
  `CreateBin(Bin, Loc, Code, '', '')` + `Location.Validate("Receipt Bin Code" / "Shipment Bin Code")` +
  `CreateWarehouseEmployee(WhseEmployee, Loc, false)`; skladový doklad `CreateWhseReceiptFromPO(PurchaseHeader)` /
  `CreateWhseShipmentFromSO(SalesHeader)` po `Release…Document` (bez dialogu). `LibraryUtility.GenerateRandomCode` vrací
  `Code[10]`.

### 5.x26 Skladový přesun / vyskladnění z kódu: `Validate("Bin Code")` na řádku Take a registrace jednoho páru Take/Place

Ověřeno ve zdrojích w1-28 (`WarehouseActivityLine.Table.al`, `WhseActRegisterYesNo` / `WhseActivityRegister.Codeunit.al`,
`WMSManagement.CheckBalanceQtyToHandle`, `BinContent.Table.al`) při review prod-ew-mobileBase-bc 66918 (2026-10-20):

- **`Warehouse Activity Line."Bin Code".OnValidate` dělá kontroly jen při `CurrFieldNo <> 0`** (= ze stránky). Z kódu
  (`TakeLine.Validate("Bin Code", …)`) se přeskočí: `BinType.TestField(Receive, false)` u Take řádku, `CheckWhseDocLine`,
  dostupnost v přihrádce (`CheckExceedQtyAvailBase`) i u řízené lokace `CreatePick.CalcTotalAvailQtyToPick`. Kdo mění
  přihrádku Take řádku z kódu (sken na čtečce), musí si kontroly napsat sám a **zrcadlit base**:
  - Obsah přihrádky hledej v MJ podle `GetUOMCode`: řízená lokace (*Directed Put-away and Pick*) = `"Unit of Measure Code"`
    řádku, **jinak základní MJ zboží** (`WMS Management.GetBaseUOM`) — na základní lokaci je Bin Content v základní MJ,
    `BinContent.Get(…, řádek."Unit of Measure Code")` s jinou než základní MJ nenajde nic a dostupnost vyjde 0.
  - Typ aktivity: `Pick`, `Invt. Pick`, `Invt. Movement` → `BinContent.CalcQtyAvailToPick(0)`, **`Movement` →
    `CalcQtyAvailToTake(0)`**. `CalcQtyAvailToPick` vrací **0 pro dedikovanou přihrádku** a pro `Block Movement` =
    Outbound/All (exit bez hodnoty), `CalcQtyAvailToTake` dedikaci neřeší.
  - Při jiné zóně nejdřív `Validate("Zone Code", Bin."Zone Code")` (TableRelation `Bin Code` filtruje podle zóny řádku),
    `Zone Code.OnValidate` vyprázdní `Bin Code` / `Bin Ranking` / `Bin Type Code`.
- **Registrace jen jednoho páru jde přes standard:** `Codeunit.Run(Codeunit::"Whse.-Act.-Register (Yes/No)", Lines)` s filtrem
  `"Line No." = Take|Place`. `Yes/No` dělá `WhseActivLine.Copy(Rec)`, `CheckBalanceQtyToHandle` kopíruje filtry volajícího a
  `Whse.-Activity-Register.Code` jen přidá `Activity Type` / `No.` / `Qty. to Handle (Base) <> 0` → zapíše se jen pár a
  bilance Take = Place se kontroluje jen na něm. Potvrzovací dialog přeskočí manuálně bindovaný subscriber na
  `OnBeforeConfirmRegister(var Line; var Result; var IsHandled)` (`Result := true; IsHandled := true`).
- **Detail řádku otevřený s `SetRecFilter` na řádku Place zapíše jen Place** – `Yes/No` vezme filtry předaného záznamu (jen PK
  Place) a spadne na bilanci *„Celkové základní množství k výběru 0 musí být rovno celkovému základnímu množství k vložení 6.“*
  Detail, který registruje z `Rec`, otevírej s filtry dokladu (`Activity Type`, `No.`, případně zboží) a pár drž přes `Qty. to
  Handle` (ostatní řádky 0), nebo předej filtr `"Line No." = Take|Place`. (2026-10-23, prod-ew-mobileBase-bc MobileOverallCheck.)
- **Po částečné registraci standard sám vyplní `Qty. to Handle` na všech zbylých řádcích** (`AutofillQtyToHandle`), pokud
  hlavička nemá `Do Not Fill Qty. to Handle`; plně zapsané řádky a prázdnou hlavičku smaže (`Header.Get` = false → doklad hotový).
- **Párování Take ↔ Place nemá v tabulce vazbu.** Standard (Create Pick / Create Inventory Pick/Movement) zakládá Take a hned za
  ním Place, ale **`Split Line` na Take řádku vloží nový Take mezi ně** (`Line No.` = půlka mezery) → „nejbližší předchozí
  Take" pak ukáže na odštěpenou část s menším množstvím. Robustnější filtr: zboží, varianta, tracking, MJ,
  `"Whse. Document Line No."` / `"Source Line No."` a kontrola 1:1 (`Qty. Outstanding (Base)` Take = Place), jinak srozumitelná
  chyba „zpracuj v BC".

### 5.x27 Jiná MJ než základní ve skladu bez řízeného zaskladnění — registrovat v základní MJ, množství přepočítat (MJ řádku neměnit)

Ověřeno ve zdrojích w1-28 (`WhseJnlRegisterLine`, `WMSManagement`, `WarehouseActivityLine`, `WarehouseReceiptLine`, `ItemJournalLine`,
`UnitofMeasureManagement`) a v BC-DEV (prod-ew-mobileBase-bc 66453 — MJ z naskenovaného odkazu na zboží, 2026-10-22):

- **Lokace bez *Directed Put-away and Pick* drží Warehouse Entry i Bin Content vždy v základní MJ** (`InitWhseEntry`: `Quantity :=
  "Qty. (Absolute, Base)" * Sign`, `GetBaseUOM`, qty per 1; `WMSMgt.InitWhseJnlLine` z deníku zboží a `Whse.-Activity-Register` dělají
  totéž). **Past:** `InitWhseEntry` hledá cílový obsah `ToBinContent.Get(…, WhseJnlLine."Unit of Measure Code")` = v MJ **řádku** → vlastní
  `Warehouse Journal Line` (Movement) v KS obsah v M nenajde, zavolá `InsertToBinContent` a v přihrádce, kde už zboží leží, spadne na
  duplicitním klíči Bin Content. Kód, který registruje skladový deník přímo (`Codeunit.Run(Codeunit::"Whse. Jnl.-Register Line", …)` —
  přesun / korekce na čtečce), musí na non-directed lokaci dát `Unit of Measure Code` = základní, `Qty. per Unit of Measure` = 1,
  `Quantity` = `Qty. (Base)`. Max. množství z přihrádky ber z `Quantity (Base)` (filtr na základní MJ) a přepočti do MJ uživatele —
  filtr Bin Content na KS nenajde nic.
- **MJ řádků dokladů neměň, přepočti zadané množství do MJ řádku.** `Warehouse Activity Line."Unit of Measure Code"` (`Editable =
  false`) z kódu přepočte qty per, ale **čísla nepřevede** (10 M → 10 KS); report 7314 *Whse. Change Unit of Measure* je jen na
  subformu Warehouse Pick/Movement a `CheckUOM` u Take chce Bin Content v nové MJ → na non-directed lokaci spadne.
  `"Qty. to Handle (Base)".OnValidate` nastaví `UseBaseQty := true`, který se na proměnné **neresetuje** (další `Validate("Qty. to
  Handle")` na téže proměnné už base nepřepočítá) → validuj `"Qty. to Handle"` s množstvím v MJ řádku. `Warehouse Receipt Line` MJ
  měnit nejde (bez OnValidate) a `"Qty. to Receive (Base)"` má `TestField("Qty. per Unit of Measure", 1)` → `Validate("Qty. to
  Receive", …)`. Deník fyzické inventury: řádky z *Calculate Inventory* jsou v základní MJ a změna MJ končí `TestField("Phys.
  Inventory", false)` (Validate(Quantity)) → napočítané KS převeď a zapiš do `"Qty. (Phys. Inventory)"`.
- `Item Reference."Unit of Measure"` je součást PK, `Insert(true)` s prázdnou MJ doplní základní; standardní převzetí MJ z odkazu
  (`ValidateItemJournalReferenceNo`): `if ItemReference."Unit of Measure" <> '' then Validate("Unit of Measure Code", …)`.
- Přepočet: `Unit of Measure Management.CalcBaseQty(ItemNo, Variant, UoM, Qty, QtyPer, RoundingPrecision)` (parametr se jmenuje
  `QtyBase`, ale je to množství v MJ — počítá `QtyBase * QtyPerUOM`), `CalcQtyFromBase(…)` (zaokrouhlí na 0,00001),
  `GetQtyPerUnitOfMeasure(Item, UoM)` vrací 1 pro základní i prázdnou MJ. Mezi dvěma MJ převáděj přes základní.

### 5.x28 Nový řádek deníku zboží z kódu bez řádku k zkopírování (prázdný list) — `SetUpNewLine` a lokace až před zbožím

Ověřeno v BC-DEV 28.5 (prod-ew-mobileBase-bc, první řádek deníku fyzické inventury ze čtečky, 2026-10-23):

- Prázdný list nemá řádek, ze kterého by šly zkopírovat datum a číslo dokladu → `Init`, `"Journal Template Name"` /
  `"Journal Batch Name"` a `SetUpNewLine(PrázdnýPoslední)`: vezme `WorkDate`, `PeekNextNo` z číselné řady listu, zdrojový kód
  a kód důvodu (neexistující kombinace šablona / list = *„List deníku zboží Neexistuje …“*).
- **`Validate("Location Code")` na řádku deníku zboží potřebuje číslo zboží** (*„Pole Číslo zboží musí mít hodnotu … Číslo
  řádku=0“*) → lokaci jen přiřaď (jako u zkopírovaného řádku), pak `Validate("Item No.")` (výchozí přihrádka, dimenze včetně
  lokace) a nakonec `Validate("Bin Code")` (relace přihrádky filtruje podle lokace řádku).
- Řádek fyzické inventury založený mimo *Vypočítat zásoby* má `Qty. (Calculated)` 0 → když zboží v přihrádce už je, zaúčtuje se
  celé napočítané množství jako kladná úprava. Rozhodni, jestli `Qty. (Calculated)` dopočítat z obsahu přihrádky.

### 5.x34 Skladový doklad v jiné MJ než zdrojový doklad — co standard BC 29 unese (příjemka / dodávka zůstává v MJ zdroje)

Ověřeno čtením zdroje BaseApp 29.1 CZ 2026-11-19 při cust-alumistr-bc PBI 66601 (RFC *Měrná jednotka skladu* — sklad chce kusy,
nákup / prodej / výroba jedou v metrech). V BC nespouštěno; co je jen odvozené ze zdroje, je u bodu napsané.

- **Kde vznikají řádky skladové příjemky / dodávky (stav BC 29.1; 5.x22 popisuje w1-28):** codeunit 5750 `Whse.-Create Source
  Document` drží jen interní helpery a eventy, logika per zdroj je v `Sales Warehouse Mgt.` (5991, `FromSalesLine2ShptLine`),
  `Purchases Warehouse Mgt.` (5992, `PurchLine2ReceiptLine`) a `Transfer Warehouse Mgt.` (5993). `Unit of Measure Code`, `Qty. per
  Unit of Measure` i rounding precision se kopírují 1:1 ze zdrojového řádku (`SetItemData`); pole MJ na `Warehouse Receipt Line` /
  `Warehouse Shipment Line` není editovatelné (5.x27). Eventy po cestě: `OnAfterInitNewWhseShptLine`, `OnBeforeSetQtysOnRcptLine` /
  `OnAfterSetQtysOnRcptLine`, `OnBeforeSetQtysOnShptLine` / `OnAfterSetQtysOnShptLine`. **Past:** MJ změněná v `OnAfterSetItemData`
  dostane rounding precision potom přepsanou.
- **Účtování skladového dokladu zapisuje do zdrojového řádku množství v MJ SKLADOVÉHO řádku, bez přepočtu:** `Whse.-Post Receipt` →
  `PurchaseLine.Validate("Qty. to Receive", WhseRcptLine."Qty. to Receive")`, `Whse.-Post Shipment` → `SalesLine.Validate("Qty. to
  Ship", …)`. Příjemka v KS nad nákupním řádkem v M (1 KS = 6 M, 10 KS) by tiše zaúčtovala 10 M do položek zboží a 60 M do skladových
  položek (odvozeno ze zdroje, nespuštěno). Dodávka v jiné MJ spadne už při vytvoření (`CheckSourceDocLineQty`, base). → **Skladová
  příjemka / dodávka zůstává v MJ zdrojového řádku.** „Sklad v kusech“ = zdrojový řádek v kusech (např. `Item."Purch. Unit of
  Measure"`), nebo přepočet až na čtečce (vzor 66601 níže).
- **Vyskladnění k dodávce v jiné MJ:** FlowField `Warehouse Shipment Line."Pick Qty."` filtruje `"Unit of Measure Code" =
  field("Unit of Measure Code")` → otevřené řádky vyskladnění v jiné MJ nevidí (riziko druhého vyskladnění téhož řádku).
  `Whse.-Activity-Register.UpdateWhseShipmentLine` při rozdílné MJ přičte do `"Qty. Picked"` `QtyToHandleBase / QtyPerUOM` řádku
  **aktivity** → částečné vyskladnění v jiné MJ zapíše špatné číslo, srovná ho jen plné vyskladnění (větev zbytku zaokrouhlení).
  Hook: `OnUpdateWhseShptLineOnAfterAssignQtyPicked`.
- **Vyskladnění pro výrobu:** `Mfg. Whse. Activity Register.UpdateProdCompLine` dělí základní množství qty per UoM řádku aktivity →
  vyskladnění v KS nad komponentou v M nastaví `Qty. Picked` = 10 (base 60). `Qty. Picked` řídí `AdjustQtyToQtyPicked`, kontrolu
  deníku spotřeby i `Completely Picked`; FlowField `Pick Qty.` na komponentě filtruje MJ stejně jako u dodávky. Vyskladnit víc, než
  komponenta potřebuje, jde jen s `Item."Allow Whse. Overpick"`; *Calc. Consumption* i flushing spotřebovávají podle potřeby, ne podle
  vyskladněného. EM Cutting Plan V2 navíc vynucuje základní MJ na řádcích kusovníku / komponentách optimalizovaného zboží
  (`CheckBaseUnitOfMeasure`).
- **Inventura:** deník fyzické inventury z reportu 790 *Calculate Inventory* je fakticky jen v základní MJ (změna MJ končí
  `TestField("Phys. Inventory", false)`, 5.x27); *Whse. Phys. Invt. Journal* jen v lokacích s *Directed Put-away and Pick*. Vlastní MJ
  umí řádky *Phys. Invt. Order* / *Phys. Invt. Recording* (`OnBeforePhysInvtRecordLineInsert`; nastav i textové pole `"Unit of
  Measure"`).
- **`Item Unit of Measure."Qty. Rounding Precision"` zaokrouhluje na nejbližší (případně chyba `InvalidPrecisionErr`), nahoru nikdy.**
  Zaokrouhlení prodejního řádku nahoru na celé jednotky jiné MJ (celé kusy) = vlastní kód v `Sales Line.OnBeforeValidateQuantity(var
  SalesLine; xSalesLine; CallingFieldNo; var IsHandled)`, který běží před `UOMMgt.RoundAndValidateQty`.
- `Item."Put-away Unit of Measure Code"` se uplatní jen v lokacích s *Directed Put-away and Pick*.
- **Vzor 66601 pro čtečky (MJ jen na zobrazení):** Essence Warehouse Mobile Base dostal event `EWM Scan UoM Mgt.
  EXEBS.OnAfterGetHandheldUoM(ItemNo; ScannedUoMCode; var HandheldUoMCode)` (větev `66601_WarehouseDisplayUoM` v prod-ew-mobileBase-bc,
  zatím nevydáno) — zákaznická appka určí MJ čtečky per zboží, detailní stránky čtečky přepočítávají množství, doklady v BC zůstávají
  v MJ zdrojového dokladu.

(2026-11-19, cust-alumistr-bc PBI 66601, zdroj BaseApp 29.1 CZ.)

### 5.x35 Nákup s projektem v lokaci s přihrádkami: standard odepíše skladovou položku příjmu za spotřebu projektu, i když spotřeba nevznikla

Ověřeno čtením zdroje w1-28 (`PurchPost`, `WhsePostReceipt`, `WhseActivityPost`, `WhseUndoQuantity`, `UndoPurchaseReceiptLine`,
`SalesPost`) a eventy v BaseApp 28.4 (al-mcp) při rozboru hlášení z X-ESSENCE 2026-11-20 (prod-ep-itemManagement-bc, IMEBS *Skip
Purchase Consumption*: zboží 1019 má 3 ks v položkách zboží, 0 v obsahu přihrádky, skladové položky příjemky +3 / −3). V BC nespouštěno,
oprava zatím neimplementovaná.

- **Spotřebu projektu při příjmu (`PostItemJnlLineJobConsumption`, Negative Adjmt. ILE) a skladový odpis z přihrádky standard dělá
  odděleně.** Skladový odpis se řídí jen tím, že řádek má `Job No.` — kdo spotřebu vypne (`Purch.-Post.OnPostItemJnlLineJobConsumption`
  → `IsHandled`), musí vypnout i odpis, jinak zůstane položka zboží skladem (`Remaining Quantity`) a obsah přihrádky 0 → dodávka
  z přihrádky pak spadne na nedostatek v přihrádce. Tři místa, všechna s `IsHandled` eventem:
  1. **`Purch.-Post.PostItemJnlLineWhseLine`** (lokace s `Bin Mandatory` bez skladových dokladů; u *Directed Put-away and Pick* přímá
     faktura / dobropis): po registraci příjmu `RevertWarehouseEntry` = Negative Adjmt. Warehouse Entry z téže přihrádky (`From Bin Code
     := To Bin Code`), když `Job No. <> ''` a nejde o vratku. Hook `OnBeforeRevertWarehouseEntry(var WarehouseJournalLine; JobNo;
     PostJobConsumption; var Result; var IsHandled)` — Purchase Line v parametru není, dohledej ji ze `Source Subtype` / `Source No.` /
     `Source Line No.` skladového řádku (`CreateWhseJnlLine` je plní, řádek v DB při účtování existuje). **Vratka** (credit doc s kladným
     množstvím, záporný řádek objednávky) naopak přes `CreatePositiveEntry` nejdřív „vrátí spotřebu" do přihrádky a pak ji vratka odebere
     → přihrádka se nezmění; hook `OnBeforeCreatePositiveEntry(WarehouseJournalLine; JobNo; var Result; var IsHandled)`.
  2. **`Whse.-Post Receipt`** (*Require Receive*): `PostWhseJnlLine` po každém řádku `ConsumeWarehouseEntryForJobPurchase` (otočený
     záznam z příjmové přihrádky) a `IsReceiptForJob` navíc **zaskladnění nevytvoří** (posted řádek rovnou *Completely Put Away*,
     `CreatePutAwayDoc` řádek přeskočí). Obojí jde přes `IsReceiptForJob` → jeden hook `OnBeforeIsReceiptForJob(PostedWhseReceiptLine;
     var IsReceiptForJob; var IsHandled)` (zdroj = `Source Subtype/No./Line No.` posted řádku); jen odpis bez zaskladnění vypne
     `OnBeforeConsumeWarehouseEntryForJobPurchase`.
  3. **`Whse.-Activity-Post`** (zásobové zaskladnění, *Require Put-away* bez *Require Receive*): `IsActivityForJobPurchase` (bez eventu)
     → `ConsumeWarehouseEntryForJobPurchase` → hook `OnBeforeConsumeWarehouseEntryForJobPurchase(var TempWarehouseJournalLine;
     WarehouseActivityLine; var Result; var IsHandled)`.
  Vratka přes skladovou dodávku / zásobové vyskladnění žádnou projektovou větev nemá (`ShouldPostWhseJnlLine` je při `WhseShip` false).
- **Undo příjemky** (`Whse. Undo Quantity.InsertTempWhseJnlLine`) otáčí **všechny** Warehouse Entry příjemky podle source + `Reference
  No.` → zrcadlí, co příjem zaúčtoval (+N / −N i jen +N), nic navíc neodepisuje. Undo + nový příjem je tak i cesta, jak srovnat data
  zaúčtovaná před opravou — na lokaci bez *Directed Put-away and Pick* skladovou položku bez položky zboží standardně zaúčtovat nejde
  (*Whse. Item Journal* jen Directed).
- Prodejní strana nic podobného nemá: dodávka (i řádek s `Job Contract Entry No.`) odepisuje přihrádku normálně přes
  `Sales-Post.ShouldPostWhseJnlLine`; dobropis s vynuceným `ShouldPostItemJnlLine` (IMEBS) vrací zboží do přihrádky řádku.

