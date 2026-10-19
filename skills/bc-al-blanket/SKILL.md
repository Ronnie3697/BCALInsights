---
name: bc-al-blanket
description: >-
  BC/AL hromadné objednávky, sešit požadavků a přepočet ceny (Business Central, sekce 5.x5, 5.x9, 5.x21):
  hromadné nákupní / prodejní objednávky HNO/HPO (Blanket Order No. / Line No.) – vazba řádků NO/PO/sešitu,
  převzetí ceny a slevy (BlanketOrderIsRelated), ruční navázání = vnořený Validate(Quantity), změna varianty
  navázaného řádku, Recreate Purch/Sales Lines (TestField Blanket Order No. před přegenerováním,
  OnAfterRecreate…Line), změny z hlavičky jen ze stránky (CurrFieldNo, GuiAllowed, Link Doc. Date To Posting
  Date při účtování); Requisition Line OnAfterGetDirectCost, Req. Wksh.-Make Order / Carry Out (dvojí
  započtení, CopyOrderDateFromPurchHeader na kopii), Calculate Plan bez dotazů (manual bind, report 699);
  přepočet ceny bez ceníku (IsPriceUpdateNeeded, ruční Line Discount % nepřežije); poptávka → Requisition
  Line → Purchase Line a přenos vlastních polí (Order Planning, Get Sales Orders, Calculate Plan, NMEBS).
  Načti u HNO/HPO, sešitu požadavků, plánování a přecenění řádků dokladu.
user-invocable: true
---

# BC/AL — Hromadné objednávky, sešit požadavků a přepočet ceny (sekce 5.x5, 5.x9, 5.x21)

**Zdroj pravdy:** `bc-al-blanket.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů a příklady jsou v souboru.
Vyčleněno z `bc-al-objects.md` 2026-10-19, číslování 5.x je původní.

## Co udělat

1. **Přečti `bc-al-blanket.md` z adresáře tohoto skillu celý.** Je krátký (~175 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: Attached to Line No., Job Queue, NMEBS vazba SO↔VZ a ostatní objekty → `bc-al-objects`; cena
   rámcovky na kopii dokladu a propagace vlastních polí do účtovaných dokladů → `bc-al-posting`; `CurrFieldNo`
   z codeunity, příznak v SingleInstance po `Error` a subscribery → `bc-al-data` (3.9, 3.10); `DelayedInsert` / prázdné
   `SystemId` na subformu → `bc-al-ui`; testy plánování / sešitu požadavků (Carry Out vlastní batch, Calculate Plan
   report 699, Req. Worksheet TestPage) → `bc-al-autotests-domains` (spolu s `bc-al-autotests`).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **5.x5** `Requisition Line.OnAfterGetDirectCost` běží vždy na konci `GetDirectCost` (i mimo Purchase → filtruj sám);
  sešit nemá ochranu `BlanketOrderIsRelated` → vlastní cenu obnov po každém `GetDirectCost`. `Req. Wksh.-Make Order`
  maže řádek sešitu až ve `FinalizeOrderHeader` → dvojí započtení; Carry Out bere celý batch. „Během Calculate Plan
  se neptej" = manual bind v `reportextension` na report 699 (v `OnPreReport` nejdřív `if UnbindSubscription(X) then;`),
  ne SingleInstance příznak.
- **5.x9** Vlastní pole z poptávky na řádek sešitu: každá cesta má jiný hook (Order Planning
  `OnAfterTransferFromUnplannedDemand`, Get Sales Orders `OnBeforeInsertReqWkshLine`, Calculate Plan
  `OnMaintainPlanningLineOnBeforeReqLineInsert` jen u Order-to-Order, Carry Out
  `OnInsertPurchOrderLineOnAfterTransferFromReqLineToPurchLine`); NMEBS *Transfer Lines to Plan* skládá řádek sám.
- **5.x21** Bez řádku ceníku `IsPriceUpdateNeeded` cenu při změně `Quantity` nepřepíše → odpojený řádek si nechá cenu
  HNO/HPO; standardní cenu spočítej na temporary kopii (`UpdateDirectUnitCost` / `UpdateUnitPrice(FieldNo("No."))`).
  Ruční `Line Discount %` změnu Množství / Varianty nepřežije (`ApplyDiscount` → 0) → ulož předem a vrať.
- **5.x21 HNO/HPO** Ruční navázání přes `Blanket Order Line No.` spustí vnořené `Validate(Quantity)` už s novou vazbou →
  rekontroluj jen vazbu, kterou měla uložená verze. Změnu `Variant Code` navázaného řádku standard nehlídá. Odsouhlasení
  ber z dat, ne z cache klíčované `SystemId` (`DelayedInsert` → prázdné); pamatuj jen odpovědi, které stav řádku nemění.
- **5.x21 Recreate / hlavička** `Recreate{Purch,Sales}Lines` s navázaným řádkem spadne na `TestField("Blanket Order No.", '')`
  (běží po `OnBeforeRecreate…Lines`) → vazby ulož stranou a odpoj, po `OnAfterRecreate…Line` rozhodni znovu (ne `IsHandled`).
  `Posting Date` → `Document Date` (*Link Doc. Date To Posting Date*) validuje i účtování nad otevřeným dokladem → kontroly
  řádků z hlavičky jen ze stránky (`CurrFieldNo <> 0` + `GuiAllowed()`). Carry Out `CopyOrderDateFromPurchHeader` validuje
  `Order Date` na kopii řádku sešitu → `OnBeforeCopyOrderDateFromPurchHeader` + výpočet na temporary kopii.
