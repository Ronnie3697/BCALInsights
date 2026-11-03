---
name: bc-al-advance-cz
description: >-
  BC/AL CZZ zálohy (Advance Payments Localization for Czech; 5.z3, 5.z5, 5.z7): vazba záloha ↔ doklad
  (Advance Letter Application CZZ, Order No. jen zrcadlo), odpojení přes Advance Letter Appl. Edit a scoped guard
  (EventSubscriberInstance = Manual + BindSubscription), generovaný řádek zálohy z reportu Create Sales Adv. Letter
  CZZ (OnCreateAdvanceLetterLineOnBeforeInsert, Description Text[100]), platba zálohy a účto skupina zákazníka /
  dodavatele (Advance Letter No. CZZ OnValidate skupinu nemění, účet záloh z Advance Letter G/L Account přes Use
  Advance G/L Account CZZ, PostAdvancePayment = vyrovnání + položka zálohy, event
  OnPostAdvancePaymentOnBeforePostAdvancePayment, odpojení vrací platbu balance řádkem →
  OnPostAdvancePaymentUnlinkingOnBeforePostPaymentApplication + Applies-to ID, Allow Multiple Posting Groups, přímé
  přiřazení Posting Group). Načti u Adv. Letter Header CZZ, šablon záloh, plateb záloh z deníku / výpisu,
  Propojit / Odpojit zálohovou fakturu a účto skupin na položkách záloh.
user-invocable: true
---

# BC/AL — CZZ zálohy (sekce 5.z3, 5.z5, 5.z7)

**Zdroj pravdy:** `bc-al-advance-cz.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, signatury eventů a příklady jsou v souboru.
Vyčleněno z `bc-al-objects.md` 2026-11-03, číslování 5.z* je původní.

## Co udělat

1. **Přečti `bc-al-advance-cz.md` z adresáře tohoto skillu celý.** Je krátký (~90 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: testy CZZ zálohy s platbou (release, To Pay) → `bc-al-autotests-domains`; ostatní objekty (No. Series,
   Job Queue, duplicita IČ/DIČ) → `bc-al-objects`; subscribery, `xRec` ve `OnValidate` → `bc-al-data`; propagace polí
   dokladů → `bc-al-posting`; zdroj CZZ z `.app` (`unzip`) → `bc-al-tools` (7.6).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **5.z3** Vazbu zálohy na doklad drží `Advance Letter Application CZZ` (31007); `Order No.` na hlavičce je jen zrcadlo, které
  `OnDelete` 31007 vymaže a standard neobnoví. Guard jen pro interaktivní dialog = codeunit s `EventSubscriberInstance = Manual`
  + `BindSubscription` kolem standardní akce; v guardu `IsTemporary()` exit.
- **5.z5** Generovaný řádek zálohy uprav v `OnCreateAdvanceLetterLineOnBeforeInsert` (ne `OnInsert` tabulky); `Description`
  je Text[100]; report končí Confirm → `[ConfirmHandler]`.
- **5.z7** Výběr zálohy v deníku účto skupinu **nemění**, účet záloh jde ze šablony (*Advance Letter G/L Account*,
  `Use Advance G/L Account CZZ`). Skupinu ze šablony na položku zálohy dosaď v `OnPostAdvancePaymentOnBeforePostAdvancePayment`
  (všechny cesty: deník, výpis, pokladna, Propojit), při odpojení vrať skupinu původní platby v
  `OnPostAdvancePaymentUnlinkingOnBeforePostPaymentApplication` (`Applies-to ID` → položka platby). Přiřazuj přímo, ne
  `Validate` (*Allow Multiple Posting Groups*).
