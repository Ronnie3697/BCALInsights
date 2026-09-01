---
name: bc-al-data
description: >-
  BC/AL databázové operace a event subscribery z praxe (Business Central, AL):
  FindSet vs ReadIsolation::UpdLock vs LockTable, explicitní
  Insert/Modify/Delete(true|false) a LC0040, Temp Blob codeunit,
  SetLoadFields, SetFilter s wildcard + %1 (LC0050) a bezpečné separátory,
  TransferFields + PK pole v copy smyčce, nová pole vs field-by-field kopie,
  tableextension triggery vs subscribery (kdy volat Modify), IsTemporary
  check, init detection v OnAfterValidateEvent, SkipOnMissingLicense /
  SkipOnMissingPermission, propagace vlastního pole Sales Line → Item Ledger
  Entry / Warehouse Shipment, vlastní pole na Sales/Purchase Header/Line
  včetně archive a posted tabulek (checklist), Sales Line Validate("No.")
  Init() past (archive restore, Copy Document, RecreateSalesLines),
  EventSubscriber identifier syntax (LC0028), deprecated eventy AL0432. Načti
  při práci s recordy, posting, event subscribery, tableextension triggery,
  propagaci vlastních polí.
user-invocable: false
---

# BC/AL — Database & Event subscribery (sekce 2, 3)

**Zdroj pravdy:** `../../bc-al-data.md` (lokální klon
`C:\WorkTasks\BCALInsights\bc-al-data.md`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů, příklady a odůvodnění
jsou v souboru.

## Co udělat

1. **Přečti `../../bc-al-data.md` celý.** Vejde se do jednoho Read; když se
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
  subscriber `OnAfter…Insert`. Projdi checklist v souboru.
- **3.6b** `Sales Line.Validate("No.")` dělá `Init()` → extension pole se
  ztratí při archive restore (`OnAfterTransferFromArchToSalesLine`), Copy
  Document s Recalculate (`OnBeforeInsertToSalesLine`) a RecreateSalesLines
  (`OnBeforeSalesLineInsert`) → sdílený `Reapply` helper. `fieldgroups`
  z tableextension fungují.
- **3.7** `[EventSubscriber]` event a element jako **identifikátory**
  (`OnAfterValidateEvent`, `"Operation No."`), ne string literály (LC0028);
  prázdný element zůstává `''`.
- **3.8** AL0432 (deprecated) → nový objekt a signaturu **ověř v symbolech**
  (al-mcp), přejmenuj subscriber, ukliď osiřelé `var`.
