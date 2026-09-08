---
name: bc-al-integrations
description: >-
  BC/AL integrace a SaaS/Cloud gotchas z praxe (Business Central, AL; 5.y2 +
  sekce 11, vyčleněno z bc-al-objects): Shopify Connector BC28 (Available
  For Sales BC-only mirror, export varianty nemaže, nové varianty zakládá
  jen produktový sync s Can Update Shopify Products, Add Item existující
  produkt přeskočí, userErrors = tiché nic, produkt bez options, filtrování
  v OnAfterCreateTempShopifyProduct, Add z karty zboží obchází report 30106,
  lokální docs BCShopifyConnectorDocs), HttpClient na SaaS (Allow HttpClient
  Requests silent fail, UseDefaultNetworkWindowsAuthentication OnPrem-only,
  User-Agent), Isolated Storage scope, SecretText (Unwrap OnPrem-only
  AL0296, HMAC přes Cryptography Management, SecretStrSubstNo jen s Text
  proměnnou), External Business Events preview + Dataverse vs queue tabulka
  + API page + Power Automate trigger. Načti při práci se Shopify, HTTP
  voláními, OAuth/secrets na Cloud targetu, notifikacemi do Power Automate,
  Cloud-only omezeními.
user-invocable: true
---

# BC/AL — Integrace & SaaS/Cloud gotchas (5.y2, sekce 11)

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\bc-al-integrations.md`
(v repu `../../bc-al-integrations.md` relativně k tomuto skillu). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů konektoru, GraphQL chování a příklady
jsou v souboru. Vyčleněno z `bc-al-objects.md` 2026-09-08, číslování je původní.

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\bc-al-integrations.md` celý.** Vejde se do jednoho Read;
   když se výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: ostatní specifické objekty (No. Series, Item Tracking, Attached
   to Line No.…) → `bc-al-objects` (5); moderní patterny a Cloud target obecně →
   `bc-al-style` (10); zdroják Shopify konektoru (microsoft/BCApps) a ověření
   signatur → `bc-al-tools` (7.2, 7.3); API page / notifikace testy → `bc-al-autotests`.
   Oficiální BC MCP server (data z BC přes API pages) → draft `bc-al-mcp-server.md`.

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **5.y2** Shopify Connector BC28: `Available For Sales` je BC-only mirror;
  export varianty nemaže; create varianty nejde zablokovat. **Nové varianty
  existujícího produktu zakládá jen produktový sync** (`Sync Item = To Shopify`
  + `Can Update Shopify Products`), Add Item existující produkt přeskočí;
  `userErrors` = tiché nic (Shopify Log Entries); produkt založený bez options
  varianty už nedostane. Add z karty zboží obchází report 30106 → item-level
  kontrola v `OnAfterCreateTempShopifyProduct` (prázdný buffer variant =
  `Error`, jinak `CreateProduct` spadne na `FindSet`). Lokální rozcestník
  `C:\WorkTasks\BCShopifyConnectorDocs`.
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
