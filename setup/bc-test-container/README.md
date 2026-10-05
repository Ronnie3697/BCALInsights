# Lokální BC kontejner na autotesty

Šablona nástroje — `SETUP.md` (krok 9) ji zkopíruje do `<PRACOVNÍ-REPA>\bc-test-container\`, tam pak žije
i stažený BcContainerHelper (`Modules\`), heslo kontejneru (`credential.xml`) a `settings.json`. **Do tohohle repa
nic z toho nepatří.** Po `git pull`, který změní skripty tady, je zkopíruj znovu (`*.ps1`, `README.md`).

Jeden sdílený Docker kontejner (`bctest28`, BC 28.4 OnPrem cz + test toolkit) pro autotesty všech repo
(`cust-*`, `prod-*`). Repo se do něj nahraje, otestuje a appky se zase odinstalují — zákaznické appky sdílí PTE
rozsah ID, vedle sebe by se popraly. AI agent ho pouští **před každým push** (7.7b v `bc-al-tools.md`), detail
a pasti 7.23 v `bc-al-build.md`.

## Předpoklady (jednorázově, admin)

- Docker Desktop (`winget install Docker.DockerDesktop`) ve **Windows containers** módu (pravým na ikonu →
  *Switch to Windows containers…*, nebo `& "$env:ProgramFiles\Docker\Docker\DockerCli.exe" -SwitchWindowsEngine`).
  Licence Docker Desktopu je pro firmy nad 250 lidí / 10 M$ obratu placená — ověř.
- Uživatel ve skupině `docker-users` — nejdřív ověř: `whoami /groups` (přihlašovací token) a `net localgroup docker-users`
  (skupina). Ve skupině je, v tokenu ne → stačí odhlásit / restart. Není ani ve skupině → v PowerShellu **jako správce**
  `Add-LocalGroupMember -Group docker-users -Member "<DOMÉNA>\<uživatel>"` (celé jméno vypíše `whoami`), pak
  **odhlásit / restart**. Bez toho Docker Desktop hlásí *„checking group membership: user is not a member of the group"*.
- RAM: kontejner si vezme ~8,5 GB (limit `memoryLimit`), disk ~40 GB (artefakty + image).

## Instalace (bez admina)

```powershell
cd <PRACOVNÍ-REPA>\bc-test-container
powershell -ExecutionPolicy Bypass -File Install-Helper.ps1      # BcContainerHelper do .\Modules
powershell -ExecutionPolicy Bypass -File New-TestContainer.ps1   # ~25 min poprvé (artefakty + generic image)
```

`settings.json` (volitelný, chybějící klíč = výchozí hodnota):

```json
{
  "containerName": "bctest28",
  "version": "28.4",
  "country": "cz",
  "memoryLimit": "8G",
  "patFile": "<MCP_PAT>\\DevOpsPAT.txt"
}
```

`patFile` = read-only PAT z `SETUP.md` krok 8b — stačí na NuGet feed `BCNugetPackages` se závislostmi
(výchozí hodnota: `..\MCP_PAT\DevOpsPAT.txt` vedle složky nástroje).

## Test repa

```powershell
powershell -ExecutionPolicy Bypass -File Test-Repo.ps1 -RepoPath <PRACOVNÍ-REPA>\prod-ess-configurator-bc
powershell -ExecutionPolicy Bypass -File Test-Repo.ps1 -RepoPath <repo> -TestCodeunit 63173     # jen jeden codeunit
powershell -ExecutionPolicy Bypass -File Test-Repo.ps1 -RepoPath <repo> -KeepApps               # appky nechá nainstalované
```

Co dělá (stejně jako Essence pipeline):

- nastartuje Docker Desktop a kontejner, když stojí,
- najde `app.json` v repu, seřadí appky podle závislostí, testovací = má „Test" v názvu; repo bez testovací appky
  hned skončí (`SUMMARY: … nothing to run`, exit 0),
- externí závislosti stáhne z NuGet feedu `BCNugetPackages` — nejnovější verze v MajorMinor rozsahu deklarovaného
  minima, i s tranzitivními,
- chybějící Microsoft appky (např. AI Test Toolkit) doinstaluje z artefaktu v kontejneru,
- appky zkopíruje do sdílené složky kontejneru (repo zůstane netknuté), zkompiluje a nainstaluje,
- pustí testy testovacích appek, vypíše `SUMMARY: <n> tests, <n> failed, …` + seznam failů, uloží `TestResults.xml` (JUnit),
- na konci odinstaluje a unpublishne všechno, co přidal (kromě Microsoft appek). Exit code 0 = vše prošlo.
- poslední řádky: `TIMING: start …, dependencies …, compile …, publish …, tests …, cleanup …, total mm:ss` a cesta k výstupu běhu.

Výstup běhu: `C:\ProgramData\BcContainerHelper\Extensions\<container>\test-runs\<repo>-<čas>\`
(`run.log`, `TestResults.xml`, `output\*.app`). Doba: konfigurátor (4 appky, ~900 testů) ~6 min.

## Proč Windows PowerShell 5.1

BcContainerHelper je nejvíc odladěný na Windows PowerShellu 5.1 (vestavěný ve Windows), skripty se proto
pouští přes `powershell.exe`. PowerShell 7 (`pwsh`) je samostatná instalace na .NET Core se svými verzemi modulů;
když se 5.1 spustí z prostředí, které nastartovalo pwsh 7 (terminál, VS Code, AI nástroj), zdědí jeho
`PSModulePath` a místo svých modulů načítá ty z PS 7 → `PowerShellGet`, `Get-ExecutionPolicy`… hlásí *„module
could not be loaded"*. Skripty si proto `PSModulePath` na začátku srovnají na cesty 5.1.
