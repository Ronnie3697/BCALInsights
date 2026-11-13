---
name: bc-al-deploy
description: >-
  BC/AL testovací kontejner a ruční nasazení mimo pipeline (Business Central, Essence, 7.23–7.26): lokální Docker
  kontejner pro autotesty (Test-Repo.ps1, BcContainerHelper bez admina, pool + zámek, závislosti z BCNugetPackages
  publikované, ne nainstalované, ERROR DIALOG, zbytky -KeepApps, verze BC kontejneru vs. BC_ARTIFACT), ruční PTE
  upload z NuGetu do SaaS sandboxu přes Automation API (extensionUpload, schemaSyncMode Add/Force, AVS0109 = dev build
  téže appky, upgrade závislosti pod dev buildy), závislosti jako Dev appky do sdíleného kontejneru
  containers.essencebs.com (dev endpoint, Basic auth, scope Global vs Tenant, AL1024), dev publish do SaaS sandboxu
  přes altool (osiřelá data, duplicate package ID, ForceSync, update sandboxu smaže dev buildy, schema diff před
  publishem, symboly z dev endpointu prostředí + novější deps z NuGetu, al_downloadsymbols s víc projekty). Načti
  při spouštění testů v kontejneru a při nasazování appek do sandboxu / kontejneru.
user-invocable: true
---

# BC/AL — Testovací kontejner a ruční nasazení (sekce 7.23–7.26)

**Zdroj pravdy:** `bc-al-deploy.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; příkazy, URL, skripty a historie případů jsou v souboru. Vyčleněno z `bc-al-build.md`
2026-11-13, číslování 7.x je původní (7.11–7.22 zůstává ve skillu `bc-al-build`, 7.1–7.10 ve skillu `bc-al-tools`).

## Co udělat

1. **Přečti `bc-al-deploy.md` z adresáře tohoto skillu celý.** Vejde se do jednoho Read; když se výstup ořízne,
   okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli, nepřepisuj potichu. Nový poznatek →
   do souboru + commit + push (viz skill `bc-al`).
3. Sousední témata: NuGet minima, CI build, Deploy Staging, release deploy (7.11–7.22) → `bc-al-build`; kdy autotesty
   pouštět (jen po vyžádaném push, 7.7b), alc, git, verzování app.json (7.8) → `bc-al-tools`; psaní testů →
   `bc-al-autotests`, test appka a její kompilace → `bc-al-autotests-infra`.

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **7.23** Lokální kontejner (`Test-Repo.ps1`) jen po vyžádaném push a jen kdo ho v setupu přijal. Výsledek čti
  z řádku `SUMMARY` a hlídej `ERROR DIALOG` / počet testů (exit code wrapperu lže). Dva běhy v jednom kontejneru se
  rozbijí → pool + zámek. Závislosti nech publikované, ne nainstalované; zbytky odinstaluj `-DoNotSaveData` +
  `Sync-NAVApp -Mode Clean`.
- **7.24** Ruční PTE do sdíleného sandboxu jen na výslovný pokyn. Automation API `extensionUpload` (PATCH obsahu +
  `Microsoft.NAV.upload` s `-d ""`), stav v `extensionDeploymentStatus`. AVS0109 = nainstalovaný dev build téže appky.
- **7.25** Sdílený kontejner: dev endpoint `…/<kontejner>dev/dev/apps`, Basic auth z okna (heslo ne do chatu),
  publikuj do stejné vrstvy jako závislosti (Tenant vs Global, jinak AL1024).
- **7.26** Dev publish do sandboxu přes `altool publishapp`: před publishem porovnej schéma nainstalovaného buildu
  s čerstvým (nic navíc v prostředí = Synchronize projde), ForceSync jen se svolením. Po každém pokusu ověř
  `…/extensions` (`isInstalled`, `publishedAs`). Update sandboxu smaže všechny dev buildy.
