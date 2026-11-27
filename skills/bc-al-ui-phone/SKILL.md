---
name: bc-al-ui-phone
description: >-
  BC/AL UI na phone klientu a čtečkách (4.22, 4.23, 4.26–4.29, 4.33): dlaždice listů a ListPartů (Brick / DropDown /
  prvních 5 controlů, výrazové pole, addlast(Brick), sloty, AL0611 akce v cuegroup), sken ze zakryté stránky se odloží
  a přehraje (aria-hidden / inert, add-in ve sbalitelném FastTabu), CaptionClass '3,' a Visible pole vs. skupiny,
  klepnutí = náhled, CardPageId jen zobrazení, pole na proměnné stránky, chyba OnValidate jen křížek, InstructionalText,
  Rec prázdného listu z filtrů, \ v Message, mezera po add-inu, seznam → řádky → detail (ListPart s CardPageId,
  SubPageView), přepínací karta, čtečka místo akce cizí stránky (AC Parcels API ParcelMgt_aci), barvy kostek (TileTeal,
  AL0482), výběr jedním klepnutím, Zpět na úvodní stránku. Načti u stránek pro telefon, čtečky a kiosky.
user-invocable: true
---

# BC/AL — UI na phone klientu a čtečkách (sekce 4.22, 4.23, 4.26–4.29, 4.33)

**Zdroj pravdy:** `bc-al-ui-phone.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, ověření a příklady jsou v souboru.
Vyčleněno z `bc-al-ui.md` 2026-11-27, číslování 4.x je původní (ostatní sekce 4 zůstávají ve skillu `bc-al-ui`).

## Co udělat

1. **Přečti `bc-al-ui-phone.md` z adresáře tohoto skillu celý.** Má ~270 řádků, vejde se do jednoho Read. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: ostatní chování stránek (RunModal, factbox, `Visible` přes proměnnou 4.9, expression control 4.6b,
   `CurrPage.Update(false)` 4.17, `SaveRecord` + `RunModal` 4.25, pole za cizí control na stránce bez `SourceTable` 4.21)
   → `bc-al-ui`; skladové doklady a aktivity z kódu, MJ čtečky → `bc-al-warehouse`; symbol cizí appky z dev endpointu
   (7.26) → `bc-al-deploy`; Essence Warehouse Mobile, Control add-in a JS → osobní skill `ew-mobile-ui` (mimo repo).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **4.22** Dlaždice = fieldgroup `Brick` → `DropDown` → prvních 5 controlů repeateru. Výrazové pole do fieldgroup nedáš;
  `addlast(Brick)` na tabulce bez Bricku vyhodí z dlaždic všechno ostatní. Odvozené údaje čteček dávej do hlaviček, nebo
  do textu, který dlaždice už ukazuje.
- **4.23** Událost control add-inu ze zakryté stránky (stack `Page.Run`) BC odloží a přehraje, až je stránka nahoře →
  v JS před `InvokeExtensibilityMethod` test `window.frameElement.closest('[aria-hidden="true"], [inert]')`. Add-in, který
  musí běžet pořád, nedávej do sbalitelného FastTabu.
- **4.26** `Visible` na poli platí jen z otevření; pole ukazované podle skenu dej do skupiny s `Visible`. Popisek podle
  hodnoty přes `CaptionClass = '3,' + výraz`.
- **4.27** Klepnutí na dlaždici bez `CardPageId` = náhled; karta z `CardPageId` je v režimu zobrazení (pole na proměnných
  stránky zůstanou editovatelná); `Error` v `OnValidate` = jen křížek u pole.
- **4.29** Seznam → řádky → detail: karta hlavičky + ListPart s vlastním `CardPageId`; detail dědí `SubPageView` partu →
  z `Rec` ber jen hodnoty, ne filtry. Needitovatelnou kartu phone klient neotevře.
- **4.33** Akci cizí stránky z AL nespustíš → poskládej ji z veřejného API a výsledek porovnej se záznamem ze standardní
  stránky. Barvy kostek mimo základní + `TileTeal` / `TileLightGreen` = AL0482.
