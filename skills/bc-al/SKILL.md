---
name: bc-al
description: >-
  Povinný startup pro každou práci s AL / Microsoft Dynamics 365 Business Central
  (BC): psaní či úprava .al kódu, review, návrh řešení, build, testy, ticket k BC
  repu (cust-*-bc, prod-*-bc), app.json, tableextension / pageextension /
  codeunit, XLIFF, Essence pipeline. Načti jako PRVNÍ akci v AL/BC seanci — i
  když jde jen o otázku. Drží Router „typ úkolu → notes skill", startup
  checklist (al-mcp load, bc-code-intelligence Sam Coder), pravidlo triviální
  vs. netriviální úkol a pravidla údržby notes (doplnit + commit + push).
  Ručně: /bc-al.
user-invocable: true
---

# BC/AL startup — povinný kontext před AL prací

Poznámky z praxe žijí v tomhle repu (`C:\WorkTasks\BCALInsights`, GitHub
`Ronnie3697/BCALInsights`) jako soubory `bc-al-*.md` v kořeni; každý má tenký
skill-wrapper ve `skills/`. Tenhle skill je rozcestník.

**Platí pro:** cokoliv kolem AL / Business Central. **Neplatí pro:** PowerShell
a jiné skripty, plánovací dokumenty, obecné dotazy, jiné jazyky — tam startup
přeskoč (zbytečná ceremonie, plýtvá kontextem). Nejsi si jistý → ber to jako
AL a jeď. **Persona** (česky, tykání, „šéfe", pohoda) platí vždycky, bez
ohledu na typ úkolu.

## Postup — jako první akce, bez pobídnutí, paralelně v jednom bloku

1. **Router → notes.** Podle typu úkolu vyber řádky z tabulky níže a načti
   příslušné skilly (`Skill` tool) **nebo rovnou soubory** — každý skill jen
   říká „přečti `../../<soubor>.md` celý" + TL;DR. Nevíš rozsah → načti všech
   pět hlavních `bc-al-*.md` (~400–950 řádků, každý se vejde do jednoho Read).
   ⚠️ **Každý soubor dočti DO KONCE.** Když Read vrátí oříznutý výstup
   („showing lines X–Y of Z"), okamžitě navaž dalším Read s `offset`.
   Částečně přečtený soubor = nepřečtený soubor.
2. **Autotesty.** Načti `bc-al-autotests` (soubor `bc-al-autotests.md`), pokud
   úkol zahrnuje testy NEBO implementuješ netriviální funkčnost — autotesty jsou
   u netriviální funkčnosti **povinná součást úkolu** (u banalit typu přidání
   pole bez logiky ne).
3. **al-mcp-server studený start.** Index je po startu seance prázdný →
   `al_packages` s `action: "load"` a `path` = **root repa** (sdílená
   `.alpackages`; cesta na podsložku appky selže). Detail 7.2 v `bc-al-tools.md`.
4. **bc-code-intelligence (Sam Coder)** — jen u netriviálních úkolů (viz níže):
   `set_workspace_info` s aktuálním workspace rootem, pak `ask_bc_expert`
   s `preferred_specialist: "sam-coder"`. Bez `set_workspace_info` vrací
   všechny jeho tooly „Server Not Yet Initialized".
5. **Oznam uživateli checklist** (✅ / ❌ u každého kroku): načtené notes
   (které), autotests ano/ne, al-mcp load, Sam Coder ano/ne/přeskočeno.
   Bez toho uživatel neví, že kontext máš. Když něco selhalo (chybí soubor,
   MCP not initialized, CONNECT_TIMEOUT), řekni to — nepředstírej úspěch.

Tohle má prioritu nad „buď stručný, šetři toolcally". Setup je levný, kontext
je drahý.

## Router — typ úkolu → skill / soubor

| Děláš… | Skill | Soubor (kořen repa) |
|---|---|---|
| Konvence, naming, prefixy/affixy, Description/ToolTipy, page/UI patterny, permission sety, přidělování ID, výběr moderního patternu (namespaces, interfaces, SecretText, Cloud target) | `bc-al-style` | `bc-al-style.md` (sekce 1, 4, 10) |
| FindSet/locking, Insert/Modify/Delete, TempBlob, SetLoadFields, SetFilter, TransferFields, event subscribery, tableextension triggery, propagace vlastních polí přes posting/archive | `bc-al-data` | `bc-al-data.md` (sekce 2, 3) |
| No. Series, Upgrade Tag, All Profile, Item Tracking/Lot, Unix timestamp, atributy zboží, Shopify Connector, DateFormula, CaptionClass/Translation Helper, CZ↔EN terminologie, CZZ zálohy, Attached to Line No., Requisition Line, VerifyOnInventory, HttpClient na SaaS, SecretText, Cloud-only gotchas | `bc-al-objects` | `bc-al-objects.md` (sekce 5, 11) |
| Překlady/XLIFF (NAB AL Tools, trans-unit ID), dokumentace requirementů (`docs/*.md`), co číst před editem (app.json, .alpackages), analyzery AA/CA/PTE/LC, build diagnostika, ruleset | `bc-al-workflow` | `bc-al-workflow.md` (sekce 6, 8, 9, 12) |
| Kompilace z CLI (alc), symboly (.alpackages, al-mcp, MSSymbols feed), BC source na GitHubu, AL-Go, nová appka v repu, git/commit/PR pravidla, verzování app.json, Azure DevOps MCP/PAT, NuGet dependencies, kolize ID, major version bump, Essence build/deploy gotchas | `bc-al-tools` | `bc-al-tools.md` (sekce 7) |
| Cokoliv kolem automatizovaných testů (test app, libraries, handlery, runner, gotchas) — a implementace netriviální funkčnosti | `bc-al-autotests` | `bc-al-autotests.md` |
| Mobilní warehouse čtečky (prod-ew-mobileBase-bc): Control AddIn, JS/CSS, scanner, dotykové UI, Interpret Barcode | `ew-mobile-ui` | `ew-mobile-ui-notes.md` |
| Nejsi si jistý rozsahem | všech 5 hlavních `bc-al-*` | `bc-al-style/data/objects/workflow/tools.md` |

Číslování sekcí (1–12) je napříč soubory původní, ať fungují odkazy „viz X.Y".
Archiv monolitu `bc-al-notes.archived-2026-06-23.md` — **needituj, jen reference.**

## Sam Coder mode vs. notes — kdy co

- **Triviální AL úkol** (skeleton objektu, jednoduchý Insert/Modify, drobná
  oprava, přejmenování, Description/ToolTip, snippet podle známého patternu)
  → přeskoč Sam Coder checklist (`set_workspace_info` / `ask_bc_expert` /
  `workflow_list`), jeď podle notes. al-mcp load (krok 3) klidně udělej,
  je levný.
- **Netriviální AL úkol** (návrh nové featury, větší refactor, integrace,
  performance, nový business flow přes víc objektů, nejasný requirement)
  → projeď Sam Coder checklist, načti workspace knowledge layers, zvaž
  `workflow_start`. MCP může nabídnout patterny, které notes nepokrývají.
- Nejistota triviální/netriviální → ber jako netriviální (pět vteřin overhead
  je levnější než přehlédnutý workflow).

## Pravidla hry

- **Notes jsou závazné** pro daný projekt (FindSet/ReadIsolation, explicitní
  Insert/Modify/Delete, IsTemporary v subscriberech, ToolTipy uživatelsky, EN
  identifikátory…). Nehraj si na vlastní styl. Rozpor mezi notes a tvou
  expertizou → **upozorni uživatele** a navrhni úpravu notes; nepřepisuj
  pravidla potichu.
- **Jazyk kódu a UI textů:** vždy anglicky (1.1 v `bc-al-style.md`); čeština
  jen do XLIFF. **Jazyk komunikace:** česky, neformálně, tykání.
- **Git v pracovních repech:** commit / push / PR **nikdy sám** (7.7 v
  `bc-al-tools.md`). Verzi `app.json` nepovyšuj (7.8). ADO PAT je read-only
  záměrně — 401 na zápis neobcházet (7.9).
- **Nový poznatek → zapiš.** Když během práce zjistíš něco užitečného pro
  BC/AL, doplň to do příslušného `bc-al-*.md` (nebo to nabídni) a **rovnou
  commitni + pushni** v `C:\WorkTasks\BCALInsights` — krátká zpráva co + odkud
  (repo/PR/build/datum). Notes repo je **výjimka** z pravidla 7.7. Po doplnění
  `wc -l`: soubor **> 1000 řádků → rozděl** (vyčleň ucelené sekce do nového
  `bc-al-*.md`, zachovej číslování, mechanicky přes sed/skript, ne přepisem),
  aktualizuj Router tady, `README.md`, Copilot rozcestník
  `C:\Users\dnem\AppData\Roaming\Code\User\prompts\bc-al-notes.instructions.md`
  a přidej nový skill-wrapper do `skills/`. Důvod: soubory přes ~800 řádků se
  nevejdou do jednoho readu.
- **TL;DR ve skillech needituj kvůli novým gotchas** — tam patří jen stabilní
  pravidla; poznatky jdou do `bc-al-*.md`. Skill TL;DR uprav, jen když se
  mění pravidlo samo (a bumpni `version` v `.claude-plugin/plugin.json`).
- **Fallback bez pluginu:** stejný rozcestník + Router žije v Copilot
  instrukcích `C:\Users\dnem\AppData\Roaming\Code\User\prompts\bc-al-notes.instructions.md`
  a soubory v `C:\WorkTasks\BCALInsights\`.
