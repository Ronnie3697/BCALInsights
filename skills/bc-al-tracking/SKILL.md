---
name: bc-al-tracking
description: >-
  BC/AL Item Tracking (šarže, sériová čísla, Reservation Entry 337, Tracking Specification 336;
  sekce 5.x–5.x22): stránka Item Tracking Lines (6510) a její eventy pro ruční řádek (OnBeforeOnInsertRecord
  / OnBeforeOnModifyRecord), Assign Serial No. / Create Customized SN (OnAfterAssignNewTrackingNo),
  předvyplnění šarže (šarže = číslo projektu, zadání SN šarži maže), SN zboží bez automatického řádku,
  vlastní výběr šarže z akce na 6510, source pole u Prod. Order Line, tracking na Sales Quote (Prospect vs
  Surplus), tracking z Get Shipment Lines (jen Prospect), PC0013 Get do enum PK, TestPage handlery Enter
  Quantity to Create, FEFO z kódu a prošlé šarže (Strict Expiration), Lot Specific vs. prodej do mínusu,
  Reservation Entry Entry No. AutoIncrement, dobropis / storno s Appl.-from Item Entry (SQNR), Item
  Jnl.-Check Line po smazání rezervací, převodka s prázdným / přepsaným Order No. = chyba New Expiration
  Date a in-transit párování. Načti u šarží, SN, Item Tracking Lines, Reservation Entry, převodek se
  sledováním.
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
- **5.x22** Převodka: `Item Journal Line."Order No."` (= číslo převodky) **nikdy nevyprázdnit ani nepřepsat** —
  `CheckExpirationDate` bez něj bere řádek jako reclass a chce `New Expiration Date` (z převodky nejde zadat), in-transit
  párování jde přes `Order Type` + `Order No.`. Vlastní reference (PO, dodavatel) = vlastní pole na Item Journal Line + ILE,
  propsat v `OnAfterInitItemLedgEntry` (běží i pro odvozenou položku).
