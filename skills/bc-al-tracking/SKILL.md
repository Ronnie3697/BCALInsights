---
name: bc-al-tracking
description: >-
  BC/AL Item Tracking (Business Central — šarže Lot No., sériová čísla Serial No., Reservation Entry 337, Tracking
  Specification 336; sekce 5.x, 5.x2, 5.x2b, 5.x15): stránka Item Tracking Lines (6510) a její eventy pro ruční řádek
  (OnBeforeOnInsertRecord / OnBeforeOnModifyRecord), Assign Serial No. a Create Customized SN (OnAfterAssignNewTrackingNo),
  předvyplnění šarže (šarže = číslo projektu, zadání SN šarži maže přes FindLotNoBySNSilent), SN zboží bez automatického
  řádku, přepis Lot No. při změně projektu, vlastní výběr šarže z akce na 6510 (Item Tracking Summary nerozšiřovat),
  source pole u Prod. Order Line (Source Prod. Order Line), tracking na Sales Quote (Prospect vs Surplus,
  IsOrderNetworkEntity), tracking na fakturačním řádku z Get Shipment Lines (jen Prospect), PC0013 Get s Integer do
  enum PK, TestPage handlery Enter Quantity to Create / Enter Customized SN. Načti u šarží, sériových čísel,
  Item Tracking Lines, Reservation Entry a jednostranného trackingu na dokladech.
user-invocable: true
---

# BC/AL — Item Tracking: šarže, sériová čísla, Reservation Entry (sekce 5.x, 5.x2, 5.x2b, 5.x15)

**Zdroj pravdy:** `bc-al-tracking.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů a příklady jsou v souboru.
Vyčleněno z `bc-al-objects.md` 2026-10-07, číslování 5.x je původní.

## Co udělat

1. **Přečti `bc-al-tracking.md` z adresáře tohoto skillu celý.** Je krátký (~190 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: ostatní objekty (No. Series, Requisition Line, Job Queue, NMEBS vazba SO↔VZ) → `bc-al-objects`;
   propagace polí Sales Line → Item Jnl. Line → ILE a Job No. dodávka vs. faktura → `bc-al-posting`; subscribery →
   `bc-al-data`; testy přes TestPage a handlery → `bc-al-autotests`; ověření `var` u event parametrů ze zdrojáku .app →
   `bc-al-tools` (7.6) a `bc-al-objects` (5.y).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **5.x** Výběr šarže nerozšiřuj v `Item Tracking Summary` (6500 nad `Entry Summary` 338 bez Item No.) → vlastní výběrová
  page z akce na `Item Tracking Lines` (6510) + temp buffer + `CurrPage.Update(true)`.
- **5.x2** Tracking řádku VZ má `Source Ref. No. = 0`, číslo řádku je v `Source Prod. Order Line` (komponenty naopak).
- **5.x2b** Tracking na nabídce / rámcové objednávce má status **Prospect**, Surplus jen Order / Return Order
  (`IsOrderNetworkEntity`); filtry na vlastní tracking `Surplus|Prospect`. Make Order ho přenese na SO.
- **5.x15** Fakturační řádek z Get Shipment Lines smí mít jen Prospect z dodávky → subscriber na `Validate(Quantity)` guard
  `Shipment No.` / `Return Receipt No.` (nákup `Receipt No.` / `Return Shipment No.`).
- **5.x15b** Stránka 6510 je temp (`IsTemporary` guard nepatří); šarži do ručních řádků dávej v `OnBeforeOnInsertRecord` +
  `OnBeforeOnModifyRecord` (zadání SN ji přes `FindLotNoBySNSilent` vymaže a modify ji vrátí), do generovaných SN
  v `OnAfterAssignNewTrackingNo` (FieldID Serial No.); SN zboží žádný automatický řádek; `Get` s Integer do enum PK =
  PC0013 → `Enum::"…".FromInteger`.
