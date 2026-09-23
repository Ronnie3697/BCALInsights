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

Poznámky z praxe žijí v tomhle repu (GitHub `essencebs/BCALInsights`, firemní;
klon může být kdekoli) jako soubory `bc-al-*.md`, každý **vedle svého
skill-wrapperu ve `skills/<název>/`** — podpůrný soubor skillu podle Agent Skills
spec, proto se na něj odkazuje jen jménem, relativně k adresáři skillu (žádné
absolutní cesty, žádné `../..` — přes junction jen na `skills/` by `..` nesedělo).
Kořen repa (README, `mcp-setup.md`, `check-skills.py`) najdeš přes
`git -C <adresář skillu> rev-parse --show-toplevel` (funguje i přes junction).
Tenhle skill je rozcestník — **jediné místo, kde žije Router.** Tentýž adresář `skills/` čtou Claude Code (plugin `bcal-insights`),
Copilot a Codex (junction `~/.agents/skills`) i Antigravity (junction
`~/.gemini/config/skills`); always-on soubory těch nástrojů (CLAUDE.md,
`bc-al-notes.instructions.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`) na
tenhle skill jen odkazují.

**Platí pro:** cokoliv kolem AL / Business Central. **Neplatí pro:** PowerShell
a jiné skripty, plánovací dokumenty, obecné dotazy, jiné jazyky — tam startup
přeskoč (zbytečná ceremonie, plýtvá kontextem). Nejsi si jistý → ber to jako
AL a jeď. Jazyk a tón komunikace se řídí always-on souborem uživatele (osobní
preference, ne součást notes).

## Postup — jako první akce, bez pobídnutí, paralelně v jednom bloku

0. **Merge masteru do aktuální větve** (jen pracovní repa `cust-*` / `prod-*`,
   ne notes repo): `git fetch origin` a `git merge origin/master` do větve, na
   které stojíš (na masteru `git pull --ff-only`). Konflikty **vyřeš sám** a
   oznam, které soubory a jak; merge commit je tady v pořádku. Když merge
   odmítne kvůli necommitnutým změnám v dotčených souborech, nestashuj —
   řekni to uživateli. Stejný krok opakuj **před každým `commitni` / `pushni`**
   (detail 7.7b v `bc-al-tools.md`). Uživatel na to nechce myslet.
1. **Router → notes.** Podle typu úkolu vyber řádky z tabulky níže a načti
   příslušné skilly (Claude Code: `Skill` tool; Copilot `/název`, Codex
   `$název`, Antigravity zmínkou jménem) **nebo rovnou soubory** — každý skill
   jen říká „přečti `<soubor>.md` z adresáře skillu celý" + TL;DR. Nevíš rozsah → načti všech
   osm hlavních `bc-al-*.md` (~250–750 řádků / ≤ 45 KB, každý se vejde do
   jednoho Read; kdyby se výstup přece ořízl, dočti přes `offset`).
   ⚠️ **Každý soubor dočti DO KONCE.** Když Read vrátí oříznutý výstup
   („showing lines X–Y of Z"), okamžitě navaž dalším Read s `offset`.
   Částečně přečtený soubor = nepřečtený soubor.
2. **Autotesty.** Načti `bc-al-autotests` (soubor `bc-al-autotests.md`), pokud
   úkol zahrnuje testy NEBO implementuješ netriviální funkčnost — autotesty jsou
   u netriviální funkčnosti **povinná součást úkolu** (u banalit typu přidání
   pole bez logiky ne).
3. **al-mcp-server studený start** (pokud je MCP v daném nástroji
   nakonfigurovaný; když chybí — v `claude mcp list` není — jednorázová
   instalace všech MCP serverů je v `mcp-setup.md` v kořeni notes repa —
   `git -C <adresář skillu> rev-parse --show-toplevel` — jinak ho nečti). Index je po startu seance prázdný →
   `al_packages` s `action: "load"` a `path` = **root repa** (sdílená
   `.alpackages`; cesta na podsložku appky selže). Detail 7.2 v `bc-al-tools.md`.
4. **bc-code-intelligence (Sam Coder)** — jen u netriviálních úkolů (viz níže)
   a jen tam, kde je ten MCP nakonfigurovaný (jinak krok přeskoč a řekni to):
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

| Děláš… | Skill | Soubor (v adresáři skillu) |
|---|---|---|
| Konvence, naming, prefixy/affixy, Description/ToolTipy, formát page fieldů, permission sety, přidělování ID, přetěžování procedur, locale pasti (Format/Evaluate, Excel Buffer), výběr moderního patternu (namespaces, interfaces, SecretText, Cloud target) | `bc-al-style` | `bc-al-style.md` (sekce 1, 10) |
| Chování page/pageextension: RunModal a výběr na RoleCenter, ConfirmManagement default, factbox SubPageLink, CaptionClass cache, názvy controlů / expression pole, modify cizí pageextension, smyčka aktualizace v OnAfterGet*Record, Visible přes page proměnnou, MultiLine/RichContent/control add-in, page procedura se jménem metody `Rec` (AL0604), výběrový dialog v LookupMode (jen pro čtení) | `bc-al-ui` | `bc-al-ui.md` (sekce 4) |
| FindSet/locking, Insert/Modify/Delete, TempBlob, SetLoadFields, SetFilter, TransferFields, Mark/Copy, event subscribery, tableextension triggery / klíče / modify(), propagace vlastních polí přes posting/archive (částečné účtování, Blob + CalcFields, AutoFormatExpression) | `bc-al-data` | `bc-al-data.md` (sekce 2, 3) |
| No. Series, Upgrade Tag, All Profile, Item Tracking/Lot (i na Sales Quote), Unix timestamp, atributy zboží, DateFormula, CaptionClass/Translation Helper, CZ↔EN terminologie, CZZ zálohy, Attached to Line No. / parent↔child řádky, Requisition Line, VerifyOnInventory, Auto Format / částky v textu, Item Charge Assignment z kódu, Job Queue z účtování / recurring entry | `bc-al-objects` | `bc-al-objects.md` (sekce 5) |
| Shopify Connector (varianty, sync vs Add Item, eventy, userErrors, Internal komunikační vrstva → vlastní HttpClient + custom app), HttpClient na SaaS, Isolated Storage, SecretText, OAuth/secrets na Cloud targetu, Cloud-only gotchas, notifikace do Power Automate / Business Events | `bc-al-integrations` | `bc-al-integrations.md` (5.y2, sekce 11) |
| Překlady/XLIFF (NAB AL Tools, trans-unit ID), dokumentace requirementů (`docs/*.md`), uživatelská příručka featury (HTML se screenshoty v `docs/`), co číst před editem (app.json, .alpackages), Word layouty (repeater `w15:dataBinding`), analyzery AA/CA/PTE/LC, XML doc komentáře, build diagnostika, ruleset | `bc-al-workflow` | `bc-al-workflow.md` (sekce 6, 8, 9, 12) |
| Kompilace z CLI (alc, analyzery, UTF-16 logy, dočasná package cache, BOM-aware ID), Bash/heredoc pasti Claude Code, symboly (.alpackages, al-mcp), BC source na GitHubu, AL-Go, nová appka v repu (GUID, idRanges, affixy, permission sety), source závislé appky, git/commit/PR pravidla, verzování app.json, Azure DevOps MCP/PAT, case-only rename | `bc-al-tools` | `bc-al-tools.md` (sekce 7.1–7.10) |
| NuGet dependencies a minima (MajorMinor/LatestMatching, dedupe per GUID), symboly test frameworku z MSSymbols feedu (lokalizační appky s `.cz.` infixem od BC 28), kolize object ID po merge, major version bump, Essence build faily (testy, squash merge, Subcontracting ≥ 28.3, BC_ARTIFACT, Compile AL Apps bez `##[error]` / PTE0012), Deploy Staging sync mode/ForceSync/obsolete, smíchané verze MS symbolů | `bc-al-build` | `bc-al-build.md` (sekce 7.11–7.21) |
| Cokoliv kolem automatizovaných testů (test app, libraries, handlery, runner, Setup Storage, TestPage vs Rec.Validate, modální Worksheet bez Cancel, lokální kompilace test appky, gotchas) — a implementace netriviální funkčnosti | `bc-al-autotests` | `bc-al-autotests.md` (+ příloha `bc-al-autotests-saas-fallback.md` jen pro SaaS-only) |
| Essence Configurator (prod-ess-configurator-bc, COEBS; rozšíření COALU/COZLK): konfigurační parametry a podmínky, dialog varianty, systémové parametry (QUANTITY, CNC X1/X/Y/Z) a tiché nuly, číselné vzorce (Action Formula Line, PK bez Field Type) i textové vzorce (konkatenace + řádek Formula s vloženým výrazem), identita varianty, akce kusovníku/postupu/prodejního řádku, diagnostika přes service stránky, Zrušit editorů vzorců (`WasCancelled` / `EditFormula`), pole EM Cutting Plan na kusovníku z konfigurátoru | `ess-configurator` | `ess-configurator-notes.md` |
| Oficiální BC MCP server (`mcp.businesscentral.dynamics.com`): konfigurace v BC (page 8350/8351, Dynamic Tool Mode), Entra app registrace vs. device login, Claude Code `--mcp-config` + `headersHelper` | — (draft, bez skill-wrapperu) | `bc-al-mcp-server.md` v adresáři skillu `bc-al` |
| Nejsi si jistý rozsahem | všech 8 hlavních `bc-al-*` | `bc-al-style/ui/data/objects/integrations/workflow/tools/build.md` |

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
  jen do XLIFF. **Jazyk komunikace:** podle always-on souboru uživatele.
- **Git v pracovních repech:** commit / push / PR **nikdy sám** (7.7 v
  `bc-al-tools.md`). Na startu seance a před každým vyžádaným commitem/pushem
  **mergni `origin/master`** a vyřeš konflikty (7.7b). Verzi `app.json`
  nepovyšuj (7.8). ADO PAT je read-only záměrně — 401 na zápis neobcházet (7.9).
- **Nový poznatek → zapiš.** Když během práce zjistíš něco užitečného pro
  BC/AL, doplň to do příslušného `bc-al-*.md` (nebo to nabídni) a **rovnou
  commitni + pushni** v notes repu — jeho kořen je
  `git -C <adresář skillu> rev-parse --show-toplevel` (přes junction funguje) —
  krátká zpráva co + odkud (repo/PR/build/datum). Notes repo je **výjimka**
  z pravidla 7.7. **Každá** změna tady (notes, skilly, README) jde do **všech**
  remotů, které `git remote` vypíše (typicky jen `origin` =
  `essencebs/BCALInsights`; kdo má navíc vlastní fork, pushne i tam —
  `for r in $(git remote); do git push $r master; done`), ať se repa nerozejdou.
  Po doplnění `wc -l`: soubor **> 1000 řádků → rozděl** (vyčleň ucelené sekce do nového
  `bc-al-*.md`, zachovej číslování, mechanicky přes sed/skript, ne přepisem),
  aktualizuj Router tady, `README.md` a přidej nový skill-wrapper do `skills/<název>/`
  (notes soubor leží vedle jeho `SKILL.md`)
  (vzory: 7.11–7.19 → `bc-al-build.md` 2026-09-01; sekce 4 → `bc-al-ui.md`
  a 5.y2 + 11 → `bc-al-integrations.md` 2026-09-08). Always-on soubory ostatních
  nástrojů Router nedrží, jen odkazují sem — ty netřeba měnit; jen seznam skillů
  v `~/.claude/CLAUDE.md`, pokud ho tam uživatel drží. Důvod: soubory přes ~750 řádků / ~50 KB
  se nevejdou do jednoho readu (limit je ~25k tokenů ≈ 50 KB, ne řádky).
- **TL;DR ve skillech needituj kvůli novým gotchas** — tam patří jen stabilní
  pravidla; poznatky jdou do `bc-al-*.md`. Skill TL;DR uprav, jen když se
  mění pravidlo samo (a bumpni `version` v `.claude-plugin/plugin.json`).
- **Nové téma v notes = nové klíčové slovo ve skillu.** Když poznatek otevírá
  novou sekci / nový objekt / nový nástroj (ne jen další odstavec k existující
  sekci), doplň ho i do `description` příslušného skillu (to je trigger, podle
  kterého si agent skill načte — bez klíčového slova se nenačte) a do Routeru
  tady. `description` má limit **1024 znaků** → `python check-skills.py`
  v kořeni repa hlídá délky; při přetečení zhusti, nemaž. Klidně to dělej
  hromadně (audit 2026-09-07 dohnal 30 commitů notes najednou).
- **Fallback bez skillů:** přečti přímo `skills/bc-al/SKILL.md` (tenhle soubor)
  v klonu notes repa — cestu ke klonu má uživatel v always-on souboru — a notes
  ve `skills/<název>/<název>.md`. Ostatní nástroje:
  Copilot `~/.agents/skills` + `.instructions.md` (applyTo `*.al`), Codex
  `~/.agents/skills` + `~/.codex/AGENTS.md`, Antigravity `~/.gemini/config/skills`
  + `~/.gemini/GEMINI.md` — všechno junctiony na `skills/` v tomhle repu.
