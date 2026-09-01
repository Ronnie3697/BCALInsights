---
name: bc-al-objects
description: >-
  BC/AL specifické objekty, API a SaaS gotchas z praxe (Business Central, AL):
  All Profile, Upgrade Tag, No. Series GetNextNo vs PeekNextNo a kontrola
  Document No. (No. Series - Batch, simulation mode, generátor řádků per
  Posting Date), Unix timestamp / UTC, Item Tracking a výběr šarže (Lot No.),
  Reservation Entry source pole u Prod. Order Line, EM Net Make to Order
  vazba SO ↔ VZ, al-mcp ByReference past, atributy zboží (Item Attribute
  Management), Shopify Connector variant sync, DateFormula limity,
  CaptionClass + Translation Helper, CZ ↔ EN terminologie BC, CZZ Advance
  Payments, Sales Line Attached to Line No., Requisition Line
  OnAfterGetDirectCost a Req. Wksh.-Make Order, VerifyOnInventory / negativní
  sklad, Item Journal Line UoM qty-per; HttpClient na SaaS (Allow HttpClient
  Requests), Windows auth OnPrem-only, Isolated Storage scope, SecretText
  Unwrap / SecretStrSubstNo. Načti při práci s těmito objekty, číselnými
  řadami, item trackingem, výrobou, HTTP a secrets na Cloud targetu, překladu
  českých BC termínů.
user-invocable: false
---

# BC/AL — Specifické objekty, API & SaaS gotchas (sekce 5, 11)

**Zdroj pravdy:** `../../bc-al-objects.md` (lokální klon
`C:\WorkTasks\BCALInsights\bc-al-objects.md`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury, tabulky (CZ↔EN termíny, posting
cesty) a příklady jsou v souboru.

## Co udělat

1. **Přečti `../../bc-al-objects.md` celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: subscribery a propagace polí → `bc-al-data`; Cloud target
   patterny obecně → `bc-al-style` (10); ověření signatur z .app → `bc-al-tools`
   (7.2, 7.6).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **5.1** `All Profile` se `Scope::Tenant` → `App ID` prázdný GUID.
- **5.2** Upgrade Tag: definice v samostatné codeunitě
  (`OnGetPerCompanyUpgradeTags`), `HasUpgradeTag` → upgrade → `SetUpgradeTag`;
  v Install `SetAllUpgradeTags()`.
- **5.3** `No. Series`: **`GetNextNo`** posune řadu (direct posting
  `RunWithCheck`, plain insert); **`PeekNextNo`** neposune (před batch post
  `Codeunit.Run("Item Jnl.-Post")`, codeunit 241).
  Chyba „Číslo dokladu musí být rovno X+1" = GetNextNo tam, kde patří Peek.
  `Codeunit.Run("Item Jnl.-Post", Rec)` chce napozicovaný Rec (`FindFirst`).
- **5.4** Kontrola Doc No. vs řada žije **jen v `*-Post Batch`**; read-only
  replika = `No. Series - Batch` (308) + `SetSimulationMode()`, nikdy
  `SaveState()`. Generátor řádků (suggest report): `PeekNextNo` **per
  `Posting Date`** (ne jednou `Today()` pro celý běh) a řádky jednoho období
  drž souvisle v pořadí účtování, jinak post spadne.
- **5.5** Unix timestamp = `CurrentDateTime() - Evaluate('1970-01-01T00:00:00Z', 9)`;
  ne přes `.Date()/.Time()` (timezone posun).
- **5.x / 5.x2** Item Tracking: nerozšiřovat `Item Tracking Summary` (page 6500
  nad `Entry Summary` 338, která nemá Item No.; event hlášen bez `var` — přeověř,
  viz 5.y) → vlastní výběrová page z akce na `Item Tracking Lines` (6510) +
  temp buffer + `CurrPage.Update(true)`. Prod. Order Line link
  přes `"Source Prod. Order Line"`, ne `Source Ref. No.` (= 0).
- **5.x3** NMEBS: vazba SO řádek ↔ VZ řádek jen přes `Sales Production Ref. NMEBS`.
- **5.y** al-mcp `ByReference` u event parametrů **nevěřit** → ověř zdroják
  z `.app` (`unzip`).
- **5.w** Filtrování zboží podle atributů = base app (`Item Attribute
  Management.FindItemsByAttributes`, page 7506, mapping 7505); persistuj
  ID + jméno.
- **5.y2** Shopify Connector BC28: `Available For Sales` je BC-only mirror;
  export varianty nemaže; create varianty nejde zablokovat; filtrování při Add
  Item přes `OnAfterCreateTempShopifyProduct`.
- **5.z** DateFormula: půlrok **nejde** → enum + zaokrouhlení v kódu.
- **5.z2** CaptionClass resolver respektuj `Language` přes `Translation
  Helper` (53), ne holý `GlobalLanguage()` (LC0022).
- **5.z4** CZ ↔ EN termíny podle tabulky v souboru (Zboží = Item, Přihrádka =
  Bin, Šarže = Lot, Montáž = Assembly…), ne doslovný překlad ze slovníku.
- **5.z3** CZZ: vazba záloha ↔ doklad v `Advance Letter Application CZZ`;
  scoped guard přes `EventSubscriberInstance = Manual` + `BindSubscription`;
  v guardu `IsTemporary()` exit (dialog jede nad temp buffery téže tabulky).
- **5.x4** `Attached to Line No.` (80): posting bez kontroly, kaskádní delete
  a delete při změně `No.` hlavního řádku.
- **5.x5** `Requisition Line.OnAfterGetDirectCost` běží vždy na konci
  (filtruj sám); `Req. Wksh.-Make Order` maže řádek sešitu až ve
  `FinalizeOrderHeader` → dvojí započtení; carry-out bere celý batch.
- **5.x6** Consumption (i Assembly) / Transfer nikdy do mínusu bez ohledu na Prevent
  Negative Inventory (`VerifyOnInventory`); `Validate("Unit of Measure Code")`
  přepíše `Qty. per Unit of Measure` → vlastní qty-per až po něm + `Validate(Quantity)`.
- **11.1** SaaS `HttpClient` vrací `false` s prázdným `GetLastErrorText()` bez
  **Allow HttpClient Requests** → čistá hláška, do README.
- **11.2** `UseDefaultNetworkWindowsAuthentication()` = OnPrem-only (compiler
  nehlásí). **11.3** Isolated Storage scope `Module` default.
- **11.4 / 11.5** `SecretText.Unwrap()` = OnPrem-only (AL0296) → co
  potřebuješ v plaintextu, nedrž jen v SecretText; HMAC bez unwrapu přes
  `Cryptography Management.GenerateHash(Text, SecretText, Option)` (vrací
  UPPERCASE hex, ne Base64). Text → SecretText **jen**
  `SecretStrSubstNo('%1', TextVar)` (literál neprojde, AL0133). V testech
  `IsEmpty()` + chování, ne obsah.
