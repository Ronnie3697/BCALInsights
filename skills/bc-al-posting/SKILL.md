---
name: bc-al-posting
description: >-
  BC/AL propagace vlastních polí do účtovaných dokladů, archivu a kopií (Business Central, sekce 3.5–3.6f):
  Sales Line → Item Jnl. Line → ILE / Whse. Shipment Line, vlastní pole Sales/Purchase Header/Line se stejným
  field ID na archive + posted tabulkách (TransferFields), total řádku při částečném účtování
  (OnAfterInitFromSalesLine, undo dodávky), AutoFormatExpression GetCurrencyCode, Validate("No.") Init() past
  (archive restore, Copy Document s Recalculate, RecreateSalesLines), OnAfterGetUnitCost, Blob pole hlavičky =
  CalcFields + subscriber na každém přenosu (Sales-Post 4× OnBefore…TransferFields, archiv + obnova,
  Quote → Order, Copy Document OnAfterCopySalesHeaderDone), délky Text polí (LC0044, PC0020), guard
  OnModifyRecord jako invarianty, kontrola dokladu OnAfterCheckSalesDoc vs OnBeforeIsApprovedForPosting, Job No.
  dodávka vs faktura. Načti u vlastních polí na dokladech, postingu, archivace, kopie dokladu a rich text poznámek.
user-invocable: true
---

# BC/AL — Propagace vlastních polí do účtovaných dokladů, archivu a kopií (sekce 3.5–3.6f)

**Zdroj pravdy:** `bc-al-posting.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů, příklady a odůvodnění jsou v souboru.
Vyčleněno z `bc-al-data.md` 2026-09-29, číslování 3.x je původní.

## Co udělat

1. **Přečti `bc-al-posting.md` z adresáře tohoto skillu celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: obecné subscriber patterny (IsTemporary, SkipOnMissing…, identifier syntax, xRec
   v modify triggerech) → `bc-al-data` (3.1–3.4, 3.7–3.9); rich text editor na stránce → `bc-al-ui`
   (4.10); testy účtování a undo → `bc-al-autotests`.

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **3.5** Propagace pole: `Sales-Post.OnPostItemJnlLineOnAfterPrepareItemJnlLine`
  → `Item Jnl.-Post Line.OnAfterInitItemLedgEntry`;
  `Sales Warehouse Mgt.OnAfterCreateShptLineFromSalesLine` (+ `Modify(false)`).
- **3.6** Vlastní pole na Sales/Purchase Header/Line → **stejné field ID a typ
  na archive + všech posted tabulkách** (TransferFields to přenese bez
  subscriberu) + pageextension na všech posted/archive page. FlowField zdroj →
  subscriber `OnAfter…Insert`. Projdi checklist v souboru. Vlastní **total
  řádku** se při částečném účtování nepřepočítá → dopočítej
  v `OnAfterInitFromSalesLine` (na všech 4 posted line tabulkách, **různé
  pořadí parametrů**) a otoč znaménko při undo
  (`OnBeforeNewSalesShptLineInsert` / `…ReturnRcptLineInsert`); test musí krýt
  částečné účtování + undo. Invoice/Cr.Memo Line nemají `Currency Code` →
  `AutoFormatExpression = Rec.GetCurrencyCode()`.
- **3.6b** `Sales Line.Validate("No.")` dělá `Init()` → extension pole se
  ztratí při archive restore (`OnAfterTransferFromArchToSalesLine`), Copy
  Document s Recalculate (`OnBeforeInsertToSalesLine`) a RecreateSalesLines
  (`OnBeforeSalesLineInsert`) → sdílený `Reapply` helper. `fieldgroups`
  z tableextension fungují.
- **3.6c** Blob pole na Sales Header: `TransferFields` ho bez `CalcFields` **tiše
  nepřenese** → subscriber na každém přenosu (post, archiv, Quote→Order, Copy
  Document) s `CalcFields` na zdroji. Délku/typ vlastního Text pole drž
  stejnou v celé sadě tabulek (LC0044 = warning = CI fail).
- **3.6d** Kontrola celého dokladu, která má platit i pro účtování z kódu a testy →
  `Sales-Post.OnAfterCheckSalesDoc`, ne `OnBeforeIsApprovedForPosting` (jen UI).
