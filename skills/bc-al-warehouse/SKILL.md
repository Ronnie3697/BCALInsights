---
name: bc-al-warehouse
description: >-
  BC/AL sklad (5.x22, 5.x26–5.x28, 5.x34, 5.x35): Bin Code SO/PO → Whse. Receipt / Shipment (GetDefaultBin,
  OnAfterGetDefaultBin, Receipt/Shipment Bin Code, OnBeforeWhseReceiptLineInsert, Validate Bin Code = Message); přesun /
  vyskladnění z kódu (Bin Code na Take bez kontrol, CalcQtyAvailToPick vs CalcQtyAvailToTake, Whse.-Act.-Register
  (Yes/No) pár Take/Place, Split Line); jiná MJ bez Directed Put-away (Warehouse Entry a Bin Content v základní
  MJ, Whse. Jnl.-Register Line, UseBaseQty, CalcBaseQty); nový řádek deníku zboží (SetUpNewLine); skladový doklad v jiné
  MJ než zdroj (Sales/Purchases/Transfer Warehouse Mgt. BC 29, Whse.-Post Receipt / Shipment, Pick Qty., Qty.
  Picked, Allow Whse. Overpick, inventura v základní MJ, Phys. Invt. Order, Qty. Rounding Precision, Put-away Unit of
  Measure Code, OnAfterGetHandheldUoM); nákup s projektem bez spotřeby (RevertWarehouseEntry,
  ConsumeWarehouseEntryForJobPurchase, IsReceiptForJob). Načti u přihrádek, skladových dokladů a aktivit, MJ ve skladu,
  inventury a čteček.
user-invocable: true
---

# BC/AL — Sklad: přihrádky, skladové doklady a aktivity, MJ ve skladu (sekce 5.x22, 5.x26–5.x28, 5.x34)

**Zdroj pravdy:** `bc-al-warehouse.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů a příklady jsou v souboru.
Vyčleněno z `bc-al-objects.md` 2026-11-19, číslování 5.x je původní (čísla 5.x22 / 5.x26–5.x28 mají i `bc-al-tracking.md`
a `bc-al-projects.md` s jiným obsahem — odkazuj i se jménem souboru).

## Co udělat

1. **Přečti `bc-al-warehouse.md` z adresáře tohoto skillu celý.** Je krátký (~180 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: `VerifyOnInventory`, qty-per na Item Journal Line (5.x6), CZ ↔ EN termíny skladu (5.z4) a ostatní objekty →
   `bc-al-objects`; fyzická inventura se šaržemi, tracking na příjemce → `bc-al-tracking`; vlastní pole Sales Line → Whse.
   Shipment → `bc-al-posting`; stránky phone klientu a čtečky (dlaždice, sken ze schované stránky) → `bc-al-ui-phone`; signatury
   eventů ze zdroje `.app` → `bc-al-tools` (7.6).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **5.x22** Přihrádku řádku SO/PO počítá `GetDefaultBin` (hook `OnAfterGetDefaultBin`); prodejní řádek ji při `Require Shipment`
  + `Shipment Bin Code` nenastaví. Do skladového dokladu jde přihrádka z hlavičky (Receipt / Shipment Bin Code), řádek
  objednávky jen jako fallback → vlastní přihrádku dosaď v `OnBeforeWhseReceiptLineInsert` / `OnBeforeWhseShptLineInsert`.
  `Validate("Bin Code")` na řádku objednávky z kódu = `Message` (test chce `[MessageHandler]`).
- **5.x26** `Validate("Bin Code")` na řádku Take z kódu (`CurrFieldNo = 0`) přeskočí všechny kontroly → zrcadli base (MJ podle
  `GetUOMCode`, `CalcQtyAvailToPick` vs. `CalcQtyAvailToTake` u Movement). Jeden pár = `Whse.-Act.-Register (Yes/No)` s filtrem
  `"Line No." = Take|Place`; Take ↔ Place nemá vazbu (`Split Line`).
- **5.x27** Lokace bez *Directed Put-away and Pick* drží Warehouse Entry i Bin Content v základní MJ → vlastní registrace
  skladového deníku v základní MJ; MJ řádků dokladů neměň, zadané množství přepočti do MJ řádku.
- **5.x28** Nový řádek deníku zboží v prázdném listu: `SetUpNewLine`, lokaci jen přiřaď, pak `Validate("Item No.")`, nakonec
  `Validate("Bin Code")`.
- **5.x34** Skladová příjemka / dodávka **zůstává v MJ zdrojového řádku** — účtování zapisuje množství v MJ skladového řádku
  bez přepočtu, vyskladnění v jiné MJ rozbije `Pick Qty.` / `Qty. Picked` (dodávka i výroba). „Sklad v kusech" = zdrojový
  řádek v kusech, nebo přepočet na čtečce. `Qty. Rounding Precision` nahoru nezaokrouhluje.
