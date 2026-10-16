---
name: bc-al-ui
description: >-
  BC/AL UI patterny stránek (sekce 4): RunModal vs Run, výběr na RoleCenter CardPart (SingleInstance
  + CurrPage.Close), OnDrillDown vs OnLookup, ConfirmManagement default, factbox Rec.Reset maže
  SubPageLink, CaptionClass cache, expression control bez přejmenování (AL0270, XLIFF ID), modify()
  cizí pageextension, smyčka aktualizace v OnAfterGet*Record, Visible = Rec.pole v pageextension
  padá, MultiLine 3 řádky / RichContent / control add-in, page procedura se jménem metody Rec
  (AL0604), List v LookupMode jen pro čtení; filtr partu z OnOpenPage zmizí; DelayedInsert = prázdné
  SystemId; CurrPage.Update(false) v OnValidate zahodí hodnotu; ListPart přes RunModal pod TestPage;
  stránka bez SourceTable (protected var / veřejný getter + výraz v SourceExpr, stínění parametrů);
  dlaždice na phone klientu (Brick / DropDown / prvních 5 controlů, addlast Brick). Načti u page,
  pageextension, factboxů, partů, výběrů, captionů a viditelnosti.
user-invocable: true
---

# BC/AL — UI patterny stránek (sekce 4)

**Zdroj pravdy:** `bc-al-ui.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, příklady kódu a odůvodnění jsou v souboru.
Vyčleněno z `bc-al-style.md` 2026-09-08, číslování 4.x je původní.

## Co udělat

1. **Přečti `bc-al-ui.md` z adresáře tohoto skillu celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: konvence, naming, ToolTipy, formát page fieldů → `bc-al-style`
   (1, 10); propagace Blob/Text polí do posted dokladů → `bc-al-posting` (3.6c);
   Confirm + `CurrFieldNo` chování Sales Line a testy → `bc-al-objects` (5.x4) /
   `bc-al-autotests`.

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **4.1–4.3** RoleCenter CardPart: `RunModal` s návratovou hodnotou / `GetRecord`
  nefunguje → výběr přes SingleInstance codeunit + `CurrPage.Close()`.
- **4.4** `ConfirmManagement.GetResponseOrDefault(Qst, true)` pro běžné akce,
  `false` pro destruktivní / nevratné.
- **4.5** Factbox `SourceTableTemporary`: `Rec.Reset()` smaže SubPageLink
  (filter group 4) → ulož a obnov view kolem reloadu.
- **4.6** CaptionClass captiony se cachují per session → nejdřív vyluč cache
  (Ctrl+F5) a per-company setup, až pak hledej bug v kódu.
- **4.6b** Přeměna pole na expression control: **název controlu nech**, měň jen
  `SourceExpr` (kotva `addafter`/`modify` závislých appek → AL0270, XLIFF ID,
  personalizace); nové controly pojmenuj podle pole tabulky. Pak zkompiluj
  závislé appky proti novému buildu.
- **4.7** `modify()` na kontrolu cizí pageextension jde s přímou dependency
  (bez ní AL0270).
- **4.8** **Žádný zápis ani `CurrPage.Update()` v `OnAfterGetRecord` /
  `OnAfterGetCurrRecord`** (smyčka aktualizace) → přepočty do akcí /
  `OnOpenPage`, idempotentně (`Modify` jen když se hodnota liší).
- **4.9** `Visible = not Rec."Pole"` v pageextension **kompiluje, ale za běhu
  padá** („identifier … could not be found") → page `Boolean` proměnná
  nastavená už v `OnOpenPage` (+ `OnAfterGetRecord`, `OnValidate` řídícího
  pole + `CurrPage.Update()`).
- **4.10** `MultiLine` = pevné ~3 řádky, žádná property výšku nezvětší. Celý
  dlouhý text = `ExtendedDatatype = RichContent` na Text proměnné v root group
  (hodnota HTML → Blob, 3.6c v `bc-al-posting`) nebo vlastní control add-in
  (u zákaznických rep počítej s odmítnutím jako obcházení standardu).
