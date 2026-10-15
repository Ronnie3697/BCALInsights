# BC/AL poznámky — Item Tracking (šarže, sériová čísla, Reservation Entry)

> Vyčleněno z `bc-al-objects.md` 2026-10-07 (soubor přesáhl 1000 řádků). Číslování sekcí 5.x / 5.x2 / 5.x2b / 5.x15 je původní,
> aby fungovaly odkazy „viz X.Y" z ostatních souborů.
> Načítej, když řešíš: Item Tracking Lines (6510) a její eventy, výběr šarže, Lot No. / Serial No. na dokladech,
> Reservation Entry (337) vs Tracking Specification (336), source pole u VZ, tracking na nabídce (Prospect vs Surplus),
> tracking na fakturačním řádku z Get Shipment Lines, šarže = číslo projektu, Assign Serial No. / Create Customized SN.

Obsahuje:
- **5.x** výběr / obohacení šarže — vlastní page z akce na Item Tracking Lines
- **5.x2** source pole trackingu u Prod. Order Line
- **5.x2b** tracking na Sales Quote — Prospect vs Surplus
- **5.x15** tracking na fakturačním řádku z Get Shipment Lines
- **5.x15b** předvyplnění šarže na Item Tracking Lines (hooky stránky 6510), SN zboží bez automatického řádku
- **5.x16** automatické přiřazení šarže z kódu (FEFO) — prošlé šarže při Strict Expiration Posting přeskoč
- **5.x17** `Reservation Entry."Entry No."` je AutoIncrement — `"Entry No." := 0` před Insert, nikdy FindLast + 1
- **5.x18** dobropis / vratka s `Appl.-from Item Entry` z kódu — SQNR se mění až při účtování, slučování šarží při účtování

## 5. Specifické objekty a API — Item Tracking

### 5.x Item Tracking — filtrování/obohacení výběru šarže (Lot No.)

Když potřebuješ **omezit nebo obohatit výběr šarže** při zadávání item trackingu
(typicky consumption na Prod. Order Component — výběr Lot No. dle vlastního kritéria,
zobrazení vlastních polí z Lot No. Information), **nepokoušej se rozšiřovat nativní
výběrový dialog** `Item Tracking Summary` (page 6500 nad tabulkou `Entry Summary` 338).
Dva tvrdé blokátory:

- **`Entry Summary` (338) nemá `Item No.`** (jen Lot/Serial/Package No. + qty + Source
  Subtype + Table ID). Lot No. Information (klíč Item No.+Variant+Lot No.) odtud
  spolehlivě nedohledáš.
- **`Item Tracking Data Collection` (6501) event `OnAfterRetrieveLookupData(TrackingSpecification;
  FullDataSet; TempGlobalReservEntry; TempGlobalEntrySummary)` nepředává entry summary
  buffer `var`** — subscriber ho neumí filtrovat ani plnit. (Ověřeno přes al-mcp
  `al_search_object_members` — všechny parametry ByReference=false.)

**Funkční pattern (Sonnentor 64042 — výběr šarže dle kvality):** vlastní výběrová stránka
otevřená **akcí z `Item Tracking Lines` (page 6510, source `Tracking Specification` 336)**.
Řádek 6510 (`Rec`) **má `Item No.`, `Variant Code`, `Location Code` i Source pole**, takže:

- Komponentu VZ dohledáš ze Source: `Source Type = Database::"Prod. Order Component"`,
  `Source Subtype`→Status (Option→Integer→`"Production Order Status".FromInteger`),
  `Source ID`→Prod. Order No., `Source Prod. Order Line`→Prod. Order Line No.,
  `Source Ref. No.`→Line No.
- Kandidátní šarže naplníš do **temp buffer tabulky** (`TableType = Temporary` → žádný
  permission/tabledata) z `Lot No. Information` (+ vlastní pole), zůstatek lotu vezmi
  z **FlowField `Inventory`** (`CalcFields(Inventory)` s `SetRange("Location Filter", …)`)
  — nemusíš sám sumarizovat Item Ledger Entry.
- Výběrová `page` (List, `SourceTableTemporary`, lookup mode) si buffer plní v `OnOpenPage`;
  „rozpustit filtr" = akce, která přenaplní buffer bez filtru (ne mazání řádků).
- Po `RunModal = LookupOK` vrať Lot No. na řádek 6510 a v `OnAction` zavolej
  `CurrPage.Update(true)` — tím proběhne standardní tracking validace, neobcházíš ji.

Business logiku (resolve required code, build buffer) dej do codeunitu s **public**
procedurami → testovatelné z test appky bez TestPage (UI tracking přes TestPage je fragile).

### 5.x2 Item Tracking — mapování Source polí u řádku VZ (Prod. Order Line)

`Reservation Entry` (337) i `Tracking Specification` (336) plní source pole pro
**Prod. Order Line** takto (base app `Prod. Order Line-Reserve.InitFromProdOrderLine`):

```al
SetSource(Database::"Prod. Order Line", Status.AsInteger(), "Prod. Order No.", 0, '', "Line No.");
//        Source Type                   Source Subtype      Source ID          ^Source Ref. No. = 0
//                                                                             Source Prod. Order Line = "Line No."
```

**`Source Ref. No.` je 0** — číslo řádku VZ žije v **`Source Prod. Order Line`**!
(U komponent 5407 je to jinak: `Source Prod. Order Line` = řádek VZ,
`Source Ref. No.` = Line No. komponenty.) Důsledek: SubPageLink / filtr factboxu
nad tracking daty pro Prod. Order Line **musí** linkovat
`"Source Prod. Order Line" = field("Line No.")` — link přes `Source Ref. No.`
nikdy nematchne a part je věčně prázdný (chyba ze Zlomek 64189; u Sales Line je
naopak správně `Source Ref. No.`). Ověřeno extrakcí z BC 27.5 base app.

### 5.x2b Item Tracking na Sales Quote — standard ho umí, přenáší se do Order

**Prodejní nabídka má standardní item tracking.** Na `Sales Quote Subform` (95)
je akce **„Item Tracking Lines"** (`Rec.OpenItemTrackingLines()`, jen pro
`Type = Item`, ne pro ATO řádky) a tracking se ukládá do `Reservation Entry`
(337) se `Source Type = 37`, **`Source Subtype = 0`** (Quote), `Source ID` =
číslo nabídky, `Source Ref. No.` = Line No. Při **Make Order** (`Sales-Quote to
Order`, 86) se rezervační položky přenesou na objednávkový řádek přes
`SalesLineReserve.TransferSaleLineToSalesLine(SalesQuoteLine, SalesOrderLine,
"Outstanding Qty. (Base)")` — SN/šarže zadané na nabídce tedy na SO nezmizí.
Totéž platí pro Blanket Order → Order (87). Neplést s **rezervací** skladu:
`Reserve` na nabídce nedělá nic užitečného, ale tracking (jednostranné entries
s SN) na ní žije. Ověřeno w1-28 (2026-09-02, nacenění Zlomek 62661).

⚠️ **Tracking na nabídce má `Reservation Status = Prospect`, ne Surplus.**
`Item Tracking Lines` (6510) `SetSourceSpec` dává `Surplus` jen „order network
entitám" a `Item Tracking Management.IsOrderNetworkEntity` bere u `Sales Line`
**jen Subtype 1 (Order) a 5 (Return Order)** — nabídka (0) a rámcová objednávka
(4) padnou do `else` větve = `Prospect`. Na Surplus to překlopí až
`TransferSaleLineToSalesLine` během Make Order. Důsledky:

- Vlastní kód, který jednostranný tracking hledá `SetRange("Reservation
  Status", …::Surplus)`, na nabídkách **tiše nedělá nic** (žádná chyba, žádný
  záznam) → filtruj `'%1|%2'` Surplus + Prospect. Párované (`Reservation` /
  `Tracking`) nech být — `CreateReservEntry.CreateEntry` pro ně zakládá dvě
  řádky a protistrana drží starou hodnotu.
- `Sales-Quote to Order` volá na **každé** položce
  `ReservEntry.TestItemFields(SalesLine."No.", "Variant Code", "Location Code")`
  → jakýkoliv nesoulad varianty mezi řádkem a jeho rezervačními položkami
  vybouchne až tady (*„Kód varianty musí být rovno…"*), ne při samotné změně.
  Konfigurátorové scénáře, které mění `Variant Code` řádku se sledováním, proto
  musí variantu na entries srovnat samy — a `CreateReservEntry.TransferReservEntry`
  ji s sebou nese přes `TransferFields(OldReservEntry, false)`, takže po přesunu
  položky na jiný řádek zůstává stará.

(2026-09-17, prod-ess-configurator-bc WI 66066 — rozdělení řádku nabídky
s konfigurací; `Sales Line Split Mgt. COEBS.AlignTransferredTrackingVariant`
srovnával jen Surplus, na nabídce tedy nic, a Make Order padal. Zdroje Base
Application 28.3.52162.53506, extrakce z .app.)

**Praktický dopad:** report/factbox „rozpad SN z řádků nabídky" se čte z 337
(+ 336 pro handled) s filtrem `Source Subtype = 0`, žádné vlastní pole na
řádku není potřeba. U Zlomku to sbírá hotová codeunit `Item Tracking Mgt. ZLK`
(`CollectForDocument(Database::"Sales Line", DocType, DocNo, TempBuffer)`,
viz doc 64189 v `cust-zlomek-bc`) — při dalších reportech nad SN nabídky ji
znovu použij, nepiš nový sběr. Pro jeden řádek (sloupce Výčet SN / Počet SN na subformu, PBI 65152)
má `CollectForSalesLine` / `GetSalesLineSerialNos` — bere 337 ve **všech** stavech (Surplus, Prospect,
Reservation, Tracking), filtr na stav by nezrychlil nic (klíč `Source ID, Source Ref. No., Source Type,
Source Subtype, …` = seek) a schoval by SN rezervovaná ze skladu.

⚠️ **Test knihovna stav nabídky NEsimuluje:** `Library - Item Tracking.CreateSalesOrderItemTracking` →
`InsertItemTracking` dává `Prospect` jen řádkům deníku zboží, plánovaným/simulovaným VZ a sešitu požadavků;
**každý `Sales Line` (i nabídka) dostane `Surplus`** (BCApps `LibraryItemTracking.Codeunit.al`). Test, který
má hlídat chování na nabídce (Prospect), musí stav po založení přepnout sám (`"Reservation Status" :=
Prospect` + `Modify(false)`), jinak kód filtrující jen Surplus projde zeleně. Stejně levně jde zafixovat
„všechny stavy“ (přepnout jednu položku na Reservation / Tracking — sběr čte jen stranu řádku).
(2026-10-08, cust-zlomek-bc 65152 code review, `Sales Line SN Tests ZLK`.)

### 5.x15 Item Tracking na fakturačním řádku z Get Shipment Lines — smí být JEN `Prospect` z dodávky; subscriber na `Validate(Quantity)` tam nesmí sahat

`Sales Shipment Line.InsertInvLineFromShptLine` (BC 28) staví fakturační řádek jako `SalesLine := SalesOrderLine` → `Line No.` /
`Document Type` / **`Shipment No.` + `Shipment Line No.`** → `ClearSalesLineValues` → **`SalesLine.Validate(Quantity, …)`** (ještě před
`Insert`) → … → `Insert` → `ItemTrackingMgt.CopyHandledItemTrkgToInvLine` (Prospect entries s `Item Ledger Entry No.` z Item Entry
Relation dodávky). Při účtování jde řádek s `Shipment No. <> ''` přes `Sales Line-Reserve.RetrieveInvoiceSpecification2`, který projde
**všechny** rezervační položky řádku a na každé udělá `TestField("Reservation Status", Prospect)` + `TestField("Item Ledger Entry No.")`.
Jakýkoli vlastní subscriber na `Sales Line OnAfterValidateEvent Quantity/No./…`, který zakládá tracking (`CreateReservEntry.CreateEntry(…,
Surplus)`), se na fakturačním řádku chytne už při tom `Validate(Quantity)` (Line No. je nenulové, řádek vypadá „čistý", protože
`ClearSalesLineValues` vynulovalo Qty. Shipped) → na řádku je tracking dvojmo (Item Tracking Lines ukáže množství 2× vyšší než řádek)
a účtování padne „Stav rezervace musí být rovno 'Výhled' v Položka rezervace … Současná hodnota je 'Přebytek'". Obrana v subscriberu:
`"Shipment No." <> ''` / `"Return Receipt No." <> ''` → exit (obojí je přiřazené před Validate); a obecně status podle
`Item Tracking Management.IsOrderNetworkEntity` — Surplus jen pro Order/Return Order, Invoice/Credit Memo/Quote/Blanket dostávají Prospect
(viz 5.x2b), filtry na vlastní tracking pak `Surplus|Prospect`. Úklid rozbitého dokladu: smazat řádek faktury a Get Shipment Lines znovu
(rezervační položky řádku se smažou s ním). (2026-09-24, cust-soitron-bc `Job Lot Tracking Mgt. SOI` — šarže = číslo projektu, faktura z
částečné dodávky.)
Oprava v cust-soitron-bc 2026-09-24 (`Job Lot Tracking Mgt. SOI`, testy `Job Lot Tracking Test SOI`): guard `Shipment No.` /
`Return Receipt No.` (sales) a `Receipt No.` / `Return Shipment No.` (purchase) v `IsRelevant*Line` + status z
`ItemTrackingMgt.IsOrderNetworkEntity(SourceType, SourceSubtype)` (public) místo pevného Surplus; všechny filtry/mazání
vlastního trackingu berou ten samý status. V testu částečnou dodávku šaržového řádku uděláš tak, že na jediné Surplus položce
řádku nastavíš `"Qty. to Handle (Base)"` / `"Qty. to Invoice (Base)"` na dodávané množství (`Modify(false)`), jinak Sales-Post
hlásí nesoulad Qty. to Handle vs. Qty. to Ship. `Sales Line."Job No."` (45) je v BC 28 `Editable = false` bez OnValidate —
`OnAfterValidateEvent` na něj přesto z kódu funguje.

### 5.x15b Předvyplnění šarže na `Item Tracking Lines` (6510) — hooky pro ruční řádek, Assign Serial No. a Create Customized SN

Když má zboží **sledování SN i šarže**, jednostranný automatický tracking na celé množství řádku (5.x15) je k ničemu —
každý kus potřebuje vlastní řádek se SN (uživatel musel auto-řádek smazat a nové řádky už šarži neměly). Řešení v
cust-soitron-bc (`Job Lot Tracking Mgt. SOI`, 2026-10-07): u SN zboží auto-řádek nevytvářet a šarži doplňovat na stránce
6510 do každého řádku s prázdnou šarží. Stránka je `SourceTableTemporary` nad `Tracking Specification` (336) — **guard
`IsTemporary` tam nepatří**, Rec je temp vždy. Hooky (všechny s `var Rec`, zdroj Base App 28.5 `ItemTrackingLines.Page.al`):

- **Ruční řádek:** `OnBeforeOnInsertRecord(var TrackingSpecification; SourceQuantityArray; var Result; var IsHandled)` (z
  `ValidateAndInsert`, před `InsertRecord` → `TempItemTrackLineInsert.TransferFields(Rec)`) a
  `OnBeforeOnModifyRecord(var TrackingSpecification; xTrackingSpecification; InsertIsBlocked; var Result; var IsHandled)`
  (z `OnModifyRecord` před `UpdateTrackingData` → `Rec.Modify` + buffery). Nový řádek má source pole i `Item No.` z filtrů
  (`SetFilters` = `SetRange` ve FilterGroup 2 → platforma je dá do `Init`). Žádný `OnNewRecord` event stránka nemá; pageextension
  s `OnNewRecord` by sice šarži ukázala hned, ale pak `Rec.TestField("Lot No.", '')` v Assign Serial No. s „Create New Lot No."
  spadne — eventová cesta nechá explicitně vyžádanou šarži ze řady vyhrát.
- ⚠️ **Zadání SN šarži VYMAŽE, když SN není skladem:** page `Serial No.` OnValidate volá `FindLotNoBySNSilent(LotNo, Rec)`
  (`Clear(LotNo)` + hledání v `TempGlobalEntrySummary`) a pak **bezpodmínečně** `Rec.Validate("Lot No.", LotNo)` → šarže
  zadaná před SN zmizí. Hned nato `CurrPage.Update()` → `OnModifyRecord` → subscriber ji doplní znovu (`"Lot No." = ''` →
  fill). `OnValidateSerialNoOnBeforeFindLotNo(Rec, IsHandled)` by lookup přeskočil úplně — nepoužívat, u výdeje má lot ze skladu
  přednost.
- **Funkce Assign Serial No. / Create Customized SN:** `OnAfterAssignNewTrackingNo(var TrkgSpec; xTrkgSpec; FieldID; var
  SourceTrackingSpecification)` se volá po `AssignNewSerialNo` / `AssignNewCustomizedSerialNo` (FieldID = `FieldNo("Serial No.")`)
  **před** `Validate("Quantity (Base)")` + `Rec.Insert()` v cyklu → šarže se zapíše do vloženého řádku i do
  `TempItemTrackLineInsert`. Source ber ze `SourceTrackingSpecification` (vždy nastavené v `SetSourceSpec`). S „Create New Lot
  No." je šarže z řady přiřazená před cyklem (FieldID Lot No.) → fill-if-empty ji nechá. `OnAssignSerialNoBatchOnAfterInsert` /
  `OnCreateCustomizedSNBatchOnAfterRecInsert` jsou až po `Insert` — změna Rec by chtěla `Modify`, zbytečné.
- `Validate("Lot No.")` na temp řádku je bezpečný: `WMSManagement.CheckItemTrackingChange` řeší jen `Source Type = Item Journal
  Line`; `TestField("Quantity Handled (Base)", 0)` ohlídej předem. `Create Customized SN` vyžaduje `No. Series."Manual Nos."`
  na `Item."Serial Nos."` (`NoSeries.TestManual`).
- **Změna projektu u SN zboží:** auto-řádek neexistuje, takže místo delete + create přepiš `Lot No.` na jednostranných
  položkách (`Surplus`/`Prospect` podle `IsOrderNetworkEntity`) s `Lot No. = stará šarže` (prázdná, když projekt nebyl) na novou;
  položky s jinou šarží nech (ruční zadání). `ReadIsolation(IsolationLevel::UpdLock)` + `FindSet` + `Modify(false)`.
- **PlatformCop PC0013:** `SalesLine.Get(ReservEntry."Source Subtype", …)` s Integer do enum PK pole alc 17 přeloží, ale PC0013 je
  error → `Enum::"Sales Document Type".FromInteger(SourceSubtype)` (base app to tak dělá taky).
- **Testy (TestPage):** `PurchaseLine.OpenItemTrackingLines()` → `[ModalPageHandler]` na `TestPage "Item Tracking Lines"`:
  ruční řádky `"Serial No.".SetValue` + `"Quantity (Base)".SetValue(1)` + `New()`; funkce `"Assign Serial No.".Invoke()` →
  handler `TestPage "Enter Quantity to Create"` (`CreateNewLotNo.SetValue(false)`, `OK()`), `"Create Customized SN".Invoke()` →
  `TestPage "Enter Customized SN"` (`CustomizedSN`, `Increment`, `CreateNewLotNo`, `OK()`); supply strana (nákup) má akce
  `"Assign Serial No."` / `"Create Customized SN"`, demand (prodej) `"Assign &Serial No."` / `CreateCustomizedSN` (dvě sady,
  `Visible` podle `FunctionsSupplyVisible` / `FunctionsDemandVisible`). Nákup je pro test jednodušší — výdej bez skladu se při
  zavření ptá na dostupnost (ConfirmHandler). SN+Lot zboží: `LibraryItemTracking.CreateItemTrackingCode(Code, true, true)` +
  `LibraryUtility.CreateNoSeries(NoSeries, true, true, false)` + `CreateNoSeriesLine` pro `Serial Nos.`. Assert DB po zavření
  (`Reservation Entry` per SN + `Lot No.`), ne hodnotu na TestPage (kdy proběhne insert řádku, TestPage nezaručuje).
  Testy `Job Lot Tracking Test SOI` — lokálně jen kompilace, běh až v CI.

### 5.x16 Automatické přiřazení šarže z kódu (FEFO) — prošlé šarže při *Strict Expiration Posting* přeskoč

- Vlastní FEFO (open positive ILE per lot, řazení podle `Expiration Date`, zápis přes `Create Reserv. Entry`) vezme jako
  „first expired" klidně **už prošlou** šarži. Když má `Item Tracking Code` **`Strict Expiration Posting`** („Přísné účtování
  expirace"), `Item Jnl.-Post Line` výdej odmítne: „Datum expirace je před zúčtovacím datem. v Položka zboží Číslo
  položky='244'" — kontext chyby je ILE šarže, ne řádek dokladu. Doklad se přitom vytvořil v pořádku, padá až účtování.
- Pravidlo: při sestavování kandidátů vyřaď šarži s `Expiration Date <> 0D` a `< Posting Date` dokladu (ne WorkDate —
  importovaný doklad má datum z cizího systému), **jen když** je `Strict Expiration Posting` zapnuté (bez něj BC prošlou
  šarži prodat dovolí). Když po vyřazení nic nezbude, vyhoď vlastní chybu, která řekne, že šarže byly prošlé a kód
  sledování vyžaduje přísné účtování — „chybí N kusů" bez důvodu uživatele zmate (zásoba na kartě je vidět).
- Test: `Library - Item Tracking`.`CreateItemTrackingCode(Code, false, true)` + `Validate("Use Expiration Dates", true)` +
  `Validate("Strict Expiration Posting", true)`; naskladnění šarže přes `CreateItemJournalLineInItemTemplate` +
  `CreateItemJournalLineItemTracking(ResEntry, Line, '', LotNo, Qty)` + `ResEntry.Validate("Expiration Date", …)`, zúčtovací
  datum naskladnění **před** expirací (`WorkDate() - 30`), ať příjem nenarazí na stejnou kontrolu.
- Pozn. k datům v BC-DEV: lookup šarže na 6510 ukáže i prošlou šarži (expirace je vidět ve sloupci *Datum expirace*
  řádku sledování) — rychlá diagnostika, proč účtování padá. (2026-10-12, prod-ess-dotykackaConnector-bc PBI 63075,
  `Dotykacka Lot Assign DCEBS`, Sonnentor kód LOTEXP.)
- **„Prodat zbytek do mínusu na šarži" (Force Sell Negative) NEJDE s `Lot Specific Tracking`.** `Item Jnl.-Post Line`
  (`InsertItemLedgEntry`, w1-28) hodí *Text018 „Lot No. … cannot be fully applied"*, když by zůstala otevřená záporná
  položka šarže a `ItemTrackingCode.IsSpecific()` (= SN Specific or Lot Specific) je true. Bez Lot Specific se výdej
  šarží vůbec nevyrovnává (`ApplyItemLedgEntrySetFilters` šarži nefiltruje) a do mínusu projde (pokud zboží zápornou
  zásobu dovolí). Vlastní FEFO s režimem „do mínusu" proto u Lot Specific musí skončit vlastní chybou **před** založením
  dokladu — jinak vznikne doklad, který nikdy nezaúčtuješ. Když žádná šarže nemá volnou zásobu (vyprodaná, nebo ji
  celou drží nezaúčtovaný doklad), vezmi existující šarži i z **uzavřených** ILE (nejpozdější expirace), jinak režim
  „do mínusu" v nejčastějším případě nezabere. Víc `Reservation Entry` téže šarže na jednom řádku nevadí (účtování je
  sečte přes `SumUpItemTracking`), ale je to nepořádek — sbírej alokace do temp bufferu a zapiš jednu na šarži.
  (2026-10-14, code review prod-ess-dotykackaConnector-bc, `Dotykacka Lot Assign DCEBS`.)

### 5.x17 `Reservation Entry."Entry No."` je `AutoIncrement` — nikdy `FindLast + 1`, žádný zámek to nezachrání

- Pole 1 tabulky 337 má `AutoIncrement = 1`. Base (`Create Reserv. Entry.CreateEntry`) nastaví `"Entry No." := 0`,
  číslo přidělí SQL identity při `Insert` a druhou položku páru (`Positive` false/true) vloží pod číslem převzatým
  z první **po** jejím Insertu.
- Vlastní `GetNextEntryNo` přes `FindLast + 1` (s `LockTable` i s `ReadIsolation::UpdLock`) proti tomu **závodí**:
  souběžný base insert poslední řádek nečte, takže ho zámek nezablokuje → naše explicitní číslo už existuje → „The record
  already exists". Projeví se náhodně pod zátěží (účtování, sklad). UpdLock na posledním řádku navíc drží zámek do
  konce transakce a brzdí další vlastní sessiony.
- Správně: `"Entry No." := 0` před `Insert` (po `TransferFields` z jiné položky nulu nastavit znovu — kopíruje PK),
  po Insertu je přidělené číslo v recordu. Pár položek = druhá s číslem první. Temporary record AutoIncrement
  nemá (tam dál ručně). Historická explicitně vložená čísla nevadí, SQL identity se po nich posune na maximum.
- Ověření, jestli tabulka AutoIncrement má: al-mcp `al_get_object_definition` (`summaryMode: false`) ukáže property
  u pole; zdroj base viz `microsoft/BCApps` `src/Layers/W1/BaseApp/Inventory/Tracking/CreateReservEntry.Codeunit.al`
  (raw.githubusercontent, bez `gh`: `curl -sfL`). (2026-10-12, cust-jiri-bc EUDR — šest vlastních insertů
  rezervací přešlo z `GetNextReservationEntryNo` na nulu.)

### 5.x18 Dobropis / vratka s `Appl.-from Item Entry` z kódu — odečti, co si z položky vzaly ostatní řádky dokladu

- `Shipped Qty. Not Returned` (SQNR) prodejní ILE se mění **až při účtování**. Kód, který při stavbě dobropisu hledá
  „první ILE s `Abs(SQNR) >= množství`", tak dá dvěma řádkům téhož zboží **stejnou** položku → účtování spadne až v
  `Item Jnl.-Post Line.UpdateOutboundItemLedgEntry` („Shipped Qty. Not Returned is too low in Item Ledger Entry").
  Kontrola na řádku (`Sales Line.CheckApplFromItemLedgEntry`) porovnává jen vlastní řádek proti DB, takže nic nechytí.
  Volné množství = `Abs(SQNR)` − součet `Quantity (Base)` ostatních řádků dokladu se stejným `Appl.-from Item Entry` −
  `Reservation Entry` řádků dokladu (`SetSourceFilter(Database::"Sales Line", DocType, DocNo, -1, true)` = všechny řádky)
  se stejným `Appl.-from Item Entry`. Funguje, když předchozí řádky už jsou vložené i s rezervacemi.
- **Šarže: účtování slučuje sledování podle šarže a vyrovnání bere z prvního řádku.** `RetrieveItemTracking` →
  `SumUpItemTracking(…, false, true)` sečte řádky sledování jen podle Lot/Serial (filtr `TrackingSpecification`
  ignoruje vyrovnání) a celé množství aplikuje na `Appl.-from Item Entry` prvního z nich → dvě `Reservation Entry` téže
  šarže s různým vyrovnáním na jednom řádku = přečerpání první ILE. Slouč je podle šarže a vyrovnání nech jen tehdy, když
  ho pokryje jediná ILE, jinak 0 (pozor: při *Exact Cost Reversing Mandatory* pak dobropis nezaúčtuješ — `TestField`
  v `TransferSalesLineToItemJnlLine`). (2026-10-14, code review prod-ess-dotykackaConnector-bc, storno účtenky se dvěma
  řádky téhož zboží, ověřeno w1-28.)

### 5.x19 Propagace vlastního pole Sales Line → Prod. Order Line přes vazbu Order-to-Order — subscriber na `Reservation Entry.OnAfterInsertEvent` base přepíše svým `Modify()`

- Vazba MTO vzniká **až po `Insert` řádku VZ** (`Sales Line-Reserve.BindToTracking` → `Create Reserv. Entry.CreateEntry` →
  `ReservEntry.Insert()` + `ReservEntry2.Insert()`; partner existuje až při druhém insertu). Subscriber, který při ní
  nastaví pole na `Prod. Order Line` **jinou instancí** (`Get` + `Modify(false)`), v DB vyhraje jen na okamžik — base
  pak uloží **svou** (zastaralou) instanci řádku a pole přepíše zpět:
  `Create Prod. Order from Sale.CreateProductionOrder` (Item Order: `BindToTracking` → `ProdOrderLine.Modify()`),
  `Create Prod. Order Lines.CopyFromSalesOrder` (Project Order / Refresh VZ se zdrojem Sales Header: `BindToTracking` →
  `ProdOrderLine.Modify()`), `Mfg. Carry Out Action.InsertProdOrderLine` (sešit: `TransferPlanningLineToPOLine` /
  `ReserveBindingOrderToProd` → `ProdOrderLine.Modify()`). Hlavička VZ (jiná instance, base ji po vazbě znovu neukládá)
  přežije → při změně stavu (`Prod. Order Status Management`: `ToProdOrderLine := FromProdOrderLine` → `Insert` →
  subscriber `OnAfterInsertEvent` řádku nastaví pole na **`var Rec`** → následný `ToProdOrderLine.Modify()` ho zachová)
  se pole na řádcích „záhadně" objeví až po vydání. Pevně plánovaná z prodejky ho nemá, vydaná ano = tenhle vzor.
- `Production Order.OnAfterInsertEvent` s podmínkou na `Source Type/No.` v `Create Prod. Order from Sale` nikdy nechytne:
  `ProdOrder.Insert(true)` běží **před** nastavením zdroje (Source No. prázdné), zdroj se dopíše `Modify()`.
- **Fix = nastav pole do `var ProdOrderLine` těsně před base `Modify()`** (všechny tři eventy mají řádek by-ref):
  `OnCreateProductionOrderOnBeforeProdOrderLineModify(var ProdOrderLine; var SalesLine; var ProdOrder; …)` (99000787),
  `OnCopyFromSalesOrderOnBeforeProdOrderLineModify(var ProdOrderLine; SalesLine; SalesPlanningLine; var NextProdOrderLineNo)`
  (99000788), `OnInsertProdOrderLineOnBeforeModifyProdOrderLine(var ProdOrderLine; var RequisitionLine)` (Mfg. Carry Out
  Action). Nejjednodušeji obecně: načti uloženou verzi řádku (`Stored.Get(ProdOrderLine.RecordId)`) a převezmi z ní pole,
  které reservation subscriber zapsal — nezávislé na tom, odkud se vazba bere. Test „VZ z prodejky (MTO) má příznak na
  řádku" musí assertovat **DB po dokončení akce**, ne stav uvnitř subscriberu. (2026-10-15, cust-sonnentor-bc PBI 65215
  `Pallet Tracking Mgt. SON`; zdroj Base App 28.5 extrakce z .app.)
