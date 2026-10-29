# BC/AL poznámky — Integrace & SaaS/Cloud gotchas

> Vyčleněno z `bc-al-objects.md` 2026-09-08 (5.y2 + sekce 11; původně část `bc-al-notes.md`, archiv
> `bc-al-notes.archived-2026-06-23.md`). Ostatní 5.x (No. Series, Item Tracking, Attached to Line No.…) zůstávají
> v `bc-al-objects.md`.
> Načítej, když řešíš: Shopify Connector (varianty, sync vs Add Item, eventy, userErrors), HttpClient na SaaS (Allow
> HttpClient Requests, Windows auth OnPrem-only), Isolated Storage scope, SecretText (Unwrap OnPrem-only,
> SecretStrSubstNo), notifikace do Power Automate (External Business Events preview vs API page + BC konektor).
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **5.y2** Shopify Connector (BC28) — variant sync (část sekce 5)
- **11.** SaaS gotchas — HttpClient, SecretText, Isolated Storage, Business Events / Power Automate, API page, Dataverse, Jira, Dotykačka (11.10)

## 5. Specifické objekty a API — integrace (jen 5.y2; zbytek sekce 5 v `bc-al-objects.md`)

### 5.y2 Shopify Connector (BC28) — variant sync: co jde a nejde eventovat

Poznatky z rozšiřování product/variant syncu (cust-sonnentor-bc, PBI 63076, 2026-08):

- **`Shpfy Variant`."Available For Sales" je BC-only mirror pole.** Export ho plní
  (`FillInProductVariantData`: z Item Blocked/Sales Blocked), ale **neposílá do Shopify**
  (není v update mutaci) a **neukládá lokálně**, pokud se nezměnilo žádné pole z mutace
  (HasChange). Import ho přepisuje z `availableForSale` (computed hodnota Shopify).
  Persist změny řeš subscriberem na `OnBeforeSendUpdateShopifyProductVariant(Shop,
  var ShopifyVariant, xShopifyVariant)` — xShopifyVariant je DB stav, fires pro každou
  variantu updatovaného produktu.
- **Export lokální `Shpfy Variant` záznamy nikdy nemaže** — maže je jen import
  (`Shpfy Product Import`.SetProduct), když varianta zmizela přímo v Shopify. Konektor
  neposílá žádné variant-delete mutace ani `productSet`.
- **Od BC28 export sync dovytváří chybějící varianty existujících produktů**
  (`Shpfy Product Export`.UpdateProductData, 2. smyčka přes Item Variant →
  `CreateProductVariant`). **Neexistuje IsHandled/cancel event** — vytvoření nejde z extension
  zablokovat: `OnBeforeSendAddShopifyProductVariant` je uvnitř skládání mutace (všechna pole
  if-guarded, poison-pill nejde), communication eventy (`OnClientSend`…) běží jen při
  `IsTestInProgress` (v BC 29 smazané úplně, viz 5.y4). Per-variant filtrování create path = jedině PR do microsoft/BCApps.
- **Filtrování variant při Add Item to Shopify** jde čistě: `OnAfterCreateTempShopifyProduct
  (Item, var TempProduct, var TempVariant, var TempTag)` — smaž nechtěné temp varianty
  (mark-and-delete přes List of [BigInteger], ne Delete v FindSet smyčce); při vyprázdnění
  setu resetni `TempProduct."Has Variants"` (zrcadlí standard při all-blocked variantách).
- **Internal eventy konektoru jdou subscribovat z jiné appky** — `Shpfy Product Events` má
  všechny publishery `internal procedure` + `[IntegrationEvent]`, subscription z per-tenant
  extension funguje (ověřeno nasazeným kódem; direct call by neprošel).
- Zdroják konektoru: **microsoft/BCApps**, `src/Apps/W1/Shopify/App/src/...`, branch
  `releases/<major>.<minor>` — před použitím eventu ověř, že existuje ve verzi z CI
  artifactu (`BC_ARTIFACT`), lokální `.alpackages` může být novější minor.
  Lokální rozcestník konektoru (DNEM, GitHub `Ronnie3697/BCShopifyConnectorDocs`, generovaný z microsoft/BCApps
  `releases/29.0`; stav 28.5 v historii repa, commit `b0db0b2`): `C:\WorkTasks\BCShopifyConnectorDocs`
  — `shopify_codeunits|tables|pages|reports.md` (ID → název → GitHub link), `shopify_functional_breakdown.md`,
  `VersionChanges/Changes27-28.md`, `Changes28.md` (minor diffy 28.x), `Changes28-29.md`, `Changes29.md`, update přes
  `python scratch/update_docs.py`.

- **Nové varianty existujícího produktu zakládá JEN produktový sync, ne Add Item to Shopify.**
  `Shpfy Create Product.OnRun` produkt pro dvojici Shop Code + Item SystemId tiše přeskočí, když už
  existuje (`ShopifyProduct.IsEmpty` guard; `ConfirmAddItemToShopify` navíc už namapované shopy
  z výběru vyřadí) — „přidám variantu a znovu kliknu Add Item" nikdy nic nepřidá. Chybějící varianty
  dovytváří `Shpfy Product Export.UpdateProductData` (2. smyčka přes Item Variant), a ta běží jen
  když shop má **`Sync Item = To Shopify`** a **`Can Update Shopify Products = true`** (pole je
  vzájemně výlučné se `Shopify Can Update Items` — OnValidate druhé shodí). Bez toho sync produkty
  vůbec nesáhne (výjimka: `Only Sync Price`, který ale varianty nezakládá — `CreateProductVariant`
  při `OnlyUpdatePrice` exitne). Export žádný filtr „změněno od posledního syncu" nemá — bere všechny
  `Shpfy Product` shopu s Item SystemId.
- **`productVariantsBulkCreate` s `userErrors` = tichý neúspěch.** `Communication Mgt.ExecuteGraphQL`
  vyhazuje `Error` jen na top-level `errors`; `userErrors` (chybějící option, duplicitní hodnota…) jen
  označí `Has Error` v `Shpfy Log Entry` (a to pouze při `Logging Mode` All / Error Only).
  `Variant API.AddProductVariant` pak vrátí false, `Shpfy Variant` se nezaloží, žádný Skipped Record,
  žádná chyba job queue. Diagnostika: page **Shopify Log Entries** (filtr Has Error) + **Shopify
  Skipped Records** (blokované zboží/varianty, Draft/Archived produkt).
- **Produkt založený bez options už varianty přes sync nedostane.** Item bez variant (nebo se všemi
  variantami odfiltrovanými/blokovanými) jde do `productCreate` bez `productOptions` → Shopify mu dá
  jedinou „Default Title" variantu. Pozdější `CreateProductVariant` posílá `optionValues
  [{optionName: "Variant"}]` na produkt, který option „Variant" nemá → userError → tiché nic.
  Konektor `productOptionsCreate` nevolá. Náprava jen ručně v Shopify adminu (přidat option) nebo
  smazat mapování a produkt nahrát znovu.
- ⚠️ **`Product API.CreateProduct` volá `ShopifyVariant.FindSet()` bez ošetření návratu** — prázdný
  temp set variant (všechny blokované / odfiltrované subscriberem `OnAfterCreateTempShopifyProduct`)
  = runtime error při Add Item to Shopify. Subscriber, který varianty z temp bufferu maže, musí
  nechat aspoň jednu, nebo produkt raději vůbec nezakládat (nejde — žádný IsHandled; jen Error
  s vysvětlením). (Analýza cust-sonnentor-bc 63089, 2026-09-02, konektor 28.3.52162.53601.)
- **Add to Shopify z karty zboží obchází report 30106** (pageext `Shpfy Item Card` → `Sync Products.AddItemToShopify`
  → `Create Product.Run(Item)`), takže reportextension filtr na `Item` dataitemu neplatí. Item-level kontrolu dej do
  subscriberu `OnAfterCreateTempShopifyProduct(Item, var TempProduct, var TempVariant, var TempTag)` — má shop
  (`TempProduct."Shop Code"`) i zboží, běží před `FindShopifyProductVariant` (HTTP) i `productCreate` a pokryje i veřejnou
  CU `Shpfy Product` (30234). `OnBeforeActionEvent` na akci karty nestačí: shop se vybírá až v dialogu uvnitř akce.
  Při prázdném bufferu variant (filtr / všechny blokované) radši `Error` — konektor jinak spadne na `FindSet()`, nebo
  založí produkt bez options („Default Title" past). (cust-sonnentor-bc 63089, 2026-09-03)
- **Pole `Option 1..3 Name/Value` na BC `Shpfy Variant` nejsou důkaz stavu v Shopify.** Export je při update přepisuje
  (`FillInProductVariantData` → `Option 1 Name := 'Variant'`, `Option 1 Value := Variant Code`) a `UpdateVariants` /
  TitleChanged uloží celý buffer do DB, jenže options v update mutaci nejsou → Shopify klidně drží `Title / Default Title`.
  Pravdu ukáže Shopify CSV export (`Option1 Name`) nebo `hasOnlyDefaultVariant`. Ruční oprava produktu bez options:
  admin → „Add options like size or color" → název přesně `Variant`, hodnota = Variant Code namapované varianty; další
  Synchronizace → Produkty zbylé varianty založí (ověřeno 2026-09-03 na dev shopu Sonnentor).
- **Import produktu (jediný zapisovatel `Has Variants = false`) běží i mimo `Sync Item = From Shopify`:** `Shpfy Order
  Mapping.MapVariant` při importu objednávky naimportuje produkt, když varianta v BC chybí nebo nemá `Item SystemId`;
  dále `FindShopifyProductVariant` při Add Item (shoda SKU / barcode) a `Create Item`. `Item Variant SystemId` dopíše
  i ruční akce **Map Variant** na stránce Shopify Variants nebo `Try Find Product Mapping` (SKU dle SKU Mapping).
- **Kde spouštět sync nových variant:** `Shpfy Sync Products` (30108) filtruje jen shop; jediný report s filtrem na zboží
  je `Add Item to Shopify` (30106), který existující produkt přeskočí — typická záměna u uživatelů.
- **Zásobu do Shopify posílá jen sync zásob, úprava = `Shpfy Inventory Events.OnAfterCalculationStock`.** Jediná cesta
  je `Shpfy Sync Inventory` (report 30102 `Shpfy Sync Stock to Shopify` i background sync přes `Codeunit.Run`) → `Shpfy Inventory
  API.GetStock` per řádek `Shpfy Shop Inventory` (produkt × varianta × lokace); sync **zboží nijak nefiltruje** (ani Blocked,
  ani filtr produktového syncu). Po výpočtu (libovolný `Stock Calculation` lokace, i vlastní enumextension) a přepočtu MJ volá
  `OnAfterCalculationStock(Item, ShopifyShop, LocationFilter, var StockResult)` (codeunit 30196, `internal` + IntegrationEvent,
  z PTE jde odebírat) — `StockResult := 0` pak pošle `inventorySetQuantities` s nulou, pokud Shopify drží jinou hodnotu (porovnává
  se `Shopify Stock` načtenou na začátku téhož běhu). Produktový sync zásobu **neposílá**: nový produkt / varianta se zakládá vždy
  s `availableQuantity: 0` (`Shpfy Variant API.GetInventoryQuantities`), skutečné číslo doplní až sync zásob. Zboží vyřazené
  z produktového syncu (filtr na `OnAfterProductsToSynchronizeFiltersSet`) si tak v Shopify drží poslední odeslanou zásobu —
  „schovat z webu" = nulovat zásobu tímhle eventem (a zásobová politika varianty *Deny*). Testovat jde jen procedura
  subscriberu volaná napřímo (event i `GetStock` jsou internal). (cust-sonnentor-bc PBI 63036 *Blokováno pro web*, 2026-10-14,
  konektor 28.5.)
- **Cena varianty pro Shopify se počítá přes dočasnou prodejní nabídku, takže běží tvoje validace `Sales Line`.**
  `Shpfy Product Price Calc.CalcPrice` (30182) volají Add Item, produktový / cenový sync, katalogové ceny i `Shpfy Update Price
  Source`. Pro každou exportovanou variantu založí temp `Sales Header` (Quote, `No.` = kód shopu) a temp `Sales Line` a validuje
  `Type`, `No.`, `Variant Code`, `Quantity` 1 a MJ.
  - Triggery tableextension na `Sales Line` (`modify(...) OnBeforeValidate`) i subscribery bez `IsTemporary` guardu proto běží
    při každé synchronizaci produktů a cen.
  - Zboží se speciálními pravidly řádku (dárkové poukazy: množství ±1, stav varianty) vyřaď subscriberem
    `Shpfy Product Events.OnBeforeCalculateUnitPrice(Item, VariantCode, UnitOfMeasure, ShopifyShop, Catalog, var UnitCost,
    var Price, var ComparePrice, var Handled)` (internal + IntegrationEvent, z PTE jde odebírat).
  - S `Handled = true` musíš sám nastavit i `ComparePrice`. Nulování „compare ≤ price → 0“ je uvnitř ne-handled větve. Přepočet
    na MJ (`Qty. per Unit of Measure`) si taky udělej sám, záložní větev konektoru ho dělá.
  - ⚠️ `Handled = true` obchází i všechno, co dělá dočasná nabídka: **měnu shopu / katalogu** (`TempSalesHeader.Validate("Currency
    Code")`), **`Prices Including VAT`** shopu a **ceník** (`Customer Price Group` / `Customer Disc. Group` shopu, slevy;
    `Price` = `Line Amount`). Záložní větev konektoru (`Item."Unit Price"` z karty) běží jen bez dočasné hlavičky, tedy prakticky
    nikdy. I bez ceníku standardní cesta cenu z karty nepošle surově: `Price Asset - Item.FillBestLine` (w1-28) ji dá jako řádek
    s `Currency Code` '' a `Price Includes VAT` z karty a výpočet řádku ji přepočte na měnu a DPH dočasné hlavičky (= shopu).
    S `Handled` a holým `Item."Unit Price"` tedy pošleš stejné číslo jen když je shop v LCY a sazba DPH je 0 % nebo `Price
    Includes VAT` karty = `Prices Including VAT` shopu. Jinak přepočet udělej sám, nebo to aspoň ověř na datech. Příští sync ceny
    v Shopify přepíše, takže změnu uvidí zákazník. (Review hotfixu 28.0.167.1, cust-sonnentor-bc, 2026-10-19, konektor 28.5.)
  - ⚠️ **Než s `Handled` sáhneš po `Item."Unit Price"`, ověř na datech, kde cena zboží reálně žije.** Zákazník s ceníky (B2C ceník,
    pokladna) mívá jednotkovou cenu na kartě 0 a standardní cesta konektoru našla cenu v ceníku přes dočasnou nabídku. Hotfix s kartou
    pak pošle do Shopify **cenu 0**. Import objednávky převezme cenu ze Shopify, takže zboží jde v e-shopu koupit zadarmo.
  - Sonnentor 28.0.167.1 → 28.0.167.2: cena poukazu se bere z vlastního pole hodnoty a měny (`Voucher Value SON` / `Voucher Currency
    SON`). Na měnu shopu ji přepočte `Currency Exchange Rate.ExchangeAmtFCYToFCY(WorkDate(), Z, Do, Částka)` (prázdný kód = LCY,
    stejné kódy = beze změny) a zaokrouhlí na `Unit-Amount Rounding Precision` (`Currency.Initialize`).
  - Kód měny rovný `General Ledger Setup."LCY Code"` (`CZK`) normalizuj na `''`. `ExchangeAmtFCYToFCY('CZK', '', …)` by hledal kurz
    pro CZK a sync by spadl.
  - **Zboží, které nemá jít do Shopify, vyřaď na úrovni produktu, ne až ve výpočtu ceny.**
    - Sync: `OnAfterProductsToSynchronizeFiltersSet` (filtr na `Item SystemId`, vzor `NarrowToAllowedItems` v cust-sonnentor-bc).
      Vyřazený produkt nedostane žádnou změnu, ani nově zakládané varianty, které by jinak vznikly s cenou z výpočtu.
    - Report Add Item (30106): `reportextension` `OnAfterPreDataItem`. Report volá `Shpfy Create Product.Run(Item)` bez ošetření,
      takže `Error` u jednoho zboží zastaví celý zbytek seznamu.
    - Filtr „není poukaz NEBO má hodnotu“ jde přes `Item.FilterGroup(-1)`: `SetRange` / `SetFilter` na různá pole se v této
      skupině kombinují přes OR. Pak vrátit původní skupinu. Ověřuje test `AddItemToShopifyLeavesOutVoucherWithoutValueAndLogsIt`
      (`RecordCount` nad třemi zbožími = 2), který prošel v lokálním kontejneru BC 28.4 (2026-10-20).
  - Pojistka ve výpočtu ceny (katalogové ceny, Add to Shopify z karty): `Handled := true` a ceny nech, jak je konektor předal.
    U existující varianty jsou to uložené hodnoty (`ShopifyVariant.Price`), takže se cena v Shopify nezmění. Výpočet běží pro
    **každou** variantu, takže zápis do logu deduplikuj (SingleInstance seznam zboží + shop, reset na začátku každého exportu).
    Jeden nový produkt z karty zboží zastav `Error` v `OnAfterCreateTempShopifyProduct` (běží po výpočtu cen, před voláním Shopify).
  - Cílová měna: `ShopifyShop."Currency Code"`, ne `Catalog`. `Shpfy Product Price Calc.` je SingleInstance a `SetShop` mění
    parametry jen při změně shopu, takže katalog v eventu může zůstat z dřívějšího katalogového syncu téže session.
  - Test zakládá zboží s **nulovou** jednotkovou cenou na kartě. Test, kde se karta rovná očekávané hodnotě, projde i se špatným
    zdrojem ceny.
  - `UnitOfMeasure` je `Code[20]`. Do `Item Unit of Measure.Get` ho dávej přes `Code[10]` proměnnou, jinak ALCops **PC0013**.
  - Vytvoření prodejního dokladu ze Shopify objednávky (`Shpfy Process Order.CreateLinesFromShopifyOrder`) cenu nepočítá. Bere
    `Shpfy Order Line."Unit Price"` z importu objednávky (`Validate("Unit Price", …)`).

  (cust-sonnentor-bc hotfix 28.0.167.1 / 28.0.167.2, `Shpfy Sync Event Handler SON.CalcVoucherPrice`, 2026-10-19/20, konektor 28.5.)
- **Vazba Shopify objednávka ↔ prodejní doklad drží pevně jen hlavičku.**
  - Hlavičky: `Shpfy Order Header."Sales Order No." / "Sales Invoice No."` ↔ `Sales Header."Shpfy Order Id"` + tabulka
    `Shpfy Doc. Link To Doc.` (30146).
  - Řádky jen jedním směrem: `Sales Line."Shpfy Order Line Id"`.
  - Víc prodejních řádků se stejným Line Id konektor snese. Fulfillment (`Shpfy Export Shipments.FindFulfillmentOrderLines`)
    sčítá `Quantity to Fulfill` podle Line Id. Kontrola konfliktu při reimportu prodejní řádky nečte.
  - Rozdělit Shopify řádek s množstvím N na N prodejních řádků jde přes `Shpfy Order Events.OnBeforeCreateItemSalesLine(…, var
    Handled)`.
  - Pozor na `ApplyGlobalDiscounts`: počítá slevu hlavičky ze **Shopify** řádků. Slevu, kterou na prodejním řádku zahodíš, v BC
    ztratíš.
  - Smazání prodejního dokladu `Sales Order No.` ani `Processed` na objednávce nevynuluje. Na to je akce *Unlink Processed
    Documents*.
  - Detail je v rozcestníku BCShopifyConnectorDocs, `shopify_functional_breakdown.md` sekce 3a.
  - ⚠️ `OnBeforeCreateItemSalesLine`: konektor `IsHandled` mezi řádky zboží **neresetuje** (jen ve smyčce dopravy). Subscriber,
    který nastaví `Handled := true` pro jeden řádek, musí u ostatních vracet `false`, jinak se všechny další řádky přeskočí.

  (2026-10-19, konektor 28.5 i 29.0.)
- **Slevové kódy objednávky konektor nedrží. Všechny kódy a částky po kódech jdou jen vlastním dotazem.**
  - Import čte jen `discountCode` (jeden kód, uříznutý na Code[20]). `Shpfy Order Header."Discount Codes"` (Text[250]) se plní
    z `discountCodes`, který v dotazu chybí, takže je **vždy prázdné**.
  - Řádky čtou `discountAllocations { allocatedAmountSet }` **bez** `discountApplication`. `Shpfy Order Line."Discount Amount"` je
    součet všech slev na řádku, včetně kódu „částka z objednávky“, který Shopify rozpustil poměrem na řádky. Na prodejním řádku
    je to `Line Discount Amount`.
  - Ani *Načtená data Shopify* (`Shpfy Data Capture` 30114, Internal) víc nemají. Ověřeno na objednávce se 3 kódy: JSON hlavičky
    má jeden `discountCode`, JSON řádku jen částky. Tabulka `Shpfy Order Disc.Appl.` (30117) je Internal a nikde se neplní.
  - Dotazy konektoru rozšířit nejde: GraphQL eventy jsou `InternalEvent`, `Shpfy Communication Mgt.` je Internal (5.y3).
  - Řešení:
    - Vlastní HttpClient (5.y3) s oprávněním **`read_orders`**: `order(id: "gid://shopify/Order/<id>") { discountApplications { nodes
      { index ... on DiscountCodeApplication { code } } } lineItems(first: 50, after: $after) { pageInfo { hasNextPage endCursor }
      nodes { id discountAllocations { allocatedAmountSet { shopMoney { amount } presentmentMoney { amount } } discountApplication
      { index } } } } }`.
    - `DiscountApplication.value` je **nastavená** hodnota slevy, ne odečtená. Skutečně odečtené = součet alokací řádků
      s daným `index`. Shopify ořízne fixní slevu na hodnotu košíku a při skládání slev se druhý kód spotřebuje jen zčásti.
    - `read_orders` vidí objednávky za posledních 60 dní.
  - Kde zasáhnout při vytvoření dokladu (`Shpfy Process Order`, celé uvnitř `if not ProcessOrder.Run()`):
    - Načtení a kontrola patří do `OnBeforeProcessSalesDocument`. `Error` tam zastaví jen tuhle objednávku: konektor ho uloží do
      `Error Message` přes `CopyStr` na 2048 a doklad vrátí zpět.
    - Zápis do vlastních tabulek ve stejné transakci se při chybě vrátí taky. Co má chybu přežít (výsledek kontroly pro
      uživatele), drž v SingleInstance bufferu. Zapiš ho v subscriberu `Shpfy Order Header.OnAfterModifyEvent` při
      `Has Error`: obě cesty konektoru (`Shpfy Process Orders.ProcessShopifyOrder` i report Sync Orders) po rollbacku
      nastaví chybu přes `Modify(true)` a pak `Commit`.
    - Úpravu řádkové slevy dělej v `OnAfterCreateItemSalesLine` jen na prodejním řádku, a to na `var SalesLine` eventu.
      Znovu načtený záznam by další subscriber se starou kopií přepsal. Shopify řádek nech být: `ApplyGlobalDiscounts` by
      rozdíl vrátil jako fakturační slevu.
    - Vlastní řádky dokladu (např. uplatnění poukazu) vkládej v `OnAfterCreateSalesHeader`. Řádky zboží si pak berou
      `GetNextLineNo` (FindLast + 10000) za nimi. Na „poslední Shopify řádek“ nespoléhej: BC 29 vynechává řádky výměny
      (`Is Exchange Item`) a cizí subscriber s `Handled` může řádky přeskočit. Po `ApplyGlobalDiscounts` už event není a
      `OnAfterProcessSalesDocument` může vidět vydaný doklad. Hodí se jen na závěrečnou pojistku s `Error`.
    - Shopify drží `discountAllocations` i u vráceného řádku, který konektor při importu sníží na 0 a smaže. Alokace kódu
      na řádku, který v `Shpfy Order Line` není, se na žádný prodejní řádek nepromítne. Hlídej to předem a na konci porovnej
      odečtenou a alokovanou částku.
    - Import (`OnAfterImportShopifyOrderHeader` / `OnAfterCreateShopifyOrderAndLines`) JSON nepředává. Pád HTTP tam vrátí import
      celé objednávky.
  - Automatické vytvoření dokladu v *Sync Orders From Shopify* běží jen pro **nově** naimportované objednávky. Objednávku, která
    spadla do chyby, zpracuje znovu akce *Create Sales Document(s)* nebo report **30103 `Shpfy Create Sales Orders`** (všechny
    nezpracované objednávky obchodu, jde do fronty úloh).

  (cust-sonnentor-bc PBI 63637 uplatnění dárkových poukazů z objednávek Shopify, `Shpfy Voucher Redemption SON`, 2026-10-20, konektor
  28.5, stejné i v 29.0.)
- **Co export produktu z BC do Shopify reálně pošle u metapolí a značek** (BC 28.4, `Shpfy Product Export` / `Shpfy Metafield API`):
  metapole jen při `Shop."Product Metafields To Shopify"` (pole 130; zákazník 131, společnost 132) přes
  `SyncMetafieldsToShopify` → `CollectMetafieldsInBC` bere jen `Type <> string & <> integer` (legacy typy se **nikdy** nepošlou),
  `Value <> ''` (vyprázdnění v BC se do Shopify nepropíše) a `"Last Updated by BC"` > `updatedAt` v Shopify (OnModify záznamu ho
  nastaví). Značky jdou v `productUpdate` jen když `Tags Hash` změnil produkt a seznam **není prázdný** (smazání všech značek v BC se
  nepošle). `Only Sync Price` metapole přeskočí. `Shpfy Product.OnDelete` maže metapole `DeleteAll()` → subscriber na
  `Shpfy Metafield` OnAfterDelete se spustí po řádcích. Hromadné plnění hodnot metapolí / značek z dat BC (pole, atribut, dimenze,
  funkce, maska JSON) řeší produktová appka **Essence Shopify Connector (SCEBS)** – dokumentace a známé chyby
  `prod-ess-shopifyConnector-bc/docs/module/Essence Shopify Connector.md` (větev Dokumentace, 2026-10-01).

### 5.y3 Shopify Connector — vlastní GraphQL mutace z PTE = vlastní HttpClient, vlastní token i vlastní adresa shopu

Zjištění z cust-sonnentor-bc 63637 (slevové kódy pro dárkové poukazy, konektor 28.4.53241.53839, 2026-09-22):

- **Komunikační vrstva konektoru je z PTE nepoužitelná:** `Shpfy Communication Mgt.` (30103, má `ExecuteGraphQL`),
  enum `Shpfy GraphQL Type` (30111, `Extensible = true`, ale Internal → enumextension neprojde) i `Shpfy Authentication
  Mgt.` (30199) mají **`Access = Internal`**; token je v Isolated Storage konektoru se scope `Module`. Konektor navíc
  **žádné discount API neimplementuje** (`discountCodeBasicCreate` apod. nikde). Essence Shopify Connector (SCEBS)
  řeší jen metafieldy, HTTP vrstvu nemá.
- **`Shpfy Shop` (30102) je public, ale `"Shopify URL"` i `GetStoreName`/`SetStoreName` jsou Internal** → `AL0161`
  při kompilaci. al-mcp u nich vrátí `Properties: []` a access nedoloží — rozhoduje kompilátor a zdroj
  (`microsoft/BCApps` releases/28.4 `src/Apps/W1/Shopify/App/src/Base/Tables/ShpfyShop.Table.al`; cesta `Base/Entities`
  je 404). Public tabulka ≠ public pole.
- **Důsledek:** vlastní `HttpClient` (`POST https://<shop>.myshopify.com/admin/api/<YYYY-MM>/graphql.json`, header
  `X-Shopify-Access-Token` jako SecretText z Isolated Storage scope Company), vlastní pole s doménou shopu na
  `Shpfy Shop` tableextension a **vlastní custom app v Shopify adminu** s potřebným scopem (`write_discounts`) —
  credentials zařizuje zákazník, je to blocker E2E testu. Query skládej přes `JsonObject` + `variables`, ne dosazováním
  do textu. `userErrors` v odpovědi = HTTP 200, ale nic se nestalo (viz 5.y2) — parsovat vždy; top-level `errors[].extensions.code = THROTTLED`
  a HTTP 429 (`Retry-After`) řešit jako čekání, ne jako chybu k počítání.
- **HTTP nikdy v posting transakci.** Vzor: subscriber při účtování jen zapíše řádek do fronty (rollbackne se s dokladem),
  Job Queue worker řádek claimne pod `ReadIsolation(UpdLock)` (token + lease), `Commit`, HTTP v `[TryFunction]` codeunitu
  bez DB zápisů, výsledek zapíše pod lockem jen vlastník tokenu a stav změní jen při nezměněné `Revision` (souběh
  „uplatněno během běžícího create"). Ownership marker do titulu discountu (`[BC <SystemId>]`) + lookup podle kódu před
  create = recovery po timeoutu bez duplicit a bez převzetí cizího kódu. Detail: `docs/proposals/63637-shopify-voucher-discounts.md`
  v cust-sonnentor-bc.

### 5.y4 Shopify Connector BC 29 — co se mění pro PTE a provoz

Z přímého diffu microsoft/BCApps `releases/28.5` → `releases/29.0` (snapshot `84f94fce`, 2026-10-05; detail
`VersionChanges/Changes28-29.md` v BCShopifyConnectorDocs):

- ⚠️ **Expirující offline tokeny — termín 2027-01-01.** Shopify pak odmítne neexpirující offline tokeny veřejných appek
  založených před 2026-04-01. BC 29 token sám jednou vymění (`Shpfy Authentication Mgt.EnsureValidAccessToken` před každým
  voláním; access token 1 h, refresh token 90 dní → po propadnutí notifikace **Reconnect** na kartě obchodu). V
  `releases/28.x` (28.6) k 2026-10-02 **není** → zákazník, který do 1. 1. 2027 zůstane na BC 28 bez backportu, přijde o
  spojení. Hlídat při plánování upgradů. U vlastního tokenu PTE (5.y3) ověř v dokumentaci Shopify, jestli se ho požadavek týká.
- **GQL codeunity → `.graphql` resource soubory** (`App/.resources/graphql/<Oblast>/<Dotaz>.graphql`, `# cost: N` + JSON,
  `NavApp.GetResourceAsText`). 129 codeunitů `Shpfy GQL *` smazáno, 14 zůstalo jako `ObsoleteState = Pending` pod
  `#if not CLEAN29`; interface `Shpfy IGraphQL` a interní eventy `OnBefore/AfterGetGrapQLInfo`, `OnBefore/AfterReplaceParameters`
  pryč. Enum `Shpfy GraphQL Type` má hodnoty `{Oblast}_{Dotaz}` a `Extensible = false`. PTE s odkazem na smazaný GQL codeunit
  (typicky **permission set**) se na 29 nezkompiluje. Objektů konektoru je 509 místo 639.
- **Test mocking:** `Shpfy Communication Events` (30200; `OnClientSend/Post/Get`, `OnGetContent`, `OnGetAccessToken`),
  `Set/GetTestInProgress` i `OnBeforeUploadImage` jsou smazané → testy PTE mockují HTTP platformním `[HttpClientHandler]`
  s `TestHttpRequestPolicy = BlockOutboundRequests` (vzor v testech konektoru).
- **Nové public API:** `Shpfy Product` (30234) `ConfirmAddItemToShopify`, `CheckItemAttributesCompatibleForProductOptions`,
  `GetProductUrl` (stejný postup jako Add to Shopify z karty); setery stránky `Shpfy Add Item Confirm` (30144) public. Nový
  event `OnAfterMapShopifyOrder(var ShopifyOrderHeader; Result)` v `Shpfy Order Events` (30162), `internal` +
  `[IntegrationEvent]` jako ostatní (z PTE jde odebírat, viz 5.y2), `CommitBehavior::Ignore`.
- **Internal zůstává** `Shpfy Communication Mgt.`, `Shpfy Authentication Mgt.`, `Shpfy GraphQL Type` i `Shpfy Shop."Shopify URL"`
  → 5.y3 platí i pro 29.0 (tokeny dál v Isolated Storage scope `Module`). Admin API verze 2026-07.

## 11. SaaS gotchas — HttpClient a Cloud target

### 11.1 HttpClient na SaaS — silent fail bez Allow HttpClient Requests

V SaaS sandboxu / produkci `HttpClient.Get()` / `HttpClient.Send()` může
vracet **`false` s prázdným `GetLastErrorText()`**, pokud extension nemá
povolený outbound HTTP. Uživatel to musí povolit v:

**Extension Management → najít extension → Configure → zapnout
"Allow HttpClient Requests"**

Důsledky pro vývoj:

- **V README** příslušné appky to popsat — "tato extension volá X, vyžaduje
  zapnutý Allow HttpClient Requests".
- **V kódu** mít čistou error message — pokud `Send`/`Get` vrátí `false` a
  `LastErrorText` je prázdný, je to skoro jistě tohle. Hlasit uživateli
  konkrétně, ne generic "HTTP failed".
- **V container / OnPrem buildu toggle neexistuje** — HTTP funguje vždycky.
  Rozdíl mezi dev container a SaaS je častý zdroj zmatku ("u mě to fungovalo!").
  Při hlášení problému vždycky řekni, **na jakém scope jsi testoval**.

### 11.2 `HttpClient.UseDefaultNetworkWindowsAuthentication()` = OnPrem-only

Compiler ji v `target: "Cloud"` extensionu **přijme** (!), ale runtime padne.
Pro Cloud target tuhle metodu nepoužívej. Pokud potřebuješ autentizaci, jdi
přes OAuth (`SecretText` token v `HttpRequestMessage` headerech) nebo Basic
auth se secretem z Isolated Storage.

### 11.3 Další Cloud-only gotchas

- `HttpClient.SkipDefaultUserAgentSet := true` — funguje, ale BC ti pak
  posílá header `User-Agent: Dynamics 365 Business Central` defaultně.
  Pokud cílový endpoint kontroluje UA, nastav vlastní.
- `IsolatedStorage` (built-in objekt) má **scope** parametr (`User`, `Company`,
  `CompanyAndUser`, `Module`). Module je defaultní pro per-extension secrets
  — sdílené napříč companies, izolované od jiných extension.

### 11.4 `SecretText.Unwrap()` = OnPrem-only (AL0296)

`SecretText` jde na Cloud targetu vytvořit i poslat do HttpClient headeru
(`SecretStrSubstNo`), ale **zpátky na Text ho nedostaneš** — `Unwrap()` má
scope OnPrem a compiler hodí `AL0296: ... has scope 'OnPrem' and cannot be
used for 'Cloud' development`.

Důsledky:

- Hodnota, kterou někdy potřebuješ v plaintextu (HTML formulář ke stažení,
  query string, obsah souboru), **nesmí žít jen v SecretText / Isolated
  Storage** — ulož ji jako normální pole setup tabulky. Typicky OAuth
  `client_id`: posílá se stejně v browser formuláři, není to secret (na
  rozdíl od `client_secret`).
- Crypto nad secretem řeš overloady, které berou SecretText jako parametr:
  `Cryptography Management.GenerateHash(InputString: Text; Key: SecretText;
  HashAlgorithmType: Option HMACMD5,HMACSHA1,HMACSHA256,HMACSHA384,HMACSHA512): Text`
  spočítá HMAC bez unwrapu a vrátí **UPPERCASE hex** (ne Base64) jako plain
  Text. Lowercase hex → `LowerCase()`.

### 11.5 Text → SecretText — jde JEN přes `SecretStrSubstNo` s Text PROMĚNNOU

Jak (ne)dostat Text do SecretText (ověřeno alc 17.0 / runtime 17, 2026-07,
prod-ess-dotykackaConnector-bc testy):

```al
// NEfunguje — přiřazení: AL0122 Cannot implicitly convert type 'Text' to 'SecretText'
MySecret := 'literal';
MySecret := TextVar;

// NEfunguje — Text LITERÁL jako substituční argument: AL0133 (Argument 2: Text→SecretText)
MySecret := SecretStrSubstNo('%1', 'literal');

// Funguje — Text PROMĚNNÁ jako substituční argument
TextVar := 'literal';
MySecret := SecretStrSubstNo('%1', TextVar);
```

Rozdíl literál vs. proměnná u `SecretStrSubstNo` je neintuitivní — literál
kompilátor odmítne, proměnnou vezme. V testech (i kódu) proto secret hodnoty
vždy nejdřív do lokální `Text` proměnné a pak `SecretStrSubstNo('%1', X)`.
Asserty na hodnotu SecretText v Cloud testech nejde dělat vůbec (Unwrap =
OnPrem, viz 11.4) — testuj přítomnost přes `SecretText.IsEmpty()` a chování
(`HasCredentials()`, `HasValidToken()`…), ne obsah.

---

### 11.6 Notifikace do Power Automate z BC — External Business Events jsou PREVIEW, pragmaticky API page + trigger konektoru

**External Business Events** (`[ExternalBusinessEvent('name','Display','Desc',
EventCategory::X)]` na proceduře s prázdným tělem v codeunitu, kategorie přes
`enumextension ... extends EventCategory`, payload = jen primitivní parametry) jsou
k 2026-05 na Learn **stále „(preview)"** (BC 22+). Prerekvizity nejsou zadarmo:
Dataverse Connection Setup se zapnutým „Enable virtual tables and events",
instalace **Business Central Virtual Table** appky do Dataverse, po každé změně
eventů ruční „Refresh Business Event Catalog" v Power Apps, v Power Automate
**Dataverse** trigger „When an action is performed" (ne BC konektor). Subscription
se zakládá pro všechny firmy naráz, bez překladů/verzování. Bez Dataverse
prostředí u zákazníka to **nenacenit jako levnou variantu**. Notifikace odchází
**až po commitu** transakce; při rollbacku vůbec.

**Pragmatická varianta bez Dataverse (GA, BC konektor):** vlastní fronta —
tabulka `... Notification Queue` (klíč Entry No., payload pole: doklad, kód,
e-mail, priorita, DateTime, Sent), do ní `Insert` v OnValidate / subscriberu
v momentě, kdy má notifikace vzniknout; nad tabulkou **API page** (`PageType =
API`, APIPublisher/Group/Version, `ODataKeyFields = SystemId`); ve flow trigger
BC konektoru **„When a record is created (V3)"** s výběrem custom API kategorie.
Jeden insert = jedna notifikace, payload je celý záznam, žádné hlídání „které pole
se změnilo". Trigger „When a record is modified (V3)" nad hlavičkou dokladu je
horší: pálí při každé změně a nepředává starou hodnotu. HttpClient z BC přímo na
PA trigger „When an HTTP request is received" jde taky, ale ten trigger je
v Power Automate **Premium**. (Zlomek 62661 nacenění, 2026-09-02.)

---

### 11.7 Vlastní API page pro zápis — POST validuje pole po jednom, temporary stránka s limitem, relace přes víc volání

Z code review API konfigurátoru (COEBS task 66387, stránky `configurationSessions` / `allowedParameterValues`, 2026-09-24):

- **POST / PATCH validuje každé pole zvlášť** a pořadí neurčuješ. `TableRelation` s `where(... = field(X))`, kde X se doplní
  až v `OnInsert` (zboží převzaté z prodejního řádku), nebo vazba přes pole, které se validuje později (číslo dokladu
  `where("Document Type" = field(...))` – enum je do té doby na defaultu, u Sales Document Type = Quote), spadne dřív, než
  se k `OnInsert` dojde. Řešení: `ValidateTableRelation = false` na takovém poli (s komentářem proč) + kontrola v `OnInsert`
  / inicializaci, až jsou známá všechna pole. Test: `Validate` polí v „nepohodlném" pořadí a pak `Insert(true)`.
- **Temporary API page plněná v `OnFindRecord` s limitem** (např. max. 1000 záznamů ze zdrojové tabulky): filtry z
  `$filter` jsou v tu chvíli na `Rec` → přečti je `Rec.GetFilter(Pole)` a **aplikuj na zdroj před limitem**, jinak záznam za
  limitem nenajde ani cílený filtr. Filtr z `GetFilter` je v AL syntaxi → na zdroj `FieldRef.SetFilter` v `[TryFunction]`
  (filtr, který na typ pole nesedí = prázdný výsledek, ne chyba 500). Plnění buffer maže → `Rec.GetView()` před a
  `Rec.SetView()` po; plnit jen při změně filtrů (klíč z filtrů v globální proměnné stránky).
- **Relace přes víc volání nesmí přepsat novější data.** Když stavová relace (tabulka držící stav mezi voláními) na konci
  zapisuje do cílového záznamu, ulož si při založení jeho `SystemId` a hodnotu, kterou mění; při aplikaci ho načti s
  `ReadIsolation(IsolationLevel::UpdLock)` a porovnej. Jiný SystemId = záznam smazán a založen znovu pod stejným klíčem, jiná
  hodnota = mezitím změnil uživatel / jiná relace → `Error` „vytvořte novou relaci". Test: dvě relace, novější aplikovat,
  starší → `asserterror`; znovuzaložení řádku `Insert(false, true)` s novým `CreateGuid()` v SystemId.
- **Neplatný vstup = `Error` dřív, než se cokoli změní.** Logika převzatá z dialogu často dělá „nečitelné číslo → prázdná
  hodnota" (uživatel to vidí a opraví); přes API by to potichu smazalo hodnotu i data na ní závislá. Temporary buffer
  `asserterror` nevrací → test po `asserterror` ověří, že buffer drží původní hodnoty.

**Ověřeno živě přes REST (COEBS 28.0.22.3 na Alumistr BC-TEST2, 2026-09-24):**

- **`$expand` = `EntitySetName` partu, ne název controlu.** `part(parameters; ...) { EntitySetName = 'configurationSessionParameters'; }`
  → `$expand=configurationSessionParameters`; `$expand=parameters` vrátí 400 *Could not find a property named 'parameters'*. U
  jednoho záznamu (`EntityName`) totéž. Dokumentaci piš podle `$metadata` (`GET …/api/<publisher>/<group>/<ver>/$metadata`,
  `<NavigationProperty Name=…>`), ne podle AL zdrojáku. BC navíc sám přidá navigaci po polích s `TableRelation` na tabulku
  jiné stránky téže API skupiny (`parameterCondition` → `configurationParameter`).
- **Pole z proměnné stránky (`field(isConfigurable; IsConfigurable)`) nejde filtrovat** — `$filter=isConfigurable eq true` →
  400 `BadRequest_NotSupported` *Field 'isConfigurable' is not filterable*. Klient (AI přes MCP) musí stáhnout vše a filtrovat
  u sebe. Filtrovatelné je jen pole tabulky (i FlowField). Počítej s tím, když API nabízí „příznak k vyhledání".
  **Řešení ověřené na BC-TEST2:** příznak jako **FlowField** na tableextension zdrojové tabulky (`exist`/`lookup`), podmínka závislá
  na `WorkDate()` přes **FlowFilter** pole (`"Valid From" = field("Cfg. Valid From Filter")`), které API stránka nastaví v `OnOpenPage`
  **i** v `OnFindRecord` (`Rec.SetFilter(FlowFilter, '%1|<=%2', 0D, WorkDate()); exit(Rec.Find(Which))`) – `$filter=isConfigurable eq true`
  pak vrací přesně řádky, které dřív spočítal výpočet v `OnAfterGetRecord` (372/372), i přes MCP server BC. (COEBS 66387, 2026-09-24.)
- **Bound action s `SetResultCode(WebServiceActionResultCode::Updated)` vrací HTTP 200 s prázdným tělem** — výsledek si klient
  musí dočíst GETem entity. `Error` v akci = 400 s textem hlášky a rollback celé akce (i vytvořené varianty / kusovníku).
- **Test z CLI bez app registrace:** device code flow s first-party klientem `1950a258-…` (M4 v `bc-al-mcp-server.md`) funguje i pro
  resource **`https://api.businesscentral.dynamics.com/Financials.ReadWrite.All`** — token pak na
  `https://api.businesscentral.dynamics.com/v2.0/<tenant>/<env>/api/…`. `Accept-Language: cs-CZ` vrací hlášky česky. Hotové skripty
  `%LOCALAPPDATA%\bc-api-test\` (`bc-api-login.ps1 -Tenant`, `bc-api.ps1 -Path -Method -Body -IfMatch`; pwsh 7 kvůli
  `-SkipHttpErrorCheck`, `Invoke-WebRequest` nemá `-StatusCodeVariable`). PATCH potřebuje `If-Match` s `@odata.etag`.
  Tenant ID z domény: `GET https://login.microsoftonline.com/<domena>.onmicrosoft.com/v2.0/.well-known/openid-configuration` → `issuer`.

### 11.8 Dataverse (CDS) sync — filtr integrační tabulky platí jen Dataverse → BC, Enum → Choice přes `OptionOrdinalValues`, testy bez Dataverse

Z cust-sonnentor-bc task 66405 (appka SON CDS Sync, BC 28.4, 2026-09-29; zdroje w1-28 `Integration/SynchEngine/
IntegrationRecordSynch.Codeunit.al`, `IntegrationTableMapping.Table.al`, `Integration/Dataverse/CRMIntegrationTableSynch.Codeunit.al`,
`CDSSetupDefaults.Codeunit.al`, `Integration/D365Sales/CRMAccount.Table.al`):

- **Integration Table Filter mapování se uplatní jen ve směru Dataverse → BC.** `CRM Integration Table Synch.` ho aplikuje při čtení
  CRM záznamů (`SplitIntegrationTableFilter` + `SetView`); ve směru BC → Dataverse se spárovaný CRM záznam dohledává
  `Integration Table Mapping.GetRecordRef(ID)` **bez filtru** (jen `SetFilter` na UID pole). Filtr typu „jen schválené účty"
  (`CRMAccount.SetRange(ebs_vendorapproved, true)`) tedy brání založení / aktualizaci v BC, ale spárovaný záznam se z BC do
  Dataverse aktualizuje dál; vypadnutí z filtru není smazání (Deletion-Conflict se netýká). Filtr skládej typovaně:
  `SetRange` → `GetView()` → `FilterPageBuilder.SetView/GetView(Caption, false)` → `SetIntegrationTableFilter` (vzor
  `CDSManagementSON.UpdateVendorIntegrationTableMapping`), nikdy ručně psaný text s čísly polí.
- **Standardní mapování VENDOR má BC filtr `Blocked = ' '`** (`CDS Setup Defaults.ResetVendorAccountMapping`) → blokovaní
  dodavatelé se do Dataverse neposílají vůbec. Když má Dataverse stav Blocked vidět, filtr zruš `IntegrationTableMapping.SetTableFilter('')`.
- **Enum / Option pole BC → Dataverse Choice (Picklist):** na CDS proxy tabulce (`TableType = CDS`, tableextension na `CRM Account`
  funguje stejně) pole `Option` s `ExternalType = 'Picklist'`, `OptionMembers` **ve stejném pořadí jako BC enum** a
  `OptionOrdinalValues = -1, 1, 2` (index → hodnota Choice v Dataverse, `-1` = null pro prázdnou; vzor base `CRM Account`.AccountCategoryCode).
  `Integration Record Synch.TransferFieldData` u shodných typů (enum se přes `FieldRef.Type` hlásí jako Option) přiřadí hodnotu přímo
  (`FieldRef.Value := Variant`) — přenáší se **index**, ne caption; caption-matching (`TextToOptionValue` přes OptionCaption /
  OptionMembers) nastupuje jen u rozdílných typů a u constant value. Hodnoty Choice v Dataverse proto musí sedět na
  `OptionOrdinalValues` (ne výchozí `100000000+`). Enum `Vendor Blocked` má `AssignmentCompatibility = true`. Přenos indexu
  ověřuje test `VendorBlockedValueIsTransferredToDataverseOption` (k datu zápisu jen lokální kompilace, CI běh ještě ne).
  **Proč ne Enum:** `Enum` pole s `ExternalType = 'Picklist'` se na CDS tabulce zkompiluje, ale `OptionOrdinalValues` na něm
  alc 17.0 odmítne (`AL0171: The property value '-1, 1, 2' on property 'OptionOrdinalValues' is not valid` — i pro `0, 1, 2`),
  takže nejde vyjádřit prázdná ↔ `null` ani jiné než ordinální hodnoty Choice; MS proxy tabulky i AL Table Proxy Generator
  používají výhradně Option (idea „Replace Option Fields in Tables of Table Type=CRM/CDS" je u MS ve stavu New). Hodnotu `-1`
  pro prázdnou bere generátor i base `CRM Account` (`AccountCategoryCode`), hodnoty ostatních členů musí sedět na Choice v Dataverse.
- **Field mapping jedním směrem uvnitř Bidirectional tabulkového mapování** je normální (`Direction::ToIntegrationTable` na
  řádku, vzor `No. → ebs_bcnumber`). `Integration Field Mapping.CreateRecord` vždy vkládá nový řádek (PK AutoIncrement) —
  duplicity při opakovaném „Default Synchronization Setup" řeší až `Integration Table Mapping.CreateRecord` (`Get → Delete(true)`
  smaže i field mappingy); vlastní mapování zakládej stejně — vždy recreate, viz bullet o ručním mapování níže.
- **Testy bez Dataverse:** `RegisterTableConnection(TableConnectionType::CRM, 'TEST', '@@test@@')` + `SetDefaultTableConnection`
  (platformové test připojení, používá MS `Library - Mock CRM Connection`) → CRM proxy tabulky jedou z lokální DB, i `FilterPageBuilder`
  nad nimi. Filtr mapování ověř `TempCRMAccount.SetView(IntegrationTableMapping.GetIntegrationTableFilter())` + `SetRange(AccountId)`
  + `IsEmpty`; přenos hodnot přímo enginem: `Temp Integration Field Mapping` (No., Source/Destination Field No.) →
  `IntegrationRecordSynch.SetFieldMapping(Temp)`, `SetParameters(SourceRecRef, DestRecRef, false)`, `Run()`, `DestRecRef.SetTable(TempCRMAccount)`.
  Tělo subscriberu na `OnAfterResetVendorAccountMapping` vyčleň do `internal procedure` (app má `internalsVisibleTo` na test app) —
  lokální `IntegrationEvent` publisher standardu z testu nevyvoláš a `CDS Setup Defaults.ResetVendorAccountMapping` táhne job queue.
  Reset konfiguračních šablon hlásí chybějící `Config. Template Header` přes `Message` → v testu šablony založ (helper
  `EnsureConfigTemplatesExist`), nebo `MessageHandler`.
  Test připojení registruj v `Initialize()` **každého** testu, který se CRM proxy tabulky jen dotkne — padá už
  `IntegrationTableMapping.CreateRecord(..., Database::"CRM Account", ...)` bez jediného čtení záznamu („Table connection for table
  type CRM must be registered using RegisterTableConnection" — cust-soitron-bc build 28646, `Tax Reg. No. Sync Test CCSOI`, 2026-10-05).
  ⚠️ **`CRM Integration Management` je SingleInstance a `IsCRMIntegrationEnabled()` si výsledek cachuje na celou session**
  (`CRMIntegrationEnabledState`, w1-28 `Integration/Dataverse/CRMIntegrationManagement.Codeunit.al`). Test, který zapíná
  `CRM Connection Setup."Is Enabled"` přes `Insert(false)` / `Modify(false)` (triggery `ClearState` nevolají), proto po
  **každém** zapnutí zavolá `CRMIntegrationManagement.ClearState()`. Bez toho: jakmile dřívější test téhož běhu (i v jiném
  codeunitu — runner jede po ID) otevře Customer / Vendor / Item / Job Card s `IsIntegrationEnabled()` v `OnOpenPage`,
  cache drží „Not Enabled" a vlastní validace padá *„The Dataverse integration is not enabled…"*, ačkoli setup už enabled je.
  Lokálně ani na masteru to nevyskočí — projeví se až přidáním testu s TestPage karty do codeunitu s nižším ID
  (cust-soitron-bc build 28826, 11 testů `CRM Business Unit Test SOI` + `Business Unit Assign. Test SOI` po přidání
  `CustomerCardShowsCreatedVendorNo` do 54430, 2026-10-13). `IsCDSIntegrationEnabled()` se necachuje.
- **Vlastní mapování při „Default Synchronization Setup" vždy založ znovu (`Integration Table Mapping.CreateRecord` =
  `Get → Delete(true)` + Insert), ne „když existuje, přeskoč".** Na stejný event `CDS Setup Defaults.OnAfterResetConfiguration`
  je subscribnutý i standardní `Manual Int. Mapping Events` (BaseApp `Integration/SynchEngine/ManualIntMappingEvents.Codeunit.al`):
  pro každý záznam **Man. Integration Table Mapping** (5380, stránka Manual Integration Table Mappings) založí `Integration Table
  Mapping` téhož jména, **pokud ještě neexistuje**, a přidá jen ruční řádky `Man. Int. Field Mapping`. Pořadí subscriberů není
  zaručené → když standard běží první, vlastní kód s guardem `if not Get then CreateRecord` mapování přeskočí a v něm zůstane
  jediné ruční pole (cust-sonnentor-bc TEST: SHIPTOADDRESS jen s Contact ↔ ebs_contacttxt — i po smazání mapování a novém
  resetu, ruční záznam přežívá, `Integration Table Mapping.OnDelete` ho nemaže; DEV bez ručního záznamu fungoval). Fix: recreate
  + smazat `Man. Integration Table Mapping` téhož jména (`Delete(true)` uklidí i jeho field mappingy), ať kódem řízené mapování
  vyhraje v obou pořadích; dedupe řádků polí pak není potřeba. Standard dělá totéž (`CDS Setup Defaults.InsertIntegrationTableMapping`
  volá `CreateRecord` bez guardu). Test: existující mapování s jedním řádkem + ruční záznam → po resetu plná sada přesně 1× a ruční
  záznam pryč (`Ship-to Sync Setup Test SON`; ruční záznam v testu `Init` + přímé přiřazení + `Insert(true)`, `CreateRecord` je internal).
  (2026-10-14, cust-sonnentor-bc, SON CDS Sync.)

- **Lookup (Code → GUID) na Dataverse tabulku, která se NEsynchronizuje (číselník udržovaný ručně v PA) = NE řádek field
  mappingu, ale `Integration Rec. Synch. Invoke.OnAfterTransferRecordFields`.** Standard (`CRM Int. Table. Subscriber.
  OnTransferFieldData` → `CRM Synch. Helper.AreFieldsRelatedToMappedTables`, w1-28 `Integration/D365Sales/`) u mapovaného
  páru polí, kde mají obě strany `TableRelation` a cíl je Guid, **vyžaduje `Integration Table Mapping` mezi oběma
  tabulkami, jinak `Error` „Table X must be mapped to table Y to transfer value between fields…“** — a protože pořadí
  subscriberů téhož eventu není zaručené, vlastní subscriber na `OnTransferFieldData` s `IsValueFound` to neobejde (ověřeno
  v DEV: řádek synchronizace spadl přesně na tuhle hlášku). Bez `TableRelation` na cílovém poli zase platforma nezná
  cílovou entitu lookupu. Funkční vzor: CRM proxy tabulka číselníku (`TableType = CRM`, `ExternalName` entity, PK + sloupec
  s kódem — u ručně založené PA tabulky bývá jen primární `ebs_name`, žádný `ebs_code` — sekundární klíč na ten sloupec,
  **bez mapování**), pole na `CRM Account` jako `Guid` + `ExternalType = 'Lookup'` + `TableRelation` na proxy, **žádný
  řádek field mappingu** a subscriber `OnAfterTransferRecordFields(SourceRecordRef, var DestinationRecordRef, var
  AdditionalFieldsWereModified, DestinationIsInserted)` (hook Base App pro doplňková pole, stejný používá standard): guard
  na zdroj Customer / cíl CRM Account, GUID dohledat podle kódu, zapsat `FieldRef.Value(...)` jen při změně a nastavit
  `AdditionalFieldsWereModified := true` (jinak engine Modify neudělá). Prázdný kód / bez shody = prázdný GUID, záznam
  nepadá. Test: `internal` procedura nad `RecordRef` temp Customer / temp CRM Account +
  `RegisterTableConnection(... '@@test@@')`, proxy záznam číselníku `Insert(false)` jde do lokální DB.
  ⚠️ **`statecode` na vlastní proxy tabulce jako `Option " ",Active,Inactive` s `OptionOrdinalValues = -1, 0, 1`** (vzor
  Picklist) shodil celý synchronizační job na *Object reference not set to an instance of an object* (job bez Finish
  Date/Time, fronta úloh opakuje 10×); po odstranění pole hned čitelná AL chyba. V cust-jps-bc mají starší proxy tabulky
  přesně tenhle blok zakomentovaný. Generátor (altpgen) dává `OptionMembers = Active,Inactive; InitValue = Active` bez
  ordinálů — když stav potřebuješ, drž generovanou podobu. Textový sloupec místo lookupu není zkratka: do lookup atributu
  string neprojde (*Unable to cast object of type 'System.String' to type 'Microsoft.Xrm.Sdk.EntityReference'*) a lookup
  sloupec v Dataverse nejde přetypovat. **Nová custom tabulka v Dataverse = přidat `Read` (Organization) aplikačnímu
  uživateli BC** (*Business Central Integration*, ApplicationId `88c57617-…`, type=8 Non-interactive) v jeho security roli,
  jinak dotaz z proxy skončí *Principal user … is missing prvRead<entity> privilege*; v BC je celý text jen v poli *Error
  Message* (2048) tabulky *Integration Synch. Job Errors*, pole *Message* (250) i seznam ho uříznou. **Výsledek u JPS:** po
  třech kolech (lookup → text → lookup) zákazník v PA lookup zrušil a založil textový sloupec `ebs_vatbusinesspostinggroup`;
  v BC zbylo pole `Text[20]` + `ExternalType = 'String'` a jeden řádek field mappingu, bez proxy tabulky a bez kódu. Než
  stavíš lookup na nesynchronizovaný číselník, zeptej se, jestli PA relaci opravdu potřebuje — text je o tři objekty, jeden
  subscriber, testy a oprávnění v Dataverse levnější. (2026-10-19/21,
  cust-jps-bc DEV, Customer `VAT Bus. Posting Group` →
  `CRM Account.ebs_vatbusinesspostinggroupid`, `CDSManagementJPS`.)

### 11.9 Jira Cloud user lookup podle e-mailu — `/rest/api/3/user/search?query=<e-mail>`, NE `/rest/api/3/users`

Z cust-soitron-bc (Jira synchronizace zdrojů, 2026-10-09): zdroje dostávaly cizí Account Id. Příčina: v setupu zůstal z první
verze (četla celý adresář a párovala e-maily v kódu) endpoint **`/rest/api/3/users`** = „Get all users" — parametr `query`
**ignoruje** a vrátí prvních 50 uživatelů adresáře; kód pak vzal prvního kandidáta se skrytým e-mailem (jiná osoba).
`InitValue` pole se změnou kódu existující setup nezmění → po změně významu setup pole hlídat validací (`OnValidate`:
musí končit `/user/search`) a říct zákazníkovi, ať hodnotu přepíše.

- **Správný dotaz:** `GET /rest/api/3/user/search?query=<celý e-mail>` (URL-encoded, `@` = `%40`). Jira matchuje celou
  adresu jako prefix e-mailu **i skrytého** (profile privacy), takže výsledek je typicky jeden uživatel; `emailAddress`
  v odpovědi chybí, když ho má uživatel skrytý. Single-user čtení: `GET /rest/api/3/user?accountId=…`.
- **Výběr kandidáta:** viditelný `emailAddress` identický (bez case) = ten uživatel; viditelný jiný = jiná osoba, přeskočit;
  skrytý e-mail = přijmout jen když je takový kandidát **jediný** (víc skrytých = nejednoznačné, nepřiřazovat — přesně to vrací
  `/users`). Porovnávání displayName se jménem zdroje nedělat (jména v Jira a BC se běžně liší, zákazník to nechce hlídat).
- Výběr drž v čisté proceduře nad textem odpovědi (`FindResourceAccountIdInUsers(ResponseText, Resource, var AccountId)`),
  ať jde testovat bez HTTP (`[HttpClientHandler]` je OnPrem-only) — testy `FindJiraUser_*` v `Jira JPL Change Test SOI`.
- Hodnotu s `@` v poli Account Id (ručně zadaný e-mail) ber jako nenavázanou (`SetFilter(Pole, '%1|%2', '', '*@*')`), ať ji
  příští dohledání přepíše; akce „Synchronize Jira Users" s volbou přepsat i existující ID opraví data po takové chybě.
- Account Id je pro Jira i Tempo povinný identifikátor (payloady `leadAccountId` / `assignee.id`, Tempo worklog `author.accountId`
  bez e-mailu; Atlassian GDPR migrace 2019; `GET /user/email` je jen pro Connect/OAuth appky, ne Basic auth) — ukládat ho na zdroj
  jako cache má smysl i při viditelných e-mailech.

- **Assignee / reporter issue (2026-10-16, cust-soitron-bc):** když BC pole `assignee` nepošle, Jira dosadí **default assignee
  projektu**, což je u projektu založeného přes API **Project lead** (`leadAccountId`) — Create project bere `assigneeType`
  jen `PROJECT_LEAD` / `UNASSIGNED` a default assignee jde přepnout na Unassigned jen při zapnutém *Allow unassigned issues*
  (System > General configuration; KB „Unable to change the Default assignee field"). Explicitní `"assignee": null` nechá issue
  nepřiřazenou — opět jen s tím přepínačem, jinak 400. **Reporter** je vždy uživatel API tokenu; přepsat ho (`"reporter":
  {"accountId": …}`) jde jen s projektovým oprávněním *Modify Reporter* a s polem Reporter na create/edit screenu (KB „User not
  able to change the reporter on an issue"), jinak 400 „Field 'reporter' cannot be set. It is not on the appropriate screen".
  Reporter **nesmí být null** (povinné pole) → bez rozpuštěného účtu pole vynechat. Diagnostika: outbound log `Jira Transfer SOI`
  nese odeslaný payload — nejdřív ověřit, že pole v requestu vůbec je (u Soitronu chybělo, protože zdroj neměl Account Id ani e-mail).

### 11.9b Tempo v4 worklog nese u issue jen `id` + `self` (žádný `key`) → parent / projekt dočíst z Jira issue

Z cust-soitron-bc (import výkazů Tempo → External Time Sheet Line, 2026-10-12): `GET https://api.eu.tempo.io/4/worklogs/{id}`
vrací `"issue": { "self": "https://<site>.atlassian.net/rest/api/2/issue/10098", "id": 10098 }` — **klíč issue tam není**.
Kód, který bral `issue.key` (a z něj prefix = Jira project key → projekt v BC), tak dostal prázdný text a fallback na
projekt nikdy nezabral. Uživatelé navíc vykazují na **podúkoly / child issue**, které BC nezakládal → podle `issue.id` se
řádek plánování nenajde.

- **Řešení:** nenajde-li se řádek podle `issue.id`, načíst issue z Jiry `GET {Jira Base Url}/rest/api/3/issue/{id}?fields=parent,project`
  (Basic auth Jira, ne Tempo bearer) → `key`, `fields.parent.{id,key}`, `fields.project.key`; lézt po `parent` nahoru
  (sub-task → story → epic, limit proti cyklu), nejbližší předek s řádkem plánování vyhrává; jinak projekt podle
  `fields.project.key`; teprve pak skip. `self` z Tempa **nevolat přímo** — URL přichází z cizí odpovědi a nesla by Jira
  credentials na libovolný host; skládat z nakonfigurované Base Url + id.
- **Selhání Jiry (≠ 404) = chyba worklogu, ne skip** — skip u inbound syncu s `updatedFrom` posune časovou značku a worklog
  se už nikdy nenačte. 404 (issue smazané / bez práv) = „nevím nic" → pokračovat fallbackem. Odpovědi cachovat per běh
  (Dictionary v instanci codeunitu, i 404 jako prázdný text) — worklogů na jednom podúkolu bývá hodně.
- **Test bez HTTP na Cloud targetu:** `[IntegrationEvent] OnBeforeFetchIssue(IdOrKey; var ResponseText; var HttpStatusCode;
  var IsHandled)` v API codeunitu (před HTTP, status kód zpracuje společný kód) + test codeunit s `EventSubscriberInstance =
  Manual`, který si mock data drží v globálních proměnných **vlastní instance** (`JiraIssueMock: Codeunit "<tentýž test>";
  JiraIssueMock.AddMockedJiraIssue(...); BindSubscription(JiraIssueMock)` v lokální proměnné testu). Neregistrovaná issue
  = 404. Existující testy, které dřív končily fallbackem bez HTTP, musí mock bindnout taky (jinak jdou na síť).
  Kompilace čistá (alc 17), CI běh zatím ne.

### 11.10 Dotykačka (Dotypos API v2) — stav skladu je `stockQuantityStatus`, blokace = `display: false`, ceny s DPH do `priceWithVat`, okno účtenek `versionDate`

Z prod-ess-dotykackaConnector-bc, PBI 63075 (test Pavla Fily 2026-10-08, oprava 2026-10-09; zdroj
`docs.api.dotypos.com/entity/warehouse/` a `/entity/product/`, `api.dotykacka.cz/...` WebFetch vrací 403):

- **`GET warehouses/{id}/products` nese množství v poli `stockQuantityStatus`, ne `quantity`.** Delta sync (stav Dotykačky
  vs. `Item.Inventory`) četl neexistující `quantity` → null-safe getter vrátil 0 → každý běh naskladnil (stockup) celou
  BC zásobu znovu („synchronizace zásob přičítá"). Obecně: **u delta syncu proti cizímu stavu chybějící pole = chyba
  čtení, ne nula** (`JsonObject.Contains` před getterem; null hodnota = 0 je OK). První běh po opravě sám srovná
  nafouknutý stav jedním `sales` pohybem.
- Stockup / sale (`POST warehouses/{id}/stockups|sales`) bere **max. 100 položek** → posílat po dávkách;
  `purchasePrice` / `sellPrice` u stockupu volitelné.
- **Produkt nejde zablokovat** — prodej se zastaví skrytím `display: false` (PATCH, If-Match ETag z GET entity, jinak 428).
  `display` jde filtrovat (`filter=id|in|1,2;display|eq|true`, bez shody HTTP 404) → skrývej jen ještě zobrazené,
  ustálený stav pak stojí jeden GET na dávku. Odblokování = další plný PUT s `display: true`.
- **Ceny:** minimální body je `priceWithoutVat` + `vat` (multiplikátor 1.21); `priceWithVat` je volitelné a Dotykačka ho
  jinak dopočte. B2C ceník v BC je s DPH → posílat `priceWithVat` = cena a `priceWithoutVat` = cena / `vat` s jemnou
  přesností (0,00001), jinak se cena s DPH zapíše jako cena bez DPH a pokladna přičte DPH podruhé. Hladiny
  `priceWithVatB–E` jsou s DPH a platí **pro celý cloud** (pole produktu) → jedna hladina = jeden ceník napříč mapou.
  **Hladinu nevolí pobočka ani pokladna** (Branch ani nastavení pokladny pole hladiny nemají): použije se, když ji
  obsluha vybere u položky, nebo **automaticky podle zákazníka** (webová správa → Zákazníci → *Cenová hladina*; skrytou
  hladinu jde použít jen přes zákazníka); per pokladna jsou jen cenové akce (Plán cen, Happy Hours). Hladina zákazníka
  v API v2 Customer **není** → BC ji nepřečte, mapa „pobočka + zákazník → hladina → ceník“ je jen deklarace
  (manuál `cenove-hladiny-vs`, `zakaznicivs`; 2026-10-20).
- **Zákazník účtenky:** order (i order item) má `_customerId` (null = bez zákazníka; filtr EQUALS). `include` na orders
  umí jen `orderItems,moneyLogs` → zákazníka čti zvlášť `GET /clouds/{id}/customers/{customerId}` (cache per běh;
  smazaný → nejspíš 404). *Externí označení* z webové správy = **`externalId`** (string ≤ 256, při importu CSV unikátní,
  ani po smazání zákazníka nejde znovu použít) → přirozený nosič čísla zákazníka BC. Sleva zákazníka jde ze *Slevové
  skupiny* (`_discountGroupId`, %) a na order item je jen jako `discountPercent` bez zdroje; platí jen při výběru
  zákazníka **před** vystavením účtu — dodatečné přiřazení v historii účtenek změní `_customerId` (a `versionDate`),
  ne ceny. Ověřeno z docs.api.dotypos.com + manuálu, **ne na živých datech** (2026-10-20).
  Výběr řádku `Price List Line` pro export: `Status` Active, `Amount Type` Price|Any, `Minimum Quantity` 0, LCY,
  `Unit of Measure Code` prázdná|základní, `Starting Date ..WorkDate`, `Ending Date` `%1|>=%2` (0D, WorkDate), varianta →
  fallback řádek zboží, převod přes `"Price Includes VAT"` řádku.
- **Účtenky (orders) — ověřeno na živém API 2026-10 (PBI 63075, AC 3):** platební metoda money logu je
  **`paymentTypeId`** (pevná ID: 900000001 hotovost, 900000002 karta, 900000011 dárkový poukaz, …), ne `_paymentMethodId`
  z některých příkladů; částka `amount`, `transactionType` `SALE` / `REFUND`. **Hotovostní zaokrouhlení** = order item
  s `_productId` 0 a bitem `flags` 16 (`vat` 1); `_productId` 0 bez bitu = rychlý prodej bez produktu. **`_taxId` na order
  itemu neexistuje** — DPH jen multiplikátor `vat`. Storno = nový order se zápornými množstvími, odkaz `_sourceOrderId`
  (starší `_relatedOrderId` se pořád plní). `documentType` `CASH_IN` / `CASH_OUT` / `EXTERNAL_INVOICE_PAYMENT` nejsou
  prodej → přeskočit. Import stavěj atomicky (sestavení dokladu v codeunitu s `TableNo` přes `Codeunit.Run` po `Commit`,
  účtování a platby jako další samostatné kroky) a platby kontroluj na mapování **před** založením dokladu, jinak vznikne
  zaúčtovaná nezaplacená faktura. Zúčtovací datum účtenky hlídej proti subscriberům, co účtují k WorkDate
  (`bc-al-posting.md` 3.6j).
- **Inkrementální import orders filtruj přes `versionDate|gteq|`, ne `created|gteq|`** (ověřeno 2026-10-14): `created` =
  otevření účtenky, `completed` = dokončení, `versionDate` = zápis na serveru (~200 ms po dokončení; BC-DEV účtenka
  otevřená 7 minut). S `created` a watermarkem se ztratí účtenka otevřená před během a dokončená po něm (zaparkovaný stůl)
  i účtenka nahraná offline pokladnou později. Podle docs.api.dotypos.com/entity/order jsou `versionDate`, `completed`,
  `created`, `updated`, `canceledDate` filtrovatelné číselnými operátory a řaditelné. Daň: změněné starší účtenky
  (originál po stornu) přijdou znovu → deduplikace přes import log a klíč na `Order Id` v hlavičkách dokladů. Watermark
  posouvej po každém úspěšném čtení API a selhané účtenky opakuj z uloženého JSON — watermark držený „do běhu bez
  chyb" jedna trvale vadná účtenka zmrazí a každý běh pak stahuje celou historii od ní.
- **EANy produktu = pole `ean[]`, které PUT celé přepíše** → zúžení výběru (jen čárové kódy jedné MJ) řeš na zdroji,
  ne odebíráním z hotového pole: další subscriber téhož „after" eventu (aktivační kód poukazu) by se se smazáním
  srazil podle pořadí subscriberů. Konektor má proto event `OnAfterSetProductEanFilters(ItemNo, VariantCode, var
  ItemReference)` před `FindSet` a zákaznická appka jen přidá filtr (Sonnentor: FlowField `Item Reference."Packaging
  Type SON"` = Consumer, lookup do Item UoM podle MJ odkazu; odkaz bez MJ tím vypadne). **Skrytý produkt
  (`display: false`) sync neposílá, jen ho skryje** → v adminu Dotykačky si nechá staré EANy a ceny; při ověřování
  změny payloadu kontroluj jen zobrazené produkty. (PBI 63075 / Task 63116, ověřeno na BC-DEV 2026-10-16.)
- **Účtenku v Dotykačce smazat nejde** – vydaná účtenka je daňový doklad, pokladna ji umí jen stornovat a storno je
  **nový order** (záporné množství, `_sourceOrderId`), který import natáhne taky. API docs nemají u orders DELETE; článek
  podpory „Vymazat data“ (historie bez produktů) je starý a dnes 404. **Nové prostředí na stejném cloudu** (BC-TEST po
  BC-DEV): prázdný watermark = první import stáhne celou historii, testovací účtenky z DEV mají ID produktů, které si
  TEST při synchronizaci založil znovu → *Selhalo* a opakování z uloženého JSON napořád. Mazání v Dotykačce by
  nepomohlo (retry čte Import Log, ne API) → v konektoru akce *Ignorovat účtenku* (Failed / Imported bez dokladu →
  Skipped, nevratné). ⚠️ Při zavádění „ignore“ stavu zkontroluj navazující toky: `CheckCancelledReceiptPosted` pouštěl
  storno přeskočeného originálu dál bez vyrovnání → ignorovaný prodej by dostal dobropis; proto `GetSkipReason`
  přeskočí i storno přeskočené účtenky. (prod-ess-dotykackaConnector-bc, Sonnentor BC-TEST, 2026-10-20.)
- **Volba v administraci ↔ pole API produktu – dokumentace API to neříká, ověř ve zdrojáku adminu.** Ověřeno
  29. 10. 2026 (admin.dotykacka.cz 26.10.2): zaškrtávátko *Neaplikovat hromadné slevy* (detail produktu, záložka
  *Ceny*; manuál: na produkt se nikdy nezapočítá sleva na celý účet) se vykresluje jako **`checked: !discountPermitted`**
  → `discountPermitted: false` = zaškrtnuto (pozor, obrácená logika). *Při prodeji pod sklad* (záložka *Sklady*) =
  `stockOverdraft`: `ALLOW` *Vždy povolit prodej*, `DISABLE` *Nikdy nepovolit prodej*, `WARN` *Zobrazit pouze
  upozornění*. Postup bez zápisu do dat: přihlášený admin je React; v DevTools / JS projdi
  `performance.getEntriesByType('resource')`, stáhni `*.js` a překlad `product.json`, najdi český popisek → klíč
  (`disableGroupDiscounts`) → v bundlu kontext `t("product:<klíč>")` ukáže navázané pole. Síťové requesty adminu přes
  Claude in Chrome vidět nejsou (data jdou mimo zachycené XHR) a výstup s úryvky bundlu filtr nástroje blokuje
  („Cookie/query string data“) → ulož do `window.__x` a vypisuj očištěné (jen písmena/čísla). Nastavení produktu
  konektor posílá při **každé** synchronizaci → ruční změna v adminu vydrží jen do dalšího běhu; per produkt jen eventem
  (konektor `OnAfterBuildProductJson`).
- **Poznámka:** order má `note` (≤ 1000) a order item `note` (poznámka k položce) — podle docs.api.dotypos.com, na
  živých datech Sonnentoru zatím neviděno. Konektor předává celé JSON orderu / položky v eventech účtenky → rozšíření
  si poznámku (např. číslo dárkového poukazu u položky „uplatnění poukazu“) přečte bez změny konektoru.

### 11.11 Email modul (System Application) z PTE — `Sent Email` má pole Internal, `Email Message` / `Email Recipient` jsou Internal tabulky

Z review commitu `992bc0e` (větev MPRI, cust-sonnentor-bc, Email → Power Automate, 2026-10-20; ověřeno alc 17 proti
System Application 28.5):

- **Tabulka `Sent Email` (8889) je `Access = Public`, ale všechna pole kromě `Id` mají `Access = Internal`** („marked as internal
  in order to prevent modifying it from code"). Z PTE tedy `Rec."Message Id"`, `"Sent From"`, `"Date Time Sent"` = `AL0161`,
  `ODataKeyFields = "Message Id"` = `AL0186`. **API page se `SourceTable = "Sent Email"` nejde z PTE postavit** — potřebuješ
  vlastní tabulku (fronta / buffer) plněnou subscriberem, nebo temporary API page.
- **`Email Message` (8900) a `Email Recipient` (8903) jsou `Access = Internal` tabulky** → `Record "Email Message"` v kódu
  i `tabledata "Email Message" = R` v permission setu = `AL0161`. Obsah zprávy čti výhradně přes codeunit `Email Message`
  (`Get(MessageId)`, `GetSubject`, `GetBody`, `IsBodyHTMLFormatted()`, `GetRecipients(Type, List)`); tabledata granty
  nepotřebuješ, codeunit si je deklaruje sám (`InherentPermissions`).
- **Event `Email.OnAfterEmailSent(SentEmail: Record "Sent Email")`** předá record, ze kterého z PTE přečteš jen `Id`.
  Runtime workaround: `RecordRef.GetTable(SentEmail)` + `FieldRef.Value` (Access je jen compile-time) — funguje, ale je to
  obcházení záměru modulu; čti jen, nikdy nezapisuj, a drž to v jedné proceduře s komentářem. Pole: 2 `Message Id` (Guid),
  7 `Date Time Sent`, 13 `Sent From` (Text[250]). Subscriber běží v session Email Dispatcheru (background task), ne v UI.
  **Lepší než RecordRef:** `Sent Email` má veřejné procedury `GetMessageId()` a `GetAccountId()` (w1-28, bez Access/Scope) →
  `SentEmail.GetMessageId()` a zbytek přes codeunit `Email Message` (`Get`, `GetSubject`, `GetBody`, `IsBodyHTMLFormatted`,
  `GetRecipients`); `Sent From` / `Date Time Sent` zůstávají jen přes RecordRef (ověřeno alc 17 + al-mcp, 2026-10-29).
- **Vazba e-mailu na doklad / příležitost neparsuj z předmětu — je v tabulce `Email Related Record` (8909), která je Public**
  (bez `Access`, jen `InherentPermissions = X`; tabledata R si dej do permission setu). Klíč `Email Message Id` + `Table Id` +
  `System Id` (+ `Relation Type` Primary/Related, `Relation Origin`). Standardní odeslání prodejní nabídky e-mailem tam zapíše
  `Sales Header` (36) jako Primary → `SalesHeader.GetBySystemId` → `"Opportunity No."`. (cust-sonnentor-bc 67411, 2026-10-29.)
- `using System.Email;` v appce bez `namespace` = `warning AL0789` (direktivy se ignorují) → s Essence `failOn warning`
  shodí CI; buď celá appka na namespaces, nebo `using` vynech.
- Pro notifikaci do Power Automate platí 11.6: `[ExternalBusinessEvent]` (preview, Dataverse + Virtual Table appka, Dataverse
  trigger) vs. vlastní fronta + API page + BC trigger „When a record is created (V3)". Sonnentor má Dataverse (SON CDS Sync), takže
  prerekvizity business eventů tam odpadají; i tak je fronta jednodušší na test (tabulka jde naplnit a číst v autotestu).

- **Obousměrná synchronizace prodejních objednávek (SALESORDER-ORDER / SOLINE-ORDERDETAIL): „při kolizi vyhrává BC“ =
  `Update-Conflict Resolution := "Send Update to Integration"` v subscriberu na `CRM Setup Defaults.
  OnResetBidirectionalSalesOrderMappingOnAfterInsertFieldsMapping` / `…SalesOrderLineMappingOnAfterInsertFieldsMapping`**
  (w1-28 `Integration/D365Sales/CRMSetupDefaults.Codeunit.al`; obyčejné `[IntegrationEvent(false, false)]`, z Cloud appky jdou
  odebírat, i když `ResetBidirectionalSalesOrderMapping` sama má `[Scope('OnPrem')]`). Standard nechává u hlavičky update
  i deletion konflikt `None` (= záznam změněný na obou stranách skončí chybou synchronizace), u řádku jen
  `Deletion-Conflict = Remove Coupling`; směr nech `Bidirectional`, aby šly obě větve. Eventy pálí z `ResetSalesOrderMappingConfiguration`
  (zapnutí *Bidirectional Sales Order Int. Enabled* na CRM Connection Setup) i z „Use Default Synchronization Setup“ — **existující
  mapování se nezmění**, dokud se setup znovu neresetuje nebo se pole nepřepíše ručně na Integration Table Mappings. Guard na dvojici
  tabulek (`Sales Header`/`CRM Salesorder`, `Sales Line`/`CRM Salesorderdetail`), testy s `RegisterTableConnection('@@test@@')`
  + `Integration Table Mapping.CreateRecord` nad proxy tabulkami bez Dataverse. (cust-soitron-bc CDS.W1
  `CDS Management CWSOI.SetSalesOrderMappingToPreferBCOnUpdateConflict`, 2RING DEV, 2026-10-22.)
- **Víc konfiguračních šablon na jednom mapování (sloupec *Table Config Templates* na Integration Table Mappings) =
  tabulka `Table Config Template` (5325; pro Dataverse stranu `Int. Table Config Template` 5326), ne pole
  `Table Config Template Code` mapování.** Engine (`Integration Rec. Synch. Invoke.FindTableConfigTemplate`, w1-28) čte
  záznamy mapování (`Parent Name`, jinak `Name`) podle `Priority` vzestupně, uložený *Integration Table Filter* aplikuje
  `SetView` na RecordRef integrační tabulky + `SetRange` na UID pole (`AccountId`) a první neprázdný výsledek dá kód;
  prázdný filtr vyhrává hned, bez shody se šablona nepoužije (žádný fallback na pole mapování). Chybějící `Config.
  Template Header` = `SynchAction::Fail` daného záznamu; pole `Table Config Template Code` šablony **nemá OnValidate**,
  takže přímé přiřazení existenci hlavičky nekontroluje. `Integration Table Mapping.OnDelete` šablony mapování maže
  (pokud není ruční `Man. Integration Table Mapping` téhož jména) → při „Use Default Synchronization Setup“
  (`CreateRecord` = Get → Delete) zmizí a musí se v subscriberu `OnAfterReset…Mapping` založit znovu: `DeleteAll` podle
  jména mapování + `Init`, `Table ID` / `Integration Table ID` z mapování, `Priority` 1..n, filtr přes
  `SetIntegrationTableFilter(GetTableFilterFromView(...))` (stejný `FilterPageBuilder` round-trip jako u filtru
  mapování; `GetView` z typovaného `CRMAccount.SetFilter`), `Insert(false)` (`No.` AutoIncrement). Priority nastav
  explicitně — všechny 0 = nedefinované pořadí. Test bez Dataverse: temp `CRM Account` s `AccountId` + stejná smyčka
  SetCurrentKey(Priority) / SetView / SetRange / IsEmpty nad šablonami. Vzor: cust-soitron-bc CDS.W1
  `CDS Management CWSOI.ResetCustomerConfigTemplates` (CUST_DOM SK / CUST_EU / CUST_EXP podle `ebs_countrycode`;
  task 67287, 2026-10-22).
- **Produkt na řádku účtované faktury (POSTEDSALESLINE-INV) není field mapping, řeší ho kód — a tiše spadne na write-in.**
  Mapování `Sales Invoice Line` → `CRM Invoicedetail` má jen Quantity / slevu / cenu / částky (`CRM Setup Defaults.
  ResetSalesInvoiceLineInvoiceMapping`). `ProductId` dosadí `CRM Int. Table. Subscriber.UpdateCRMInvoiceDetailsBeforeInsertRecord`
  → `InitializeCRMInvoiceLineWithProductDetails` → `FindCRMProductId`, a jen jednou při založení řádku (řádky faktury se posílají
  synchronně z `UpdateCRMInvoiceAfterInsertRecord` hlavičky; modify cesta přepočítává jen částky, produkt už nikdy). Prázdný
  GUID = řádek jako **write-in product** (`IsProductOverridden = true`, `ProductDescription = 'No. Description.'`), bez chyby:
  (a) `Type` není Item ani Resource (G/L účet, poplatek, komentář), (b) `Sales & Receivables Setup."Write-in Product No."` =
  číslo řádku, (c) zboží nespárované a **mimo BC filtr ITEM-PRODUCT** (standard `Blocked = false`), (d) žádné mapování
  Item ↔ CRM Product (`FindMapping`). Nespárované zboží **uvnitř** filtru se naopak spáruje za běhu (`SynchRecordIfMappingExists`)
  nebo shodí celou fakturu chybou. Řádek objednávky (SOLINE-ORDERDETAIL) má oproti tomu field mapping `No. → ProductId` přes
  spárování při každé synchronizaci, proto tam produkt je a na faktuře ne. Dodatečné spárování zboží existující řádky faktury
  v Dataverse nespraví — vazbu faktury zrušit a poslat znovu. (w1-28, cust-soitron-bc 2RING DEV, 2026-10-23.)
