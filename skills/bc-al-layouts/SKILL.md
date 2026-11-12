---
name: bc-al-layouts
description: >-
  BC/AL layouty reportů (Business Central, sekce 12.1f–12.1i, 12.5): Word layout (.docx) přes MCP bc-word-layout a
  skilly al-word-layout* (inspect → edit → validate → preview, co server neumí), repeater w15:dataBinding vs
  w:dataBinding (Word SaveAs2), RDLC tablix sloupce skriptem (TablixCell = sloupec, ColSpan, Hidden, BOM + CRLF),
  RDLC layout reportextension (alc při kompilaci přegeneruje `<DataSets>` ze symbolů, CI s jinou verzí vendora →
  „refers to the field", dvě verze appky v .dependencies, sonda sloupce AL0155), Word layout štítků psaný skriptem
  (namespace vazeb = název reportu, WordMergeDataItem bez repeateru, aliasy #Nav, zip s lomítky, jeden štítek na
  stránku hRule exact), obrázek z Blob a Essence Document Attachments (SharePoint Drive Item ID → „image stream does
  not contain valid image"), barcode fonty IDAutomation (C128 / UPCEAN, velikost písma = šířka kódu), GS1-128 / FNC1
  vlastním encoderem, kontrolní číslice EAN. Načti u Word / RDLC layoutů, reportextension layoutu a štítků s
  čárovými kódy.
user-invocable: true
---

# BC/AL — Layouty reportů: Word, RDLC, štítky (sekce 12.1f–12.1i, 12.5)

**Zdroj pravdy:** `bc-al-layouts.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, skripty a příklady jsou v souboru.
Vyčleněno z `bc-al-workflow.md` 2026-11-12, číslování 12.x je původní.

## Co udělat

1. **Přečti `bc-al-layouts.md` z adresáře tohoto skillu celý.** Je krátký (~200 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: build, analyzery a ruleset (12.1–12.1e, 12.2–12.4) → `bc-al-workflow`; `alc` přepisuje
   `.docx` / `.rdl` layouty v `src/` při kompilaci z CLI → `bc-al-tools` (7.1); MCP servery a jejich instalace
   (`bc-word-layout` krok 1b) → `mcp-setup.md` v kořeni notes repa; CI build, NuGet závislosti → `bc-al-build`.

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **12.1i** Word layout (.docx) nejdřív přes MCP `bc-word-layout` a skill `al-word-layout`
  (inspect → edit → validate → preview); ruční OOXML (12.1f, 12.5) jen pro to, co tooly
  neumí (hide-if-empty, repeater v hlavičce, štítky s barcode fontem). Preview ≠ tisk v BC.
- **12.1f** Repeater (`w15:repeatingSection`) potřebuje **`w15:dataBinding`**, ne `w:dataBinding`;
  regresní kontrola ověřuje namespace vazby, ne jen existenci uzlu.
- **12.1h** `alc` při kompilaci přepíše `<DataSets>` RDLC layoutu reportextension podle symbolů v package
  cache. CI s jinou verzí vendora (dvě verze téže appky v `.dependencies`) vyrobí layout, který padá na
  „refers to the field" → layout nesmí ukazovat na sloupec, který v některé verzi vendora chybí.
- **12.5** Word layout psaný skriptem: namespace vazeb = název reportu, každá skupina
  ne-alfanumerických znaků → jedno `_`, **ID a token ber z `.al` skriptem** (přečíslovaný
  report = prázdný tisk bez chyby; ověř, že `alc` nechal tvůj `customXml/item1.xml`).
  Struktura jako MS layouty: hlavní dataitem bez repeateru (`WordMergeDataItem`), repeater
  jen pro vnořený, aliasy `#Nav: /<dataitem>/<sloupec>`. Zip položky s lomítky, jeden
  štítek na stránku přes řádek tabulky s `hRule="exact"`. GS1-128 přes System App nejde
  (bez FNC1) → vlastní Code 128 encoder pro font `IDAutomationC128*`; kontrolní číslici
  EAN font dopočítá → validuj GS1 mod 10 před tiskem.
