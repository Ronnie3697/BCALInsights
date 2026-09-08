---
name: bc-al-objects
description: >-
  BC/AL specifické objekty, API a SaaS gotchas z praxe (Business Central):
  All Profile, Upgrade Tag, No. Series GetNextNo vs PeekNextNo, kontrola
  Document No. (Batch simulation, per Posting Date), Unix timestamp, Item
  Tracking (výběr šarže, Reservation Entry u Prod. Order Line, Sales Quote),
  NMEBS vazba SO ↔ VZ, al-mcp ByReference past, atributy zboží, Shopify
  varianty (sync vs Add Item, userErrors), DateFormula, CaptionClass +
  Translation Helper, CZ↔EN terminologie, CZZ Advance Payments, Attached to
  Line No. parent↔child (xRec/OnAfterModify, CurrFieldNo, číslování, Copy
  Document), Requisition Line OnAfterGetDirectCost, Req. Wksh.-Make Order,
  VerifyOnInventory, Item Jnl. Line qty-per, Auto Format <C,> prefix /
  částky v textu; HttpClient na SaaS, Windows auth OnPrem, Isolated Storage
  scope, SecretText Unwrap/SecretStrSubstNo, Business Events preview vs API
  page + Power Automate. Načti při práci s číselnými řadami, item
  trackingem, výrobou, Shopify, HTTP/secrets na Cloud targetu, překladu BC
  termínů.
user-invocable: true
---

# BC/AL — Specifické objekty, API & SaaS gotchas (sekce 5, 11)

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\bc-al-objects.md`
(v repu `../../bc-al-objects.md` relativně k tomuto skillu). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury, tabulky (CZ↔EN termíny, posting
cesty) a příklady jsou v souboru.

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\bc-al-objects.md` celý.** Soubor (~830 řádků / 57 KB)
   **přesahuje cap jednoho Read** (~25k tokenů) — první Read skončí kolem 5.x5,
   **vždy** navaž druhým Read s `offset` na zbytek (5.x5–5.x7, 11.x). Bez
   přečtení nejednej.
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
- **5.x2b** Item Tracking na **Sales Quote** je standard (`Reservation Entry`
  Source Type 37, Subtype 0), Make Order ho přenese na SO → žádné vlastní pole,
  čti 337/336.
- **5.x3** NMEBS: vazba SO řádek ↔ VZ řádek jen přes `Sales Production Ref. NMEBS`.
- **5.y** al-mcp `ByReference` u event parametrů **nevěřit** → ověř zdroják
  z `.app` (`unzip`).
- **5.w** Filtrování zboží podle atributů = base app (`Item Attribute
  Management.FindItemsByAttributes`, page 7506, mapping 7505); persistuj
  ID + jméno.
- **5.y2** Shopify Connector BC28: `Available For Sales` je BC-only mirror;
  export varianty nemaže; create varianty nejde zablokovat. **Nové varianty
  existujícího produktu zakládá jen produktový sync** (`Sync Item = To Shopify`
  + `Can Update Shopify Products`), Add Item existující produkt přeskočí;
  `userErrors` = tiché nic (Shopify Log Entries); produkt založený bez options
  varianty už nedostane. Add z karty zboží obchází report 30106 → item-level
  kontrola v `OnAfterCreateTempShopifyProduct` (prázdný buffer variant =
  `Error`, jinak `CreateProduct` spadne na `FindSet`). Lokální rozcestník
  `C:\WorkTasks\BCShopifyConnectorDocs`.
- **5.z** DateFormula: půlrok **nejde** → enum + zaokrouhlení v kódu.
- **5.z2** CaptionClass resolver respektuj `Language` přes `Translation
  Helper` (53), ne holý `GlobalLanguage()` (LC0022).
- **5.z4** CZ ↔ EN termíny podle tabulky v souboru (Zboží = Item, Přihrádka =
  Bin, Šarže = Lot, Montáž = Assembly…), ne doslovný překlad ze slovníku.
- **5.z3** CZZ: vazba záloha ↔ doklad v `Advance Letter Application CZZ`;
  scoped guard přes `EventSubscriberInstance = Manual` + `BindSubscription`;
  v guardu `IsTemporary()` exit (dialog jede nad temp buffery téže tabulky).
- **5.x4** `Attached to Line No.` (80): posting bez kontroly, kaskádní delete
  a delete při změně `No.` hlavního řádku (jen ze subformu). Vlastní
  parent↔child: přepočet dětí v `OnAfterModify` (`Rec` vs `xRec`, bez Modify
  parenta), `Validate("No.")` pole 80 **neobnoví** → obnov z `xRec`; dotaz
  uživateli jen při `CurrFieldNo = FieldNo(X)` (z kódu 0) + `Error('')` po
  odmítnutí; **číslování dětí do mezery pod parent** (vzor extended textů,
  fallback poslední + 10000); Copy Document přemapuj
  v `OnAfterCopySalesLineExtText` (před Insert).
- **5.x5** `Requisition Line.OnAfterGetDirectCost` běží vždy na konci
  (filtruj sám); `Req. Wksh.-Make Order` maže řádek sešitu až ve
  `FinalizeOrderHeader` → dvojí započtení; carry-out bere celý batch.
- **5.x6** Consumption (i Assembly) / Transfer nikdy do mínusu bez ohledu na Prevent
  Negative Inventory (`VerifyOnInventory`); `Validate("Unit of Measure Code")`
  přepíše `Qty. per Unit of Measure` → vlastní qty-per až po něm + `Validate(Quantity)`.
- **5.x7** Částky v textu (e-mail, CSV): `Auto Format.ResolveAutoFormat` vrací
  `<C,CZK>` prefix (jen pro page fieldy) → formát `<Precision,x:y><Standard
  Format,0>` slož sám z `Currency."Amount/Unit-Amount Decimal Places"` /
  GL Setup (`Currency.Initialize('')` decimal places **neplní**).
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
- **11.6** Notifikace do Power Automate: External Business Events = **preview**
  + Dataverse prerekvizity (nenacenit jako levné) → pragmaticky queue tabulka
  + API page + BC trigger „When a record is created (V3)"; HTTP trigger v PA
  je Premium.
