# BC/AL poznámky — Propagace vlastních polí do účtovaných dokladů, archivu a kopií

> Vyčleněno z `bc-al-data.md` 2026-09-29 (sekce 3.5–3.6f; soubor přesáhl 1000 řádků). Původně část
> `bc-al-notes.md` (archiv `bc-al-notes.archived-2026-06-23.md`).
> Načítej, když řešíš: vlastní pole na Sales/Purchase Header/Line a jejich cestu do archivu, účtovaných
> dokladů, kopie dokladu a obnovy z archivu (TransferFields, Blob + CalcFields, částečné účtování a undo,
> `Validate("No.")` → `Init()`), kontroly dokladu před účtováním a Job No. na dodávce vs. faktuře.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y". Obecné subscriber patterny
> (3.1–3.4, 3.7–3.9) zůstávají v `bc-al-data.md`.

Obsahuje:
- **3.5** Propagace vlastního pole přes Sales posting + Warehouse Shipment
- **3.6** Vlastní pole na Sales/Purchase Header/Line — kompletní rozšíření (+ 3.6b–3.6h)
- **3.6i** Report dokladu pro tělo emailu z vlastního kódu archivuje podruhé (`Mail Management` bind)

## 3. Event Subscribery — propagace polí (3.5–3.6f)

### 3.5 Propagace vlastního pole přes Sales posting + Warehouse Shipment

Typický zákaznický pattern: vlastní pole na Sales Line se musí propsat do
Item Ledger Entry a/nebo Warehouse Shipment Line.

**Sales Line → Item Journal Line (při účtování)** — event v `Sales-Post`
(Codeunit 80):

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnPostItemJnlLineOnAfterPrepareItemJnlLine, '', false, false)]
local procedure SalesPost_OnPostItemJnlLineOnAfterPrepareItemJnlLine(var ItemJournalLine: Record "Item Journal Line"; SalesLine: Record "Sales Line")
begin
    if ItemJournalLine.IsTemporary() then
        exit;
    ItemJournalLine."My Field" := SalesLine."My Field";
end;
```

**Item Journal Line → Item Ledger Entry (při účtování)** — event v
`Item Jnl.-Post Line` (Codeunit 22):

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", OnAfterInitItemLedgEntry, '', false, false)]
local procedure ItemJnlPostLine_OnAfterInitItemLedgEntry(var NewItemLedgEntry: Record "Item Ledger Entry"; var ItemJournalLine: Record "Item Journal Line"; var ItemLedgEntryNo: Integer)
begin
    if NewItemLedgEntry.IsTemporary() then
        exit;
    NewItemLedgEntry."My Field" := ItemJournalLine."My Field";
end;
```

**Sales Line → Warehouse Shipment Line (při vytváření shipmentu)** — event v
`Sales Warehouse Mgt.` (Codeunit 5991):

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales Warehouse Mgt.", OnAfterCreateShptLineFromSalesLine, '', false, false)]
local procedure SalesWarehouseMgt_OnAfterCreateShptLineFromSalesLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header")
begin
    WarehouseShipmentLine."My Field" := SalesLine."My Field";
    WarehouseShipmentLine.Modify(false);
end;
```

> **Proč NE `OnAfterCreateShptLine` v `Whse.-Create Source Document` (Codeunit 5750)?**
> Signature: `OnAfterCreateShptLine(var WarehouseShipmentLine)` — Sales Line
> tam **není jako parametr**. Musel bys Sales Line dohledávat z DB přes
> Source Type/No./Line No. — zbytečně složité.
> `OnAfterCreateShptLineFromSalesLine` má přímo `SalesLine` i
> `WarehouseShipmentLine` jako parametry.

**Poznámky:**

- `Modify(false)` u Warehouse Shipment Line je nutné — `OnAfterCreateShptLineFromSalesLine`
  se volá **po** Insert()
- Codeunit s těmito subscribery: `EventSubscriberInstance = StaticAutomatic`
- Stejný pattern funguje analogicky pro Purchase Line → Purchase Receipt
  (`OnAfterPurchRcptLineInsert`, …) a Purchase Line → Warehouse Receipt Line
  (události v `Whse.-Create Source Document` nebo `Purch. Warehouse Mgt.`)

### 3.6 Vlastní pole na Sales/Purchase Header/Line — kompletní rozšíření

Když přidáš vlastní pole na `Sales Header` nebo `Sales Line` (případně
`Purchase Header` / `Purchase Line`), **nezapomeň ho rozšířit i na archive a
posted dokumenty** — jinak se data ztratí ve chvíli, kdy se dokument
zaarchivuje nebo zaúčtuje.

#### Sady tabulek, které musíš pokrýt

**Sales — header:**

- `Sales Header` (36) — zdroj
- `Sales Header Archive` (5107) — archive při Release/Reopen/Delete
- `Sales Invoice Header` (112) — posted invoice
- `Sales Cr.Memo Header` (114) — posted credit memo
- `Sales Shipment Header` (110) — posted shipment
- `Return Receipt Header` (6660) — posted return receipt

**Sales — line:**

- `Sales Line` (37) — zdroj
- `Sales Line Archive` (5108)
- `Sales Invoice Line` (113)
- `Sales Cr.Memo Line` (115)
- `Sales Shipment Line` (111)
- `Return Receipt Line` (6661)

**Purchase — header:**

- `Purchase Header` (38)
- `Purchase Header Archive` (5109)
- `Purch. Inv. Header` (122)
- `Purch. Cr. Memo Hdr.` (124)
- `Purch. Rcpt. Header` (120)
- `Return Shipment Header` (6650)

**Purchase — line:**

- `Purchase Line` (39)
- `Purchase Line Archive` (5110)
- `Purch. Inv. Line` (123)
- `Purch. Cr. Memo Line` (125)
- `Purch. Rcpt. Line` (121)
- `Return Shipment Line` (6651)

> **Tip:** Stejné field ID použij ve **všech** tabulkách dané sady — kód
> propagace pak může být šablonový (kopírovat field-by-field bez mapování).

> **⚠️ `AutoFormatExpression` u Decimal polí na posted řádcích:** `Sales Invoice Line` a `Sales Cr.Memo
> Line` **nemají pole `Currency Code`** (žije na hlavičce) — `AutoFormatExpression = Rec."Currency Code"`
> v tableextension skončí `AL0132`. Base vzor je `AutoFormatExpression = Rec.GetCurrencyCode();`
> (procedura na obou tabulkách). `Sales Line`, `Sales Line Archive`, `Sales Shipment Line` a `Return
> Receipt Line` `Currency Code` mají. (2026-09-04, cust-alumistr-bc, SK ceny na řádcích)

#### Propagace probíhá automaticky přes `TransferFields` — ale **jen pokud existuje pole se stejným ID a typem**

Standardní BC posting / archiving rutiny používají `TransferFields` mezi
zdrojovou a cílovou tabulkou:

- **Sales-Post** → `SalesShptLine.TransferFields(SalesLine)`,
  `SalesInvoiceLine.TransferFields(SalesLine)`, …
- **ArchiveManagement** → `SalesHeaderArchive.TransferFields(SalesHeader)`, …

`TransferFields` zkopíruje všechna pole, kde **field number sedí a typ je
kompatibilní**. Takže **stačí přidat field ve všech tabulkách sady se stejným
ID a typem — žádný subscriber není potřeba**.

```al
// Sales Header ZLK
field(52340; "My Custom Field ZLK"; Code[20]) { Caption = '...'; ... }

// Sales Header Archive ZLK
field(52340; "My Custom Field ZLK"; Code[20]) { Caption = '...'; ... }

// Sales Invoice Header ZLK
field(52340; "My Custom Field ZLK"; Code[20]) { Caption = '...'; ... }

// Sales Cr.Memo Header ZLK, Sales Shipment Header ZLK, Return Receipt Header ZLK
// — totéž
```

Po deployi: nová Sales Header s vyplněným polem → po Post se hodnota objeví
v Sales Invoice Header / Sales Shipment Header automaticky. **Bez subscriberu.**

#### Kdy přidat subscriber navíc

**Pozor na vlastní celkovou částku řádku při částečném účtování.** Shodné ID
zajistí kopii hodnoty, ale nepřepočítá ji na účtované množství. V BC 28.3
`Sales Invoice Line.InitFromSalesLine` po `TransferFields(SalesLine)` přiřadí
`Quantity := SalesLine."Qty. to Invoice"`; `Sales Shipment Line` obdobně
`Quantity := SalesLine."Qty. to Ship"`. Vlastní `Total = Quantity × Unit Price`
tak zůstane za CELÝ zdrojový řádek (10 × 132 = 1320 i při dodání 3 kusů).
Jednotkovou cenu přenes 1:1, celkovou částku dopočítej v tabulkovém
`OnAfterInitFromSalesLine` z cílového Quantity a zaokrouhlení měny — event je
na **všech čtyřech** posted line tabulkách, ale s **různým pořadím parametrů**
(ověřeno ve zdrojích 28.3): `Sales Invoice Line` / `Sales Cr.Memo Line`
`(var Line, Header, SalesLine)`, `Sales Shipment Line` / `Return Receipt Line`
`(Header, SalesLine, var Line)`; al-mcp u všech hlásí `ByReference: false`
(5.y v `bc-al-objects.md`). Invoice/Cr.Memo Line nemají `Currency Code` → měnu
ber ze `SalesLine`. **Storno dodávky / příjemky vratky** (`Undo Sales Shipment
Line.InsertNewShipmentLine`, `Undo Return Receipt Line.InsertNewReceiptLine`)
dělá `NewLine.Copy(OldLine)` + `Quantity := -Old.Quantity` → vlastní total
zůstane kladný u záporného množství; otoč znaménko v
`OnBeforeNewSalesShptLineInsert(var New, Old)` / `OnBeforeNewReturnRcptLineInsert`.
Test musí zahrnout částečné účtování (order i return order) a undo; plná
fakturace tuhle chybu neodhalí. (2026-09-07, cust-alumistr-bc 65916, code
review; implementace `SK Branch Mgt. ALU`, zdroje Base Application 28.3.52162.53506.)

Subscriber typu `OnAfterTransferFields` (nebo `OnBeforeInsertEvent` na cílové
tabulce) potřebuješ jen v těchto případech:

- **Mapping** — chceš pole `A` na zdroji do pole `B` na cíli (jiný název /
  jiný typ / dopočet hodnoty)
- **Field je na zdroji `FlowField`** — `TransferFields` ho neumí přenést,
  musíš ho v subscriberu spočítat (`CalcFields`) a uložit ručně do non-flow
  pole na cíli
- **Cíl má jiné pole číslo** než zdroj (legacy, špatný design — radši to
  nedělej, ale občas to nejde jinak)
- **Zdroj nemá pole vůbec** a hodnota se odvozuje z jiné tabulky

Příklad subscriberu pro Sales Line → Sales Invoice Line, když je zdrojové
pole FlowField:

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnAfterSalesInvLineInsert, '', false, false)]
local procedure SalesPost_OnAfterSalesInvLineInsert(var SalesInvLine: Record "Sales Invoice Line"; SalesLine: Record "Sales Line")
begin
    if SalesInvLine.IsTemporary() then
        exit;
    SalesLine.CalcFields("My FlowField ZLK");
    SalesInvLine."My Snapshot ZLK" := SalesLine."My FlowField ZLK";
    SalesInvLine.Modify(false);
end;
```

#### Page rozšíření = stejná hra

Když pole zobrazuješ na `Sales Order` page, většinou ho chceš vidět i na
`Posted Sales Invoice`, `Posted Sales Shipment`, `Sales Order Archive`.
Přidej `pageextension` na všechny příslušné posted/archive stránky se stejnou
field group / area umístěním.

#### Rychlý checklist před commitem nového pole

Když přidáváš pole na `Sales Header`/`Sales Line` (nebo Purchase ekvivalent):

- [ ] Field na zdrojové tabulce
- [ ] Field na archive tabulce (stejné ID, stejný typ)
- [ ] Field na všech 4 posted tabulkách (Invoice, CrMemo, Shipment/Receipt,
      Return Receipt/Shipment) — header i line dle toho, kam pole patří
- [ ] Page extension na zdrojové page
- [ ] Page extension na archive page (`Sales Order Archive`,
      `Posted Purchase Invoice`, …)
- [ ] Page extension na všech posted page (`Posted Sales Invoice`,
      `Posted Sales Shipment`, `Posted Sales Credit Memo`, …)
- [ ] Pokud zdroj je FlowField → subscriber na `OnAfter...Insert` cílové tabulky
- [ ] Description property u všech nových tableextension / pageextension
      (sekce 1.4 v `bc-al-style.md`)
- [ ] Test: vytvoř doc → vyplň pole → Post → ověř hodnotu na posted dokumentu

### 3.6b Sales Line `Validate("No.")` dělá `Init()` → vlastní pole se tiše ztratí v base cestách, které No. znovu validují

`Sales Line."No."` OnValidate (BC 28.3, `SalesLine.Table.al` ř. ~70) dělá `TempSalesLine := Rec; Init();`
a pak plní pole znovu ze zboží → **všechna extension pole na řádku se vynulují**. Stejné ID polí na
posted/archive tabulkách (3.6) tenhle problém neřeší, protože jde o cesty, kde base po
`TransferFields`/přiřazení recordu ještě zavolá `Validate("No.")`:

| Cesta                                              | Kde                                                                                  | Hook pro obnovu vlastních polí                                                                              |
| -------------------------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| **Restore z archivu**                              | `ArchiveManagement.RestoreSalesLines`: `TransferFields(Archive)` + `Insert` + `Validate("No.")` + Validate Variant/UoM/Qty/Unit Price | `OnAfterTransferFromArchToSalesLine(var SalesLine; var SalesLineArchive)` — běží po validacích, před `Modify(true)`; prosté přiřazení z archivu |
| **Copy Document s Recalculate Lines**              | `Copy Document Mgt.CopySalesDocLine`: `ToSalesLine.Init()` + `Validate("No.")` + `Validate(UoM)` (bez recalc je `ToSalesLine := FromSalesLine` → OK) | `OnBeforeInsertToSalesLine(var ToSalesLine; var FromSalesLine; FromDocType; RecalcLines; …)` — kopírovat jen když `RecalculateLines` |
| **RecreateSalesLines** (změna Sell-to apod.)       | `Sales Header.CreateSalesLine`: Validate Type/No./UoM/Variant/Qty                    | `OnBeforeSalesLineInsert(var SalesLine; var TempSalesLine; SalesHeader)` — Temp nese původní hodnoty         |

Cesty, které jsou OK bez subscriberu: Quote → Order, Blanket → Order, Get Shipment Lines, Get Posted Doc Lines to
Reverse, Undo Shipment (přiřazení recordu / `TransferFields` z posted). Sdílený helper `Reapply<Fields>(var SalesLine; …)`
pro všechny tři subscribery. Pole odvozená z Item UoM se reverse-fillem „obnoví" sama, ale pole typu kód/varianta ne.
(2026-08-31, prod-epb-pricingMatrix-bc plán 65842 — archive restore ztrácel `Sales Price Var. Code PMEBS`.)

**`RecreateSalesLines` (změna Sell-to / Bill-to / Currency…) nejdřív udělá `Modify()` hlavičky** (BC 28
`SalesHeader.Table.al`, hned po potvrzení `RecreateSalesLinesMsg`) a teprve pak řádky znovu vytvoří přes
`CreateSalesLine`: `Validate(Type)` → `Validate("No.")` → `GetUnitCost` → `Validate("Unit Cost (LCY)")` → UoM →
Variant → `Validate(Quantity)`. Subscriber na řádku, který si hlavičku čte z DB (`SalesHeader.Get`), tedy vidí už
**nového** plátce — cenotvorba závislá na hlavičce se při přepnutí plátce na existujících řádcích spočítá sama; ručně
zadané hodnoty na řádku ale projdou Init a je třeba je vrátit z `TempSalesLine` v `OnBeforeSalesLineInsert`.
Code-review nález „změna Bill-to nechá na řádcích starou cenu" je proto planý, dokud přepočet visí na `Unit Cost (LCY)`
/ `OnAfterUpdateUnitPrice`. Signatura Copy Document hooku: `OnBeforeInsertToSalesLine(var ToSalesLine; var FromSalesLine;
FromDocType: Option; RecalcLines: Boolean; var ToSalesHeader; DocLineNo: Integer; var NextLineNo: Integer;
RecalculateAmount: Boolean; var IsHandled: Boolean)`. (2026-09-15, cust-alumistr-bc 65916 code review.)

**Totéž dělá `Validate(Type)`** (BC 28.3 `SalesLine.Table.al`, field 5 OnValidate: `TempSalesLine := Rec; Init();`
a zpět jen Type, System-Created Entry, Currency Code) → přepnutí řádku Item → G/L Account / Resource z UI vynuluje
vlastní pole samo. Code-review nález „změna typu nechá viset staré vlastní ceny" je tedy u UI cesty teoretický; přímé
přiřazení `Type`/`No.` z kódu Init nespustí, proto guard `Type <> Item or No. = '' → Clear` v přepočtu stejně drž
(levné, chování pak nezávisí na base Init). (2026-09-10, cust-alumistr-bc 65916, `SK Branch Mgt. ALU`.)

**`Validate("Unit of Measure Code")` a `Validate("Variant Code")` na Sales Line PŘEPÍŠOU `Description` i `Description 2`.** Oba triggery volají
`Item Reference Management.EnterSalesItemReference`, který u řádku zboží znovu naplní texty z Item Reference / Item Variant / Item
(+ `GetItemTranslation`) — ověřeno v Base App 28.4. Vlastní texty (z konfigurátoru, importu…) proto přiřazuj **až po** validaci
varianty a MJ, jinak tiše zmizí; když má vlastní text stejnou hodnotu jako popis zboží, bug se maskuje a projeví se jen na `Description 2`.
Totéž nepřímo přes **EPB Pricing Matrix**: `Validate("Parameter A/B PMEBS")` dohledá matricovou MJ a sám zavolá `Validate("Unit of Measure Code")`
→ subscriber, který parametry validuje až po nastavení textů, texty smaže. Vzor: texty před validací uložit a po ní vrátit
(`ValidateParametersKeepingTexts` v cust-alumistr-bc `Configurator Events COALU`).
(2026-09-13, prod-ess-configurator-bc `SL Action Cond. Mgt.InitNewSalesLineFromAction` + COALU — Popis 2 z akčního řádku se ztrácel u řádků s MJ / s parametry.)

**`Unit Cost (LCY)` na Sales Line resetuje `GetUnitCost()` z VÍC polí, než čekáš** (BC 28 `SalesLine.Table.al`): `No.` (přes `CopyFromItem`),
**`Location Code`**, `Variant Code`, `Unit of Measure Code`, `Quantity` (jen standardní metoda ocenění při změně znaménka) a `Return Reason Code`
(+ nepřímo každá cesta, která validuje MJ — EPB Pricing Matrix přes Parametr A/B). Vlastní pořizovací cena pověšená na `modify(<pole>)
OnAfterValidate` tří polí (No./Variant/UoM) tak tiše zmizí po změně lokace. **Hook patří na `Sales Line.OnAfterGetUnitCost(var SalesLine; Item)`**
(volá se na konci `GetUnitCost`, po `ValidateUnitCostLCYOnGetUnitCost`) — jedno místo pro všechny cesty; v něm `Validate("Unit Cost (LCY)", …)`
je bezpečné (base totéž dělá sám, kontrola standardní metody ocenění v OnValidate běží jen při `CurrFieldNo = Unit Cost (LCY)`), `IsTemporary`
exit. Pozor na **jinou appku s vlastním hookem na `No.`**, která zapisuje i nulu: po zadání zboží přepíše hodnotu z karty, takže test nesmí
assertovat náklad hned po `CreateSalesLine`, jen po validaci pole, které hlídáš. (2026-09-25, cust-alumistr-bc PBI 66389.)

**Vlastní `Unit Price` jen na `OnAfterUpdateUnitPrice` nestačí — přepočet ceny se plánuje jen při ZMĚNĚ pole.** `UpdateUnitPriceByField(FieldNo)`
vyvolá cenovou kalkulaci i `OnAfterUpdateUnitPrice` jen když `IsPriceCalcCalledByField` (= pole si ji naplánovalo `PlanPriceCalcByField`),
a `Variant Code` / `Unit of Measure Code` ji plánují jen `if <pole> <> xRec.<pole>`. `GetUnitCost()` ale běží vždy. Kdo validuje pole se
**stejnou hodnotou** (typicky po `Get` záznamu, kam už hodnotu zapsal přiřazením — konfigurátor `SL Action Cond. Mgt. COEBS.ApplyCurrentLineOverrides`
s variantou z dialogu), dostane přepočtenou pořizovací cenu, ale jednotková zůstane stará. Cenu z vlastního výpočtu proto nastavuj **i
v `OnAfterGetUnitCost`** (a v `OnAfterUpdateUnitPrice` kvůli přepočtům bez `GetUnitCost` — množství, zákazník, měna). Test: přiřaď pole +
`Modify(false)`, `Get`, `Validate` se stejnou hodnotou, assert ceny. (2026-09-25, cust-alumistr-bc BC-TEST2 PO2500211.)
⚠️ Vlastní cena v `OnAfterUpdateUnitPrice` / `OnAfterGetUnitCost` obchází **ochranné větve `UpdateUnitPriceByField`** (w1-28): řádek z rámcovky
dostane cenu rámcovky (`BlanketOrderIsRelated` → `CopyUnitPriceAndLineDiscountPct`), dobropisový doklad s `Copied From Posted Doc.` drží
fakturovanou cenu (`CalcUnitPriceUsingUOMCoef`). `BlanketOrderIsRelated` je `internal` → guard sám: `"Blanket Order Line No." <> 0` a
`"Copied From Posted Doc." and IsCreditDocType()` (public) → exit. (Code review cust-alumistr-bc 66389, 2026-09-29.)

**Bonus — `fieldgroups` z tableextension:** `fieldgroups { addlast(DropDown; "My Field") }` v tableextension funguje
(vzor base app `ReturnReasonExt.TableExt.al`) — nejlevnější způsob, jak vlastní atribut ukázat ve všech lookupech
(např. Item UoM dropdown na Sales/Req./Price řádcích místo holého kódu).

### 3.6c Blob pole na Sales Header → posted/archiv se přes `TransferFields` NEpřenese bez `CalcFields`; délky Text polí drž na celé sadě stejné (LC0044)

- **Blob je lazy** — v bufferu recordu je jen po `CalcFields`. `TransferFields` /
  `InitFromSalesHeader` proto nenačtený Blob **tiše nepřenese** (posted doklad má prázdný
  Blob, žádná chyba). Base app to u `Work Description` dělá explicitně:
  `SalesHeader.CalcFields("Work Description"); SalesOrderHeader."Work Description" := SalesHeader."Work Description";`
  (codeunit Sales-Quote to Order, `CreateSalesHeader`; stejně Sales-Post, Copy Document,
  Archive). Vlastní Blob pole na Sales Header tedy = subscriber na **každém** přenosu:
  faktura, dodávka, dobropis, vratka, archiv + obnova, nabídka → objednávka, kopie dokladu
  (Blob := Blob přiřazení mezi recordy funguje, jen zdroj napřed `CalcFields`). `Text[n]` tohle
  nepotřebuje — přenese se sám (3.6).
- **Stejné vlastní pole s jiným typem/délkou napříč Sales Header vs. posted/archive tabulkami**
  (`Comment 1 ZLK` `Text[2048]` na Sales Header, `Text[250]` na Invoice/Shipment/Cr.Memo/
  Return Receipt/Archive) hlásí LinterCop **`LC0044` „Conflicting ID, Name or Type with Table
  X"** na všech dotčených tableextensions (warning → Essence CI fail) a při postingu delšího
  textu hrozí overflow. Délku rozšiřuj vždy na celé sadě tabulek (checklist 3.6).

(2026-09-02, cust-zlomek-bc — rich text prototyp `Comment 2 ZLK`.)

**Kam se zavěsit (BC 28, ověřeno ve zdrojích w1-28 a zkompilováno):**

| Přenos | Event | Stačí |
|---|---|---|
| Účtování → dodávka / faktura / dobropis / příjemka vratky | `Sales-Post.OnInsertShipmentHeaderOnBeforeTransferfieldsToSalesShptHeader`, `OnInsertInvoiceHeaderOnBeforeSalesInvHeaderTransferFields`, `OnInsertCrMemoHeaderOnBeforeSalesCrMemoHeaderTransferFields`, `OnInsertReturnReceiptHeaderOnBeforeReturnReceiptHeaderTransferFields` — všechny `(var SalesHeader)` těsně před `TransferFields` | jen `SalesHeader.CalcFields(<Bloby>)`, přenos udělá base (stejná ID) |
| Archivace | `ArchiveManagement.OnBeforeSalesHeaderArchiveInsert(var Archive, SalesHeader)` (před `Insert`) | přiřazení Blobů |
| Obnova z archivu | `ArchiveManagement.OnAfterTransferFromArchToSalesHeader(var SalesHeader, var Archive)` (za ním `Modify(true)`) | přiřazení |
| Nabídka → objednávka | `Sales-Quote to Order.OnBeforeModifySalesOrderHeader(var Order, Quote)` (base tam přiřazuje `Work Description`) | přiřazení |
| Kopie dokladu | **jeden** `Copy Document Mgt.OnAfterCopySalesHeaderDone(var ToSalesHeader, Old, FromSalesHeader, FromShpt, FromInv, FromRetRcpt, FromCrMemo, FromArchive, FromDocType)` pro všechny zdroje (volá se jen s `IncludeHeader`, za ním `Modify`) | `case FromDocType` → přiřazení ze správného zdroje |

Base u příjemky vratky `Work Description` ani nekalkuluje (w1-28) — vlastní subscriber tam přesto dej. Generické
kopírování mezi různými tabulkami: `Temp Blob.FromRecord(FromVariant, FieldNo)` (sám udělá `CalcField`) →
`Temp Blob.ToRecordRef(ToRecRef, FieldNo)` → `ToRecRef.SetTable(ToRec)`. (2026-09-29, cust-zlomek-bc PBI 65651,
`Sales Comment Mgt. ZLK`.)

### 3.6e Guard na page `OnModifyRecord` nestav na diffu `Rec` vs `xRec` — hlídej invarianty

Page trigger `OnModifyRecord` dostane **spolehlivý `xRec` jen z reálného UI vstupu**. Guard
napsaný jako „co se změnilo" (`if Rec.Pole <> xRec.Pole then Error`) proto **tiše propustí**:

- programovou změnu záznamu (`Rec.Modify` z kódu, integrace, import) — tam je `xRec = Rec`
  (viz 3.9 v `bc-al-data.md`),
- **`TestPage`** — negativní test spadne na „An error was expected inside an ASSERTERROR
  statement.", protože se nic nedetekovalo (ověřeno na třech různých variantách testu: samotný
  `SetValue`, `SetValue` + `Next()`, i s druhým řádkem a `Last()`/`First()`).

**Pravidlo:** guard piš jako **invarianty záznamu** („co musí platit"), ne jako diff:

```al
// místo: if Rec."Variant Code" <> xRec."Variant Code" then Error(...)
if not IsVoucherLine(SalesLine) then exit;
SalesLine.TestField("Variant Code");                     // nesmí být prázdný
if (SalesLine.Quantity <> 1) and (SalesLine.Quantity <> -1) then Error(QtyErr, …);
if (SalesLine."Line Discount %" <> 0) or (SalesLine."Line Discount Amount" <> 0) then Error(…);
```

Invarianty se navíc dají **testovat přímo** (`asserterror Mgt.CheckLine(SalesLine)`) bez TestPage
a platí i pro cesty, kam page trigger nedosáhne. Hodnoty, které se legitimně mění (Qty. to Ship /
Invoice, data, texty), do invariantů nedávej — tím zůstane doklad normálně použitelný.
Diff proti `xRec` si nech jen tam, kde opravdu jde o „uživatel přepsal ručně zadanou hodnotu",
a počítej s tím, že z kódu ani z testu to nezabere. (2026-09-15, cust-sonnentor-bc,
`CheckVoucherLineModify` na Sales Order Subform, buildy 28270–28273.)

### 3.6d Kontrola dokladu před účtováním: `OnBeforeIsApprovedForPosting` platí JEN pro účtování z UI

`Sales Header.OnBeforeIsApprovedForPosting` (a `Purchase Header` ekvivalent) vyvolává
**`Sales-Post (Yes/No)`**, tedy cesta „uživatel klikne Účtovat". **`Sales-Post.Run` sám ho
nevolá** — takže kontrola zavěšená na tomhle eventu **neplatí** pro:

- programové účtování z kódu a integrací (`SalesPost.Run(SalesHeader)`),
- importy a job queue,
- **testy** (`LibrarySales.PostSalesDocument` jde přes `Sales-Post` přímo).

Příznak v testech je zákeřný: negativní test `asserterror LibrarySales.PostSalesDocument(...)`
spadne na **„An error was expected inside an ASSERTERROR statement."** — doklad se zaúčtoval,
protože kontrola vůbec neproběhla. Vypadá to jako chyba testu, ale je to díra v produkčním kódu:
přes API / integraci projde i doklad, který by uživatel z UI nezaúčtoval.

**Správné místo pro kontrolu celého dokladu, která má platit vždy: `Codeunit "Sales-Post"`
`OnAfterCheckSalesDoc`** — běží po standardních kontrolách v každé cestě účtování.
Signatura (BC 28.4): `(var SalesHeader; CommitIsSuppressed: Boolean; WhseShip: Boolean;
WhseReceive: Boolean; PreviewMode: Boolean; ErrorMessageMgt: Codeunit "Error Message Management")`;
nepoužité parametry se v subscriberu smí vynechat. Alternativa na samý začátek je
`OnBeforePostSalesDoc`. UI subscriber si klidně nech vedle (chyba pak přijde dřív, před
zahájením účtování) — read-only kontrola dvakrát nic nezkazí; počítej ale s tím, že nový
subscriber běží na **každém** prodejním dokladu, takže z něj rychle vyskoč, když se ho netýká.

**Pozor na `var` u parametru subscriberu:** al-mcp hlásí u těchhle eventů `ByReference: false`
i tam, kde publisher má `var` (5.y v `bc-al-objects.md`) — ze symbolů to tedy nepoznáš.
Chybějící `var` chytí ALCops **`PC0010`** („Parameter must use the 'var' keyword if the publisher
parameter is 'var'"), takže lokální build s ALCops to řekne za tebe.

(2026-09-15, cust-sonnentor-bc build 28271 — kontrola plné hodnoty uplatněného poukazu
visela na `OnBeforeIsApprovedForPosting` a při programovém účtování se nespustila.)

### 3.6f Fakturace dodaného řádku: `Sales-Post.CheckJobNoOnShptLineEqualToSales` porovnává Job No. dodávky a řádku — doplnění Job No. až při účtování faktury spadne

`PostSalesLine` (BC 28) volá v tomhle pořadí: `OnPostSalesLineOnBeforeTestUnitOfMeasureCode` → `OnPostSalesLineOnBeforeUpdateSalesLineBeforePost`
→ `UpdateSalesLineBeforePost` → `PostItemLine` → `PostItemTracking` → `PostItemTrackingForShipment`, kde se pro každý dodaný, nevyfakturovaný
řádek dodávky testuje `SalesShptLine.TestField("Sell-to Customer No." / Type / "No." / Gen. Bus. / Gen. Prod. / **"Job No."** / UoM / Variant, SalesLine.X)`.
Job No. má vlastní wrapper `CheckJobNoOnShptLineEqualToSales` s hookem **`OnBeforeCheckJobNoOnShptLineEqualToSales(SalesShipmentLine, SalesLine,
var IsHandled)`**; celý blok testů jde vypnout přes `OnPostItemTrackingForShipmentOnBeforeTestLineFields`. U vratek (`Return Receipt Line`) je
analogický `TestField("Job No.")` v `CheckReturnRcptLine` s hookem `OnBeforeCheckReturnRcptLine`.

Past: řádek objednávky vygenerovaný z Job Planning Line (IMEBS `GenerateSalesOrderJobLines`) nese jen `Job Contract Entry No.`, Job No. má prázdné
(standard ho na objednávce vyžaduje prázdné — `TestField("Job No.", '')` v `PostSalesLine` pro Order). Dodávka tedy vznikne s **prázdným Job No.**
Faktura přes Get Shipment Lines (`InsertInvLineFromShptLine`: `SalesLine := SalesOrderLine`) zdědí prázdné Job No. + kontrakt. Když pak subscriber
na `OnPostSalesLineOnBeforeUpdateSalesLineBeforePost` (IMEBS `Project Item Management`, commit 1350b6f 2026-09-17 — kvůli `PostJobContractLine`
`TestField("Job No.")` u dobropisů z Correct/Cancel) doplní Job No. z planning line na fakturační řádek, běží to **před** `PostItemLine`, a
`TestField("Job No.", SalesLine."Job No.")` na dodávce spadne („Job No. must be equal to 'X' in Sales Shipment Line … Current value is ''"), debugger
ukazuje `Sales-Post.dal:8331`. Totéž pro `Skip Purchase Consumption` projekty přes starší subscriber `OnPostSalesLineOnBeforeTestUnitOfMeasureCode`.
Řešení: buď Job No. doplňovat až po item postingu (např. `OnAfterPostItemLine` / těsně před `PostJobContractLine`), nebo v
`OnBeforeCheckJobNoOnShptLineEqualToSales` nastavit `IsHandled`, když má dodávka prázdné Job No. a stejné `Job Contract Entry No.` jako řádek
(Sales Shipment Line to pole má). Zachyceno 2026-09-22, cust-soitron-bc (Sales Aggregation, částečná dodávka → faktura z Get Shipment Lines).

**Opraveno v prod-ep-itemManagement-bc (2026-09-22, `Project Item Management IMEBS`; bypass 2026-09-25 zakomentován — appka je ve vývoji,
testovací doklady se založí znovu a nové dodávky Job No. nesou, takže standardní kontrola projde sama):** druhá varianta — subscriber
`OnBeforeCheckJobNoOnShptLineEqualToSales` nastaví `IsHandled`, jen když dodávka má prázdné Job No., shodné nenulové
`Job Contract Entry No.` s fakturačním řádkem **a** Job No. řádku = Job No. planning line s tím kontraktem (= hodnota, kterou
subscriber sám doplnil; ručně přepsaný jiný projekt standardní kontrola dál chytí). `IsHandled` u `OnBeforeCheckReturnRcptLine`
by naopak vypnul **všechny** `TestField` na řádku příjemky vratky (hook je před celým blokem), takže vratky zatím bez zásahu —
opravný dobropis z Correct/Cancel `Return Receipt No.` nemá a tou kontrolou neprochází. Test bez UI: `Sales-Get Shipment`
`SetSalesHeader(InvoiceHeader)` + `CreateInvLines(SalesShptLine s filtrem Document No.)` (`LibrarySales.GetShipmentLines`
otevírá výběrovou stránku); test `InvoiceFromShipmentLines_ShipmentLineWithBlankJobNo_PostsWithJobNoFromPlanningLine`
v `Job Sales Post Test IMEBS`. Test symboly 28.4 (`28.4.53241.53504`) z MSSymbols feedu proti Base App `28.4.53241.54031` — alc 17.0 čistě.
**`OnPostSalesLineOnBeforeTestUnitOfMeasureCode` se v BC 28 volá JEN pro `Type = Item`** (`PostSalesLine`: `if SalesLine.Type = Item then begin
… OnPostSalesLineOnBeforeTestUnitOfMeasureCode(…)`), zatímco `OnPostSalesLineOnBeforeUpdateSalesLineBeforePost` běží pro všechny typy. Subscriber
zavěšený na ten první (IMEBS Skip Purchase Consumption) tak doplní Job No. jen na řádky zboží → dodávka má u zboží Job No. vyplněné, u zdroje /
finančního účtu prázdné; při fakturaci z Get Shipment Lines pak padá právě řádek zdroje (zboží projde, hodnoty sedí). Zdroje procházejí
`PostItemTrackingForShipment` taky (`PostItemTrackingLine` běží před `case Type`), jen `PostItemJnlLine` je podmíněný `Type = Item`. Ověřeno v
w1-28 `SalesPost.Codeunit.al` (raw.githubusercontent, cesta `BaseApp/Source/Base Application/Sales/Posting/`).

**Job No. na prodejním řádku podle typu — co s ním standard při účtování dělá (BC 28, ověřeno ve zdrojích 2026-09-24):**
- **Resource:** `Res. Journal Line.CopyFromSalesLine` kopíruje Job No. → položka zdroje ho nese; `Res. Jnl.-Post Line` s ním nic dalšího nedělá.
  `PostJobContractLine` se u zdroje volá až z `PostResJnlLine` (přes `JobTaskSalesLine`), u Item / G/L / prázdného typu z `UpdateSalesLineBeforePost`.
- **G/L Account:** Job No. jde do `Invoice Posting Buffer` → `Gen. Journal Line` (`System-Created Entry = true` → `Job Post-Line.PostGenJnlLine` hned
  exituje, žádná duplicitní Usage položka) → `G/L Entry."Job No."`. **Past:** `Job Post-Line.PostJobOnSalesLine` u G/L řádku projektovou položku Sale
  NEúčtuje hned, jen ji odloží do `TempSalesLineJob`/`TempJobJournalLine`, a `Sales Post Invoice.PostLines` ji zaúčtuje jen
  `if TempInvoicePostingBuffer."Job No." <> ''` (`PostJobSalesLines` + vazba na G/L Entry No.). Řádek s `Job Contract Entry No.` a prázdným Job No.
  (objednávky z planning lines) tak Sale položku u finančního účtu **nikdy nevytvoří** — tiše. Doplnění Job No. před `UpdateSalesLineBeforePost`
  to opraví (IMEBS 2026-09-24: `SalesPost_OnPostSalesLineOnBeforeUpdateSalesLineBeforePostIMEBS` nově i pro Order a všechny typy, všechny projekty;
  skipy `OnBeforeTestSalesLineJob` / `OnPostSalesLineOnBeforeTestJobNo` rozšířeny na řádky, jejichž Job No. = projekt planning line kontraktu).
- **Item:** standard Job No. do deníku zboží nekopíruje (`Item Journal Line.CopyFromSalesLine` job pole nemá) → ILE/VE bez Job No., jen
  `IsCreatedFromJob` (Job No. + Task + kontrakt) vypne `GetUnitCost` u Standard costing při účtování.
- **Dodávka s Job No.:** `CheckItemChargePerShpt` dělá `TestField("Job No.", '')` → na takový řádek dodávky nejde přiřadit poplatek zboží
  (hook `OnPostItemChargePerShptOnBeforeTestJobNo`). Undo dodávky Job No. nekontroluje. `ArchiveRelatedJob` po účtování auto-archivuje projekt
  z prvního řádku s Job No.
- **Posted faktura s Job No. na řádku = pro `Correct Posted Sales Invoice` projektová faktura:** `SalesInvoiceLinesContainJob` →
  `CreateAndProcessJobPlanningLines` založí pro každý řádek dobropisu **nový reverzní Job Planning Line** (`InitFromJobPlanningLine(From,
  -Quantity)` + Job Planning Line Invoice typu Credit Memo) a řádek dobropisu naváže na jeho kontrakt, ne na původní. Test, který čeká původní
  `Job Contract Entry No.` na dobropisu, po doplnění Job No. na posted řádky spadne (build 28479, 2026-09-25).
- **Job Ledger Entry Sale při fakturaci z objednávky nese číslo objednávky:** `Job Transfer Line.FromPlanningSalesLineToJnlLine` bere
  `JobJnlLine."Document No." := SalesLine."Document No."` a `Sales-Post.PostJobContractLine` ho přepisuje na posted číslo jen u Invoice /
  Credit Memo; u Order (přes vlastní handler `OnBeforePostJobContractLine` + `PrepareJobLine`) zůstane číslo objednávky. Filtr testu na posted
  invoice no. → 0 záznamů. Množství Sale položky je záporné (`-Quantity`) u faktury i objednávky (`case Document Type` v Job Transfer Line
  Order nemá; IMEBS ho doplňuje `OnFromPlanningSalesLineToJnlLineOnBeforeInitAmounts` s `Qty. to Invoice`).
- Kontroly „Job No. musí být prázdné" na objednávce: `TestSalesLineJob` (hook `OnBeforeTestSalesLineJob`) a `PostSalesLine`
  (`OnPostSalesLineOnBeforeTestJobNo`); `Job Planning Line` dostává `Job Contract Entry No.` v OnInsert **vždy** (i budget řádky), takže filtr
  na kontrakt 0 nic nenajde. `LibraryJob.Job2SalesConsumableType(JPL.Type)` převádí typ planning line na `Sales Line Type` (Item=2 vs. job Item=1).

### 3.6g Vlastní kontrola „co se tímhle účtováním vyfakturuje" NESMÍ číst `Qty. to Invoice` z řádku — zrcadli `MaxQtyToInvoice`

`Sales Line."Qty. to Invoice"` na objednávce **zahrnuje i `Qty. to Ship`** (`InitQtyToInvoice` = Quantity Shipped + Qty. to Ship −
Quantity Invoiced; po každém zaúčtování dodávky se řádkům znovu nastaví `Qty. to Ship` = zbytek podle „Default Quantity to Ship" a
tím i plné `Qty. to Invoice`). Nedodaný řádek má tedy K fakturaci = celé množství. Teprve **Sales-Post** to v
`UpdateSalesLineBeforePost` srovná: bez `Ship` → `Qty. to Ship := 0`, bez `Receive` → `Return Qty. to Receive := 0`, faktura z dodávky
(`Shipment No. <> ''`) → `Quantity Shipped := Quantity`, dobropis z vratky obdobně, a pak `InitSalesLineQtyToInvoice`: když
`Abs(Qty. to Invoice) > Abs(MaxQtyToInvoice())`, ořízne na `MaxQtyToInvoice` (= Quantity Shipped + Qty. to Ship − Quantity Invoiced;
u vratek Return Qty. Received + Return Qty. to Receive − Quantity Invoiced; blanket Quantity − Invoiced; prepayment 1).
Důsledek: kontrola v `OnBeforePostSalesDoc` typu „řádek se fakturuje celý" napsaná jako `"Qty. to Invoice" = Quantity − "Quantity Invoiced"`
**projde** u objednávky účtované „jen fakturovat" po částečné dodávce, i když se z nedodaných řádků nevyfakturuje nic. Správně: spočítej
množství jako Sales-Post (upravit lokální kopii řádku podle příznaků hlavičky + `SalesLine.MaxQtyToInvoice()` je public) a teprve to
porovnej; pravidlo „všechno nebo nic" navíc vyhodnocuj **per skupina** (nejdřív zjisti, jestli se z ní vůbec něco fakturuje). Test:
ship jen část řádků → `PostSalesDocument(SalesHeader, false, true)` musí spadnout, po dodání všech řádků projít.
(2026-09-30, cust-soitron-bc `Sales Aggregation Mgt. SOI.CheckNoPartialInvoiceOnAggregatedLines`, zdroje w1-28.)

### 3.6h Subscriber na `Purch.-Post.OnPostPurchLineOnAfterPostByType` běží pro KAŽDÝ řádek a při každém typu účtování; Whse.-Post Receipt před ním commitne

- `PostPurchLine` volá `OnPostPurchLineOnAfterPostByType` pro všechny řádky dokladu bez ohledu na `Qty. to Receive` /
  `Qty. to Invoice` a bez ohledu na `PurchHeader.Receive/Invoice` (w1-28 `PurchPost.Codeunit.al` ř. ~1068; podmínka
  `"Qty. to Invoice" <> 0` je až ZA eventem). Vlastní kontrola „nákupní řádek sedí s řádkem plánování projektu" zavěšená
  sem proto padá i při **účtování skladové příjemky** (Receive only) na řádku, který v příjemce vůbec není (zdroj / finanční
  účet, `Qty. to Receive = 0`). Guard „jen když se z řádku něco fakturuje" (`PurchHeader.Invoice and "Qty. to Invoice" <> 0`)
  musí stát PŘED kontrolou, ne až v `case Document Type`.
- `Whse.-Post Receipt.Code` (w1-28 ř. 147–158): `InitSourceDocumentLines` (řádky NO v příjemce dostanou `Qty. to Receive` ze
  skladové příjemky, řádky mimo příjemku `Validate("Qty. to Receive", 0)`) → `InitSourceDocumentHeader` → **`Commit()`** →
  `PostSourceDocument`. Když účtování zdrojového dokladu spadne, rollback vrátí jen posting; **přepsaná `Qty. to Receive` /
  `Qty. to Invoice` na řádcích objednávky zůstanou** (uživatel vidí „prohozené" K příjmu / K fakturaci: řádek zboží najednou
  vyplněný, řádek zdroje prázdný). Není to poškození dat — další pokus o účtování příjemky je přepočítá znovu — ale
  v analýze chyby to nepovažuj za příčinu.
- Souvislost EPEBS: `Job Purch Invoice Track EPEBS.ValidatePurchaseRelationship` porovnává i `Location Code`, zatímco
  `Project Functions EPEBS.CreatePurchaseOrderLine` / `Job Purch Order Trans EPEBS` kopírují lokaci z JPL jen pro `Type = Item`
  (zdroj / G/L dostane lokaci hlavičky z `InitHeaderDefaults`, JPL ji má z Job Task přes `InitLocation`, 5.x18 v
  `bc-al-projects.md`) → řádek zdroje s odlišnou lokací padne při každém účtování.
  (2026-10-01, prod-ep-projectBase-bc, SK-TEST NO 1106260008 / skladová příjemka 5101260008.)
  **Oprava (2026-10-01, větev features/salesQuotes):** guard `"Qty. to Invoice" = 0 → exit` před `ValidatePurchaseRelationship`
  (Purch.-Post `UpdatePurchLineBeforePost` nuluje `Qty. to Invoice` při `not Invoice`, takže jeden test pokryje příjem i řádky
  bez množství) a lokace z JPL se při vzniku řádku NO kopíruje pro všechny typy (přihrádka dál jen Item — base `Bin Code`
  OnValidate má `TestField(Type, Item)`, což byl skutečný důvod původní podmínky `Type = Item`, lokace do ní spadla omylem).
  Testy: `PostOrder_ReceiveOnly_LinkedLineWithOtherLocation_PostsWithoutTracking`, `PostOrder_Invoice_…_RaisesFieldError`
  (`Job Purch Inv Track Test EPEBS`). Receive-only test se zdrojem funguje: `PostResJnlLine` se u příjmu nic neúčtuje.

### 3.6i Report dokladu spuštěný pro tělo emailu vlastním kódem archivuje podruhé — bez `BindSubscription(Mail Management)` to není „preview"

- Standardní reporty dokladů dělají side effects jen `if not IsReportInPreviewMode()`; u `Standard Sales - Quote` (1304, cz-28) je to
  archivace (`Archive Quotes` Always → `ArchSalesDocumentNoConfirm`, Question → `ArchiveSalesDocument` s dotazem), `Sales-Printed`
  (No. Printed +1) a log interakce v `OnPostReport`. Bez request page rozhoduje přímo setup (`<> Never`).
- `IsReportInPreviewMode()` = `CurrReport.Preview() or MailManagement.IsHandlingGetEmailBody()`. `Mail Management` (9520) je
  `EventSubscriberInstance = Manual` a true vrací jen při **bindnuté instanci**. Standard `Report Selections.SendEmailToCustDirectly` /
  `SendEmailToVendorDirectly` dělá `BindSubscription(MailManagement)` jen kolem generování těla emailu → tělo nic nearchivuje,
  archivuje jen běh pro PDF přílohu (1×).
- Vlastní kód, který tělo vyrábí sám (`Report.SaveAs(…, ReportFormat::Html, …)` s Word email layoutem) bez bindu → report bere běh jako
  ostrý tisk → **2 verze archivu na jeden email** (tělo + příloha, pár sekund po sobě; u Question i dva dotazy), No. Printed +2,
  2× interakce. Totéž hrozí u objednávek (`Archive Orders`) a každého reportu s `IsReportInPreviewMode`.
- Případ: prod-ess-documentEmail-bc `Send Email DEEBS.SaveReportAsHTML2DEEBS` (volá se ve smyčce příloh při `Use for Email Body` +
  `Email Body Layout Type = Custom Report Layout`, ignoruje tělo už vygenerované standardem). Navržená oprava (zatím neimplementovaná
  ani neověřená): `BindSubscription(MailManagement)` před `Report.SaveAs`, `UnbindSubscription` po, stejně jako standard.
- Diagnostika v BC: Archivy prodejních nabídek = page **9348** (9346 = nákupní poptávky), sloupce Datum/Čas archivace — dvojice
  verzí 2–4 s po sobě = dvojí běh reportu. (2026-10-05, Sonnentor BC-TEST: Výběr sestav Nabídka = 1304 s tělem i přílohou, `Archive
  Quotes` = Question; zdroje cz-28.0.46665.48549.)
