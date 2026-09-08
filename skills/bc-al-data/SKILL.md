---
name: bc-al-data
description: >-
  BC/AL databázové operace a event subscribery z praxe (Business Central):
  FindSet, ReadIsolation::UpdLock vs LockTable,
  Insert/Modify/Delete(true|false) (LC0040), Temp Blob, SetLoadFields,
  SetFilter wildcard + %1 (LC0050), separátory, TransferFields + PK v copy
  smyčce, Mark/MarkedOnly vs Record.Copy, field-by-field kopie,
  tableextension triggery vs subscribery, modify() ve fields, klíč jen
  vlastní pole (AL0423), var guard vs CurrFieldNo, IsTemporary, init
  detection OnAfterValidateEvent, SkipOnMissingLicense/Permission, propagace
  Sales Line → ILE / Whse. Shipment, vlastní pole Sales/Purchase Header/Line
  vč. archive/posted (checklist), total při částečném účtování
  (OnAfterInitFromSalesLine, undo), AutoFormatExpression GetCurrencyCode,
  Blob = CalcFields + subscriber, délky Text polí (LC0044), Validate("No.")
  Init() past (archive, Copy Document, Recreate), EventSubscriber identifier
  syntax (LC0028), deprecated eventy AL0432. Načti při práci s recordy,
  posting, subscribery, tableextension, propagaci polí.
user-invocable: true
---

# BC/AL — Database & Event subscribery (sekce 2, 3)

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\bc-al-data.md`
(v repu `../../bc-al-data.md` relativně k tomuto skillu). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů, příklady a odůvodnění
jsou v souboru.

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\bc-al-data.md` celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: konvence a naming → `bc-al-style`; No. Series, Item
   Tracking, Requisition Line → `bc-al-objects`; ověření signatur eventů
   (al-mcp, extrakce z .app) → `bc-al-tools` (7.2, 7.6).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **2.1** `FindSet()` bez argumentu pro čtení. Zápis v cyklu:
  `Rec.ReadIsolation := IsolationLevel::UpdLock` + `FindSet()` místo
  `LockTable()` / `FindSet(true)` (per-instance scope). V reportu do
  `OnPreDataItem`.
- **2.2** `Insert` / `Modify` / `Delete` / `DeleteAll` / `ModifyAll` **vždy
  s explicitním argumentem** (LC0040). Temp buffery `false`; `true` jen na
  reálné tabulky, kde chceš business logiku. V tableextension triggerech
  Insert/Modify nevolat vůbec (výjimka `OnAfterModify`, viz 3.1).
- **2.3** `Codeunit "Temp Blob"` + streamy, ne `Record TempBlob`.
- **2.4** `SetLoadFields(...)` před read-only `FindSet`/`Get` na širokých
  tabulkách; **ne** v cyklu s `Modify`.
- **2.5** Wildcard + placeholder v `SetFilter` (`'*%1*'`) = LC0050 → string
  poskládej `StrSubstNo` **předem** (hodnotu s filter operátory escapuj sám,
  `StrSubstNo` to nedělá). Separátor multi-value pole `~`
  (ne `|`, `&`, `,`, `..`).
- **2.6** `Init()` + `TransferFields(Src, false)` → nastav **VŠECHNA PK pole**
  explicitně v každé iteraci (TransferFields PK nepřenáší, Init PK nečistí).
- **2.6b** `Mark`/`MarkedOnly` + `Other.Copy(Rec)` → s marks na kopii nepočítej;
  dílčí filtry dělej na téže instanci a výsledek si odnes přiřazením.
- **2.7** Nové flag pole → projít i ruční field-by-field kopie (šablony,
  buffery, mirror tabulky).
- **3.1** V tableextension preferuj triggery: `OnBeforeInsert/Modify` a
  `OnAfterInsert` bez Modify; **`OnAfterModify` → `Rec.Modify(false)`**, jinak
  se změna neuloží. Subscriber (`OnAfter*Event`) pro cross-cutting logiku —
  tam `Modify` musíš.
- **3.2** Každý subscriber, který zapisuje: `if Rec.IsTemporary() then exit;`
  na začátku.
- **3.3** `OnAfterValidateEvent` init detection: `IsNullGuid(Rec.SystemId)` /
  `Rec."No." = ''` / `IsTemporary()` → exit.
- **3.4** `[EventSubscriber(..., '', false, false)]` pro business logiku
  (ať to spadne viditelně); `true, true` jen kosmetika.
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
- **3.7** `[EventSubscriber]` event a element jako **identifikátory**
  (`OnAfterValidateEvent`, `"Operation No."`), ne string literály (LC0028);
  prázdný element zůstává `''`.
- **3.8** AL0432 (deprecated) → nový objekt a signaturu **ověř v symbolech**
  (al-mcp), přejmenuj subscriber, ukliď osiřelé `var`.
- **3.9** Tableextension: `modify("Pole")` patří **dovnitř `fields { }`** (jinak
  kaskáda AL0198/AL0104); klíč smí mít **jen vlastní pole** (AL0423) →
  `SetRange` na base pole + `SetCurrentKey(vlastní)`; guard proti smyčce
  validací = globální `var` flag (per instance, přežije vnořené Validate),
  **ne** `CurrFieldNo` (z kódu jiných appek je 0).
