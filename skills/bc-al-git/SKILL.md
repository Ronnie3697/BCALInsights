---
name: bc-al-git
description: >-
  BC/AL git, PR a Azure DevOps z praxe (BC, AL, sekce 7.7–7.10): git commit /
  push / PR v pracovních repech nikdy sám (výjimka notes repo), merge
  origin/master na startu seance a před každým commitem / pushem, autotesty
  v lokálním kontejneru až po vyžádaném push, upstream past nové větve, čistá
  větev v druhém klonu z lokálního repa (origin/master = lokální master),
  ForcePush, verzování app.json (nepovyšovat, do PR XX.0.0.0), Azure DevOps MCP
  (org essencebs, PAT read-only záměrně – 401 neobcházet, search_code blob,
  IPv6 reset), texty do ADO (popis PR max 4000 znaků, PBI, Task, komentáře)
  jako Markdown blok bez zalamování, case-only rename složky appky. Načti
  u commitu, pushe, merge, PR, ADO a verze app.json. (alc, symboly, nová
  appka → skill bc-al-tools.)
user-invocable: true
---

# BC/AL — Git, PR a Azure DevOps (sekce 7.7–7.10)

**Zdroj pravdy:** `bc-al-git.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, příkazy a historie případů jsou v souboru.
Vyčleněno z `bc-al-tools.md` 2026-11-20, číslování 7.x je původní (7.1–7.6 zůstává ve skillu `bc-al-tools`,
7.11–7.22 ve skillu `bc-al-build`, 7.23–7.26 ve skillu `bc-al-deploy`).

## Co udělat

1. **Přečti `bc-al-git.md` z adresáře tohoto skillu celý.** Je krátký (~270 řádků). Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: alc, symboly, BC source, nová appka → `bc-al-tools` (7.1–7.6);
   NuGet minima, CI build, release deploy → `bc-al-build` (7.11–7.22); lokální testovací
   kontejner a jeho pasti → `bc-al-deploy` (7.23); dokumentace ticketu → `bc-al-workflow` (8).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **7.7 ⛔** `git commit` / `push` / PR / merge do master **nikdy bez
  výslovného pokynu** (výjimka: notes repo BCALInsights). **Vyžádaný push**
  = merge masteru + kompilace → **push** → teprve pak **autotesty celého repa
  v lokálním kontejneru** (`<PRACOVNÍ-REPA>\bc-test-container\Test-Repo.ps1`,
  7.7b); fail = opravit dalším commitem + push. Jen v rámci push, ne po každé změně,
  a jen kdo kontejner má (always-on `Lokální testovací kontejner: ano`; `ne` = nikdy). Nová větev z cizí
  upstream → `git branch --unset-upstream` nebo vždy `git push -u origin
  <větev>`. Dev nemá ForcePush → cizí větev zpět nevrátíš.
- **7.8** `version` v `app.json` neměnit sám; do PR `XX.0.0.0`.
- **7.9** ADO MCP: org `essencebs`, projekt `Projects`; repo odvoď z CWD /
  Area Path. **PAT je read-only záměrně — 401 na zápis neobcházet** jiným
  credentialem, PR zakládá uživatel. Texty do ADO jako jeden ` ```markdown ` blok,
  odstavec / bod na jednom řádku, název PR zvlášť; **popis PR max 4000 znaků**
  (spočítej před předáním, detaily do dokumentace MD). `search_code` vrací multi-MB blob →
  parsuj pythonem. IPv6 reset → `--dns-result-order=ipv4first`.
- **7.10** Case-only rename složky = obě cesty v merge → detekce
  `git ls-tree -r HEAD --name-only | sort -f | uniq -di`; rename dvoukrokově.
