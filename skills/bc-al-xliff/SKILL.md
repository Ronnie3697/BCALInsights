---
name: bc-al-xliff
description: >-
  BC/AL lokalizace a překlady XLIFF (Business Central, sekce 6.1–6.4): NAB AL Tools (Refresh XLIFF,
  [NAB: NOT TRANSLATED] / [NAB: SUGGESTION] prefixy, jeden target, note Xliff Generator nemazat, hromadný
  překlad skriptem source → překlad, BC CZ konvence Zboží / Přihrádka / Šarže), trans-unit ID hash (FNV-1a
  32-bit přes UTF-16LE jména, BigInt v node, rename / přesun labelu do jiné procedury mění ID → osiřelý unit),
  doplnění unitů z .g.xlf do .cs-CZ.xlf skriptem (konce řádků CRLF vs LF), víc extensionů na stejný objekt
  (disambiguované ID, LC0091 false positive), label s %n = update source i target v každém locale,
  duplicitní trans-unity po merge (AL0479, failOn warning), výpis diakritiky z xlf přes Bash (cp1250 → zapiš
  do UTF-8 souboru), .cs-CZ.xlf změněný pod rukama NAB Refreshem. Načti u překladů, .xlf souborů,
  Translations, NAB AL Tools, trans-unit ID a merge .xlf.
user-invocable: true
---

# BC/AL — Lokalizace a překlady XLIFF (sekce 6)

**Zdroj pravdy:** `bc-al-xliff.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, hash algoritmus, skripty a příklady jsou v souboru.
Vyčleněno z `bc-al-workflow.md` 2026-10-22, číslování 6.x je původní.

## Co udělat

1. **Přečti `bc-al-xliff.md` z adresáře tohoto skillu celý.** Je krátký (~210 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: kompilace z CLI (alc, `.g.xlf` z kopie projektu ve scratchpadu) → `bc-al-tools` (7.1);
   terminologie z XLIFF do uživatelské příručky → `bc-al-workflow` (8.1); Essence ruleset a `failOn warning` →
   `bc-al-workflow` (12.4); CZ↔EN terminologie → `bc-al-objects` (5.z4); falešné konflikty `.xlf` po squash merge →
   `bc-al-build`.

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **6.1** Po `Refresh XLIFF`: **jeden `<target>`** per trans-unit, smazat celý
  `[NAB: …]` prefix, note `Xliff Generator` **nikdy nemazat**. Hromadně →
  Python skript source → překlad, pak **zkompiluj**. Drž BC CZ konvence
  (Zboží, Přihrádka, Šarže, Sériové číslo).
- **6.2** Trans-unit ID = FNV-1a 32-bit přes UTF-16LE jména + 2147483647;
  rename pole/objektu ID mění, změna textu ne. **2.+ extension na stejný
  target objekt** má disambiguované ID → ber z `Translations/*.g.xlf`,
  nepřepočítávej (LC0091 tam dělá false positive; ID v `.cs-CZ.xlf` nesahat).
- **6.3** Změna zdrojového textu labelu (typicky nové `%n`) → uprav
  `<source>` **i** `<target>` v každém locale XLF, jinak CZ klient ukazuje
  starou hlášku.
- **6.4** Po každém merge, který sáhl na `.xlf`: `grep -o 'trans-unit
  id="[^"]*"' <soubor> | sort | uniq -d` + kompilace; AL0479 je warning →
  Essence CI (`failOn warning`) spadne.
