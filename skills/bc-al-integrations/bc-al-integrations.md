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
- **11.** SaaS gotchas — HttpClient, SecretText, Isolated Storage, Business Events / Power Automate

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
  `IsTestInProgress`. Per-variant filtrování create path = jedině PR do microsoft/BCApps.
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
  Lokální rozcestník konektoru (DNEM, GitHub `Ronnie3697/BCShopifyConnectorDocs`, generovaný z w1-28): `C:\WorkTasks\BCShopifyConnectorDocs`
  — `shopify_codeunits|tables|pages|reports.md` (ID → název → GitHub link), `shopify_functional_breakdown.md`,
  `VersionChanges/Changes27-28.md` + `Changes28.md` (minor diffy), update přes `python scratch/update_docs.py`.

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
