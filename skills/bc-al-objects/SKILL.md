---
name: bc-al-objects
description: >-
  BC/AL specifické objekty a API (sekce 5): All Profile, Upgrade Tag, No. Series GetNextNo vs PeekNextNo,
  kontrola Document No., Unix timestamp/UTC, NMEBS vazba SO↔VZ, al-mcp ByReference past, atributy zboží, DateFormula limity, CaptionClass + Translation
  Helper, CZ↔EN terminologie, CZZ zálohy, Attached to Line No. parent↔child (xRec, Validate(No.) Init,
  CurrFieldNo), Requisition Line (GetDirectCost, Make Order, Order Planning, Carry Out, Calculate Plan bez dotazu),
  IsPriceUpdateNeeded (cena po odpojení HNO), VerifyOnInventory,
  Item Jnl. Line UoM qty-per, Auto Format částek, Item Charge Assignment, Job Queue z účtování / recurring,
  Data Exchange / camt.053 (merge sloupců, Regex Match), Bin Code na řádcích SO/PO → Whse. Receipt/Shipment Line
  (OnAfterGetDefaultBin, Validate Bin Code = Message). Načti u číselných řad, výroby, plánování, Job Queue,
  bankovního importu, přihrádek. (Shopify, HttpClient → bc-al-integrations; Job Planning Line /
  projekty → bc-al-projects; Item Tracking / šarže / SN → bc-al-tracking.)
user-invocable: true
---

# BC/AL — Specifické objekty & API (sekce 5)

**Zdroj pravdy:** `bc-al-objects.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury, tabulky (CZ↔EN termíny, posting
cesty) a příklady jsou v souboru.

## Co udělat

1. **Přečti `bc-al-objects.md` z adresáře tohoto skillu celý.** Vejde se do jednoho Read
   (~700 řádků / 44 KB, po vyčlenění Shopify + SaaS do `bc-al-integrations.md`
   2026-09-08); když se výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení
   nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: Shopify Connector, HttpClient/SecretText na SaaS, Power
   Automate → `bc-al-integrations` (5.y2, 11); projekty / Job Planning Line → `bc-al-projects` (5.x17–5.x20); Item Tracking
   (šarže, SN, Item Tracking Lines, Reservation Entry) → `bc-al-tracking` (5.x, 5.x2, 5.x2b, 5.x15); subscribery a propagace polí →
   `bc-al-data`; Cloud target patterny obecně → `bc-al-style` (10); ověření
   signatur z .app → `bc-al-tools` (7.2, 7.6).

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
- **5.x / 5.x2 / 5.x2b / 5.x15** Item Tracking → skill `bc-al-tracking` (vyčleněno 2026-10-07).
- **5.x3** NMEBS: vazba SO řádek ↔ VZ řádek jen přes `Sales Production Ref. NMEBS`.
- **5.y** al-mcp `ByReference` u event parametrů **nevěřit** → ověř zdroják
  z `.app` (`unzip`).
- **5.w** Filtrování zboží podle atributů = base app (`Item Attribute
  Management.FindItemsByAttributes`, page 7506, mapping 7505); persistuj
  ID + jméno.
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
