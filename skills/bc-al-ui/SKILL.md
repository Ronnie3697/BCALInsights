---
name: bc-al-ui
description: >-
  BC/AL UI patterny stránek z praxe (Business Central, AL; sekce 4,
  vyčleněno z bc-al-style): RunModal vs Run a výběr záznamu na RoleCenter
  CardPart (SingleInstance + CurrPage.Close), OnDrillDown vs OnLookup,
  ConfirmManagement default Yes pro běžné a No pro destruktivní akce,
  factbox SourceTableTemporary a Rec.Reset maže SubPageLink (filter group
  4), CaptionClass captiony cache per session, přeměna pole na expression
  control bez přejmenování controlu (AL0270, XLIFF ID), modify() na kontrolu
  cizí pageextension (přímá dependency), smyčka aktualizace mezi aktivačními
  událostmi (žádný zápis ani CurrPage.Update v OnAfterGetRecord /
  OnAfterGetCurrRecord, idempotentní přepočty), Visible = Rec.pole v
  pageextension padá za běhu → page proměnná v OnOpenPage, MultiLine pevné 3
  řádky / ExtendedDatatype RichContent v root group (HTML → Blob) / control
  add-in. Načti při psaní nebo review page, pageextension, factboxů,
  RoleCenter partů, akcí s potvrzením, dynamických captionů, viditelnosti
  polí, dlouhých textových polí.
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
   (1, 10); propagace Blob/Text polí do posted dokladů → `bc-al-data` (3.6c);
   Confirm + `CurrFieldNo` chování Sales Line a testy → `bc-al-objects` (5.x4) /
   `bc-al-autotests`; control add-in jako celá page na čtečkách → `ew-mobile-ui`.

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
  (hodnota HTML → Blob, 3.6c v `bc-al-data`) nebo vlastní control add-in
  (u zákaznických rep počítej s odmítnutím jako obcházení standardu).
