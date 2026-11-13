# BC/AL poznámky — Testovací kontejner a ruční nasazení (sandbox, kontejnery, dev publish)

> Část rozděleného `bc-al-notes.md`. Sekce **7.23–7.26** vyčleněny z `bc-al-build.md` 2026-11-13 (soubor dosáhl
> ~1000 řádků — pravidlo dělení viz skill `bc-al`). **7.11–7.22** (NuGet dependencies, test symboly, kolize ID,
> major bump, CI build, Deploy Staging, release deploy) zůstávají v `bc-al-build.md`, **7.1–7.10** (alc, al-mcp,
> git/PR, verzování app.json, Azure DevOps MCP) v `bc-al-tools.md` — odkazy „viz 7.11“ apod. bez souboru hledej tam.
> Načítej, když řešíš: autotesty v lokálním Docker kontejneru (`Test-Repo.ps1`, BcContainerHelper), ruční nasazení
> PTE z NuGetu do SaaS sandboxu (Automation API, AVS0109), závislosti jako Dev appky do sdíleného kontejneru
> `containers.essencebs.com`, dev publish do SaaS sandboxu přes `altool` (osiřelá data, duplicate package ID,
> ForceSync, symboly z dev endpointu prostředí).
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **7.** Nástroje a workflow — část **7.23–7.26** (lokální testovací kontejner, ruční nasazení do sandboxu / sdíleného kontejneru, dev publish přes altool)

## 7. Nástroje a workflow — testovací kontejner a ruční nasazení (7.23–7.26)

### 7.23 Lokální testovací kontejner — autotesty před merge, bez admina (BcContainerHelper)

PR buildy testy nespouští (7.15), takže první běh nových testů je až na masteru — ⚠️ **neplatí pro každé repo**: cust-sonnentor-bc je v PR buildu pouští (PR 9940, buildy 29348 a 29373 nad `refs/pull/9940/merge`: 607 a 608 testů, 2026-11-11; počet ověř MCP `testplan_show_test_results_from_build_id`). Lokální běh po push má smysl dál (výsledek dřív, jiná minor verze BC než CI). Lokální Docker kontejner
s test toolkitem to obejde: repo se do něj nahraje, otestuje a appky se zase odinstalují. **Reprodukuje CI věrně**:
prod-ess-configurator-bc master eeba4b9 v něm spadl na **stejných 2 testech se stejnými hláškami** jako master build 28617
a opravená větev prošla (2026-10-05, BC 28.4 cz, BcContainerHelper 6.1.18).

Nástroj: šablona v notes repu **`setup/bc-test-container/`** (vlastní README), `SETUP.md` krok 9 ji zkopíruje do
`<PRACOVNÍ-REPA>\bc-test-container\` (tam i `Modules\`, `credential.xml`, `settings.json`) — `Install-Helper.ps1`,
`New-TestContainer.ps1` (kontejner `bctest28`), `Test-Repo.ps1 -RepoPath <repo> [-TestCodeunit <id>] [-KeepApps]`
(nastartuje Docker Desktop i kontejner; repo bez testovací appky hned skončí). **Agent ho pouští po každém vyžádaném push**
— nejdřív push, pak testy (7.7b v `bc-al-tools.md`); kdo kontejner v setupu odmítl, tomu se nepouští ani nenabízí.
⚠️ Verze šablony do 2026-10-06 volala `Get-BcContainerPath` **před** `Start-TestContainer` → s vypnutým Dockerem běh spadl
na `failed to connect to the docker API at npipe:////./pipe/dockerDesktopWindowsEngine` + `Get-BcContainerSharedFolders :
The property 'HostConfig' cannot be found` (exit 1, testy neběžely) místo toho, aby Docker nastartoval. A hned po startu
Docker Desktopu je kontejner zase `running` (restart policy), ale BC služba uvnitř je `StartPending` (health `starting`, pár
minut) → první `docker exec` padá na `No such exec instance` / `ServerInstance 'MicrosoftDynamicsNavServer$BC' is not running`.
Opraveno v šabloně: cesta ke `ContainerSide.ps1` se zjišťuje až po startu a `Start-TestContainer` čeká na health `healthy`
(max 10 min) — kdo má kopii starší, zkopíruj `Test-Repo.ps1` a `Import-Helper.ps1` znovu.
⚠️ Ani health `healthy` nestačí (2026-10-12, dotykackaConnector): hned po startu Docker Desktopu hlásil kontejner healthy, ale
služba `MicrosoftDynamicsNavServer$BC` byla `Stopped` → `StartPending` a první skript v kontejneru (NuGet závislosti) spadl na
`ServerInstance 'MicrosoftDynamicsNavServer$BC' is not running` (exit 1, testy neběžely). `Start-TestContainer` teď čeká i na
`docker exec <kontejner> powershell (Get-Service 'MicrosoftDynamicsNavServer$BC').Status` = `Running`. ⚠️ **Ani jedno `Running`
nestačí** (2026-10-16, dotykackaConnector): po startu Docker Desktopu služba hned hlásila Running, sessions závislostí prošly a
o minutu později ji startovací skript kontejneru restartoval → `Compile-AppInBcContainer` spadl na *StartPending* / *is not
running*. Šablona proto po startu Dockeru nebo kontejneru chce **90 s nepřetržitě Running** (teplý běh beze změny). Ruční obejití: počkat
pár minut a pustit `Test-Repo` znovu. A z Git Bash cestu `-RepoPath` dávat v **jednoduchých uvozovkách** — bez nich Bash
sežere zpětná lomítka (`C:WorkTasksprod-…` → `Resolve-Path` cannot find path).
⚠️ **Dva běhy v jednom kontejneru se rozbijí navzájem** (2026-10-09: tři seance — konfigurátor, cust-sonnentor-bc,
dotykackaConnector — pustily `Test-Repo` do `bctest28` současně): cizí publish/unpublish uprostřed testů → `ERROR DIALOG: You
tried to invoke the CodeUnit object with the ID 63190 … does not exist`, zbylých 14 test codeunitů neběželo a skript přesto
hlásil `SUMMARY: 622 tests, 0 failed` (místo 1046) + exit 0. Od téhle verze šablony: **pool kontejnerů** (`settings.json`
`"containerNames": ["bctest28", "bctest28b"]`, druhý `New-TestContainer.ps1 -ContainerName bctest28b`, ~8,5 GB RAM navíc,
image i artefakty sdílí) a **zámek na kontejner** (`test-run.lock` otevřený bez sdílení — s pádem procesu se uvolní sám,
`test-run.owner` = kdo ho drží); běh si vezme první volný, jinak čeká. `ERROR DIALOG` během testů = exit 1 + `BROKEN (tests
not run)`. Kontrola i u starší kopie: počet testů proti předchozímu běhu a `grep 'ERROR DIALOG'` v logu.
⚠️ **„`<appka> X is installed already (left by a run with -KeepApps?) - Y cannot be installed next to it`“ + `WARNING: The container
has apps installed by another run`** = v kontejneru zůstaly **nainstalované** závislosti z dřívějšího běhu (správně mají zůstat jen
publikované). Běh skončí po ~3 min, `tests 0 s`, exit 1 a testy vůbec neběžely. Bash wrapper s `; echo "exit $?"` vrací 0,
směrodatný je řádek `SUMMARY` v logu. Nejdřív zkontroluj, že starý běh nežije: `test-run.owner` v `…\Extensions\<kontejner>\`
zůstává i po skončení procesu, tak ověř `tasklist /FI "PID eq <pid>"`; `run.log` jeho složky v `test-runs\` ukáže, co odinstaloval.
Pak pusť běh do druhého kontejneru poolu (`-ContainerName bctest28b`), nebo zbytky odinstaluj **stejně jako úklid skriptu**:
`Uninstall-NAVApp -DoNotSaveData -Force` **+ `Sync-NAVApp -Mode Clean -Force`** (bez unpublish), v jedné `Invoke-ScriptInBcContainer`
relaci po `. Import-Helper.ps1`. ⚠️ Holý `Uninstall-NAVApp` nechá v databázi data staré verze a když je na feedu novější, další běh
spadne na *„Cannot install the extension … 28.0.11.0 … because an earlier version was already installed. Run Start-NAVAppDataUpgrade“*
— pak doběhni `Sync-NAVApp -Mode Clean` na všechny verze té appky (`Get-NAVAppInfo -Tenant default -TenantSpecificProperties`,
`IsInstalled = False`) a pusť běh znovu.
(2026-10-20, cust-sonnentor-bc: `bctest28` měl po včerejším „son“ běhu nainstalované Essence Shopify Connector 28.0.6.0, Essence
Distribution Base a ED Item Sales Disponibility; v `bctest28b` 321/321. 2026-10-23 znovu v obou kontejnerech — `bctest28` tytéž tři,
`bctest28b` navíc Warehouse Mobile Base 28.0.4.0 a EM Kiosk; holý uninstall → chyba Start-NAVAppDataUpgrade, po `Mode Clean` 346/346.)

**Předpoklady a pasti (Windows 11, uživatel bez admina):**

- Docker Desktop ve **Windows containers** módu a uživatel ve skupině **`docker-users`** — jinak Docker Desktop nenastartuje
  (*„checking group membership: user is not a member of the group"*, engine pipe `dockerDesktopWindowsEngine` neexistuje).
  Skupina bývá prázdná; přidání jen admin (`Add-LocalGroupMember -Group docker-users -Member corpnet\<user>`) + odhlášení
  / restart (členství je v přihlašovacím tokenu). Kontrola z Git Bash: `MSYS2_ARG_CONV_EXCL="*" whoami.exe /groups` (bez
  přepínače MSYS přepíše `/groups` na cestu a `whoami` z Gitu `/groups` nezná).
- **Windows PowerShell 5.1 spuštěný z Git Bash zdědí `PSModulePath` PowerShellu 7** → `PowerShellGet`, `Get-ExecutionPolicy`
  apod. selžou („module could not be loaded"). Ve skriptu nejdřív `$env:PSModulePath` = jen 5.1 cesty (Program Files +
  System32).
- `Install-Module -Scope CurrentUser` spadl na `Documents\WindowsPowerShell\Modules` (složku nejde vytvořit ani `mkdir` —
  nejspíš Controlled Folder Access) → **`Save-Module BcContainerHelper -Path <vlastní složka>`** + `Import-Module <cesta>\BcContainerHelper.psd1`.
- BcContainerHelper bez admina funguje; varování *„does NOT have Full Control to C:\ProgramData\BcContainerHelper"* a k
  `hosts` jsou jen varování (`-updateHosts` nepoužívat). `Compile-AppInBcContainer` sahá na dev endpoint přes **IP kontejneru**,
  hosts záznam netřeba.
- `New-BcContainer -accept_eula -artifactUrl (Get-BcArtifactUrl -type OnPrem -version 28.4 -country cz -select Latest)
  -auth NavUserPassword -Credential <cred> -includeTestToolkit -includeTestLibrariesOnly -memoryLimit 8G -shortcuts None`
  — první vytvoření ~25 min (artefakt + generic image `ltsc2025`, Hyper-V izolace), AI Test Toolkit v kontejneru už byl.
  Heslo admina generuj náhodně a ulož `Export-Clixml` (DPAPI). Onprem artefakty: 28.3.52162.52222, **28.4.53241.0**, 28.5.54151.0.
- **Závislosti z `BCNugetPackages` stačí read-only MCP PAT** (`DevOpsPAT.txt`, 7.9 v `bc-al-tools.md`): `Find-BcNuGetPackage
  -nuGetServerUrl https://pkgs.dev.azure.com/essencebs/Projects/_packaging/BCNugetPackages/nuget/v3/index.json -nuGetToken <PAT>
  -packageName (Get-BcNuGetPackageId -publisher … -name … -id …) -version "[<min>,<Major>.<Minor+1>.0.0)" -select Latest` vrátí
  `feed, packageId, version` (= MajorMinor + LatestMatching pipeline, 7.11; ~1 s), `Get-BcNuGetPackage … -select Exact` balíček
  stáhne. Essence balíčky mají závislosti v `.nuspec` (vyrábí je `New-BcNuGetPackage`): Essence ID s GUIDem, Microsoft appky jako
  `Microsoft.<Name>.<guid>` (Subcontracting), plus `Microsoft.Application` / `Microsoft.Platform`. Basic auth `user:<PAT>`.
  ⚠️ `Get-BcNuGetPackage` rozbaluje při **každém volání do nové temp složky** — mezi běhy necachuje; vlastní cache dle id/verze.
- **`Compile-AppInBcContainer` chce projekt, output i symboly ve složce sdílené s kontejnerem** (*„is not shared with the
  container"*) → appky repa zkopíruj do `C:\ProgramData\BcContainerHelper\Extensions\<container>\…` a kompiluj tam
  (bonus: alc nepřepíše `.docx` layouty ani `.g.xlf` v repu, 7.1 v `bc-al-tools.md`); `-CopyAppToSymbolsFolder` pro další appky.
  Totéž u **`Run-AlPipeline -reUseContainer -useDevEndpoint`**: `-baseFolder` musí být složka **nasdílená při vytvoření
  kontejneru** (`docker inspect <container> --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}'` → typicky
  `…\scratchpad\soitron-src -> c:\sources` z první seance), jinak krok „Compiling apps" spadne na *„<baseFolder> is not
  shared with container"*. Nový scratchpad = pracovní kopii repa robocopy do té staré nasdílené složky (ne nový kontejner).
  Pipeline Soitron (3 appky + 3 test appky, 212 testů) = 13 min, z toho testy 140 s. (2026-10-06, cust-soitron-bc 66675.)
- ⚠️ **Čas nežere práce, ale relace BcContainerHelperu.** Každé `Publish-BcNuGetPackageToContainer` / `Publish-BcContainerApp` /
  `UnPublish-BcContainerApp` otevře vlastní relaci do kontejneru a znovu čte seznam appek, platformu, zemi. Naměřeno (Zlomek,
  6 závislostí): přes `Publish-BcNuGetPackageToContainer` **134 s**, čisté operace uvnitř kontejneru — stažení 8 s, `Publish-NAVApp`
  8 s, `Sync-NAVApp` 2 s, `Install-NAVApp` 3 s; úklid 36 s proti 3 s. Proto **jedna `Invoke-ScriptInBcContainer` relace na krok**
  s `Publish/Sync/Install/Uninstall/Unpublish-NAVApp` uvnitř (funkce v `ContainerSide.ps1`, dot-source ze sdílené složky): závislosti
  23 s poprvé. **Závislosti nech publikované, ne nainstalované**: další běh jen `Sync` + `Install` (2,4 s za všech 6; s cache
  a kontrolou verze na feedu 10 s). Nainstalované by během testů jiného repa pouštěly své subscribery → výsledek jinak než CI.
  Odinstalace `-DoNotSaveData` + `Sync-NAVApp -Mode Clean` (data i schéma pryč), pořadí závislé první (`Dependencies` z
  `Get-NAVAppInfo -Id -Version`). Repo, jehož appka je jinde závislost (konfigurátor), si na začátku smaže všechny verze svých ID.
  Testy dál `Run-TestsInBcContainer -extensionId <test app> -testCodeunit … -detailed -returnTrueIfAllPassed -JUnitResultFileName …`
  (testovací appka = „Test" v názvu jako v CI).
- Doba (Zlomek, 4 appky, 144 testů): 7:03 → **4:23** (relace na krok) → **3:45** (závislosti publikované) — z toho kompilace
  `Compile-AppInBcContainer` ~2:30 (symboly pro každou appku znovu z dev endpointu). Verze kontejneru 28.4 je novější než
  `BC_ARTIFACT` pipeline (28.0–28.3); appky deklarují `application 28.0.0.0`, takže běží — výsledek se teoreticky může od CI lišit.
  ⚠️ **Stalo se:** cust-sonnentor-bc build 28705 (CI `bcartifacts/onprem/28.1/cz/weekly`) spadl na testu, který v kontejneru
  28.4 prošel samostatně, v celé codeunit i v celém repu (173/173). Příčina byla v base appce: `Req. Worksheet` umí otevřít list
  předaný přes `Page.Run(…, ReqLine)` s vyplněným Template + Batch (`GetCurrentJnlBatchName`) až od **28.4**, starší verze otevře
  první list šablony (recept v `bc-al-autotests-domains.md`). Když test lokálně projde a v CI ne, porovnej nejdřív verzi BC:
  CI ji vypisuje v kroku *Compile AL Apps* (`Artifact Description: bcartifacts/onprem/<ver>/cz/…`), lokální je v
  `bc-test-container\settings.json` (`version`). Rozdílné chování ověř přes historii souboru na StefanMaron
  (`commits?sha=w1-28&path=<soubor>` → commity per minor, raw URL se SHA, 7.3 v `bc-al-tools.md`).
- Alternativa bez kontejneru: pipeline jde pustit ručně na feature větvi (Run pipeline → branch), testy pak proběhnou před merge.
- **Zákaznické repo nad NEVYDANOU verzí produktové appky** (eventy / public procedury z feature větve, která ještě není na feedu):
  `Test-Repo.ps1` bere závislost z feedu → kompilace v kontejneru spadne. V obou variantách níž má produktová appka **verzi
  přepsanou jen v kopii `app.json`** nad minimum konzumenta (např. `28.0.99.0`; alc páruje podle vnitřní verze, 7.11), skript
  na začátku i na konci smaže všechny verze jejího ID (feedovou publikovanou závislost jiného repa další běh toho repa
  publikuje z cache znovu) a výsledek platí jen pro tu větev — po vydání minimum zvednout a běh zopakovat z feedu.
  **(a) Kombinované repo, beze změny skriptu:** appku, jejíž `id` je mezi `app.json` repa, skript kompiluje ze zdrojáků
  (`$repoIds`). Ve scratchpadu `git archive HEAD | tar -x -C <combo>\<repo>` (přesně pushnutý stav) + kopie `app/` produktové
  větve jako další složka (`<combo>\<repo>\coebs-66845\app`) a `-RepoPath <combo>\<repo>`. Seřadí base → COEBS → COZLK, testy
  jen testovacím appkám repa (produktová `test/` se nekopíruje). Ověřeno 2026-10-09, cust-zlomek-bc 66711 proti COEBS
  `66845_ConditionTreeFromStructure`: 173 testů, 0 failů, 7 min (kompilace COEBS ~1,5 min navíc). Kompilační check před push
  stejně přes alc a temp cache (COEBS proti své MS řadě, konzument proti `.alpackages` repa **bez** starých verzí COEBS +
  čerstvý build, 7.1 v `bc-al-tools.md`).
  **(b) Kopie skriptu s override hotového `.app`:** produktovou appku přelož z větve do scratchpadu a pusť
  **kopii** `Test-Repo.ps1` ve scratchpadu (dot-source `Import-Helper.ps1` a `ContainerSide.ps1` z pevné cesty
  `<PRACOVNÍ-REPA>\bc-test-container`, ne z `$PSScriptRoot`) s parametry `-OverrideAppId` / `-OverrideAppFile`: po rozřešení
  závislostí z feedu nahradí soubor té appky v `$dependencyFiles` (a smaže feedový ze symbols složky) a její ID přidá k ID repa
  pro úklid před a po běhu (všechny verze pryč, další běh si z feedu publikuje vydanou). Generátor kopie (python, `sub()`
  s kontrolou počtu výskytů) drž ve scratchpadu, ať se kopie dá přegenerovat po změně šablony. Ověřeno 2026-10-09:
  cust-alumistr-bc 66845 nad COEBS větví `66845_ConditionTreeFromStructure`, 218 testů, 7:49, v kontejneru po běhu nezůstal
  build 28.0.99.0. Varianta (a) je jednodušší (žádná kopie skriptu k udržování), (b) se hodí, když produktová appka
  v kontejneru nejde přeložit ze zdrojáků nebo chceš testovat přesně konkrétní hotový `.app`.

### 7.24 Ruční nasazení PTE z NuGetu do SaaS sandboxu (Automation API) — dev build stejné appky, AVS0109

Jen na výslovný pokyn uživatele (nasazení do sdíleného prostředí je těžko vratné). Ověřeno 2026-10-06, Alumistr BC-TEST2:
EPB Pricing Matrix 28.0.6, Alumistr SE Pricing Matrix Ext 28.0.50, Essence Configurator 28.0.33 + CZ 28.0.29, Alumistr
Configurator Ext 28.0.50.

- **Balíčky:** `query2?q=<guid>` na `BCNugetPackages` (read-only MCP PAT, 7.11) → `flat2/<id-lowercase>/<ver>/<id>.<ver>.nupkg`
  (`curl -4 -L -u u:<PAT>`; curl na redirect na blob auth nepřenese). `.nuspec` v balíčku vypíše závislosti, `.app` je uvnitř.
  Pořadí nasazení podle závislostí, jedna appka po druhé (~5 min na appku v sandboxu).
- **Upload = Automation API `extensionUpload`, totéž co `Publish-PerTenantExtensionApps`** (rychlejší to není, čas je
  serverový). `GET …/companies(<id>)/extensionUpload` → když záznam **existuje**, `PATCH …/extensionUpload(<systemId>)/extensionContent`
  (`If-Match: *`, `application/octet-stream`) + `POST …/Microsoft.NAV.upload`; když **neexistuje** (dokončený upload ho
  spotřebuje), nejdřív `POST extensionUpload` s `{"schedule":"Current Version","schemaSyncMode":"Add"}`. Stav:
  `GET …/extensionDeploymentStatus` (InProgress → Completed / Failed).
  - MCP `d365bc-admin create_pte_upload` spadl na „Failed to upload extension content" a pak na „Failed to create extension
    upload task" (záznam z prvního pokusu visel) — bez detailu; přímé volání API výš prošlo.
  - Node `https` neparsuje odpověď `Microsoft.NAV.upload` (`Parse Error: Expected HTTP/`, ani `insecureHTTPParser` nepomůže) —
    akci volej curlem. Polling `extensionDeploymentStatus` občas vrátí prázdné tělo → `JSON.parse` obal `try`.
  - curl `-X POST …/Microsoft.NAV.upload` **bez těla** vrátí `HTTP 411 Length Required` (IIS) → přidej `-d ""` (+ `Content-Type:
    application/json`), pak 200. Token do hlavičkového souboru a `curl -H @soubor`, ať není v příkazové řádce. (2026-10-20,
    Sonnentor BC-TEST, Dotykačka konektor 28.0.5.1, upgrade PTE→PTE za ~4 min.)
  - Token: `d365bc-admin get_microsoft_entra_id_token` (aud `api.businesscentral.dynamics.com`), drž ho v souboru ve scratchpadu
    a po skončení smaž.
- **Detail chyby** API nevrací: BC stránka 2508 *Stav instalace rozšíření* → řádek → 2509 → *Zobrazit podrobnosti*.
  Rychlejší: když upload skončí `Failed`, ale appka je v `…/extensions` jako `publishedAs: PTE`, `isInstalled: false`
  (publish prošel, spadla instalace), zavolej `POST …/extensions(<packageId>)/Microsoft.NAV.install` — 400 vrátí
  **celý text chyby** v `error.message`.
- **`Could not upgrade the extension … The field 'X' cannot be located. Removing fields is not allowed.` u appky, která
  v prostředí není nainstalovaná** = v DB zůstalo schéma **starší odinstalované verze** (odinstalace bez smazání dat), a nová
  verze pole odebrala. Fix (jen se svolením, maže data těch polí): nový `POST extensionUpload` s
  `{"schedule":"Current Version","schemaSyncMode":"Force"}` (API vrátí `Force_x0020_Sync`) + PATCH obsahu + `upload` — opakovaný
  upload téže už publikované verze projde. (2026-10-14, Alumistr BC-DEV: EPB Pricing Matrix 28.0.6 vs. zbytky `Width/Height PMEBS`.)
  Totéž přes dev endpoint (Dev build): `altool publishapp <app> … --schemaupdatemode ForceSync` (hláška v CZ „Pole 'X' nelze
  nalézt. Odebrání polí není povoleno.“, zbytek po odinstalovaném lokálním buildu téže appky). Před ForceSync se zeptej.
  (2026-10-16, Sonnentor BC-DEV: EW Mobile Base vs. pole `Country of Origin EXEBS` z prototypu 29. 9.)
- **curl `--data-binary @<cesta>` v Git Bash: `error encountered when reading a file`** = buď MSYS cestu `/c/…` za `@`
  nepřeloží (použij `@"$(cygpath -m "$f")"`), nebo cesta přesáhne **260 znaků** — rozbalená složka `.nupkg` ve scratchpadu
  (`x_<package-id>.<ver>/<Publisher>_<Name>_<ver>.app`) na to stačí, `ls` ji pak ukáže s prefixem `//?/`. `.app` zkopíruj
  do krátké složky (`a/1_altbom.app`). PATCH s nenačteným souborem odejde prázdný a `upload` vrátí `Extension content is empty`.
- **`AVS0109` „cannot be deployed as it has missing dependencies or the dependencies are conflicting with currently installed
  apps"** = v prostředí je **nainstalovaná DEV verze téže appky** (publikovaná z VS Code). Fix: `POST …/extensions(<packageId>)/Microsoft.NAV.uninstall`
  (data zůstanou; nejdřív závislé, např. Configurator CZ, pak Configurator), odpublikovat netřeba — PTE pak projde a převezme data.
  Odpublikovaný / přepsaný dev build už nevrátíš (nemáš jeho zdroják) → předem se zeptej. `GET …/extensions?$filter=id eq <guid>`
  ukáže všechny publikované verze se `publishedAs` (Dev / PTE) a `isInstalled`.
- **Opačný směr projde bez úklidu: dev publish (`altool publishapp`, dev endpoint, Synchronize) nad nainstalovaným PTE téže
  appky s VYŠŠÍ verzí PTE nahradí** — appka je pak `appType: dev`, data zůstala, závislé PTE (PMALU, Configurator CZ…) se
  neodinstalovaly. Verze dev buildu musí být > nainstalované PTE (jen v kopii `app.json`, 7.8). Další release PTE z pipeline do
  téhož prostředí pak narazí na AVS0109 výš → dev build nejdřív odinstalovat. (2026-10-13, Alumistr BC-TEST2 po čerstvé kopii
  z TEST: Alumistr Configurator Extension PTE 28.0.55.0 → dev 28.0.55.1.)
  **Update nad dev buildem = `altool publishapp` rovnou s `.app` z NuGetu** (CI build masteru, vnitřní verze `28.0.<build>.0` >
  dev buildu): bez lokální kompilace, bez uninstallu, ~1 min, appka zůstane `appType: dev`. Předem ověř, že ostatní dev buildy
  v prostředí (base, Configurator…) splní minima a mají všechny členy, které appka volá (CI ji kompiloval proti nejnovější verzi z feedu).
  `altool.exe` je v `<ext>\bin\`, ne v `bin\win32\`. (2026-10-26, Alumistr BC-TEST2: Configurator Ext dev 28.0.55.1 → 28.0.69.0.)
- **PTE z feature větve na sdílený TEST zamyká release z masteru.** Verze nad buildem masteru (`<build>.<rev+1>`, např.
  28.0.172.1 nad 28.0.172.0) projde a nic z masteru neubere, když větev master obsahuje (ověř `ci.sourceSha` buildu nainstalované
  verze přes `pipelines_build list buildNumber`). Nové tabulky a pole ale v masteru nejsou. Další release z masteru do téhož
  prostředí by je odebral, což je destruktivní změna a `schemaSyncMode: Add` ji odmítne (7.18). Release do TESTu proto počká na
  merge PR, jinak by šlo jen přes ForceSync se ztrátou dat. Řekni to uživateli hned u nasazení. (2026-10-21, Sonnentor BC-TEST,
  Sonnentor Extension 28.0.172.1 s uplatněním poukazů, upload `Completed` za ~3 min.)
- **PTE smí záviset na DEV appce** (MS Learn *Extension types and scope*) — PMALU / Configurator Ext jako PTE nad dev buildem
  Alumistr SE Extension prošly. Pozor: přesun / upgrade sandboxu odinstaluje DEV appky i PTE, které na nich závisí, a nový publish
  DEV buildu z VS Code může závislé PTE odinstalovat (tak na TEST2 zmizely PTE Alumistr appky z 26. 8.).
  Protipříklad: `altool publishapp` (Synchronize) dev → dev se **stejným schématem** závislou PTE nechal nainstalovanou (2026-10-27,
  TEST2: Essence Configurator dev 28.0.37.67241 → 28.0.38.66392, Alumistr Configurator Extension PTE 28.0.69.1 dál `installed`).
  Před publishem ověř původ dev buildu (vlastní build z commitu X → `git diff X origin/master -- */src/table*`), po něm
  `get_installed_apps` na závislé appky.
- **Upgrade PTE závislosti pod nainstalovanými DEV buildy závislých appek projde a závislé zůstanou nainstalované.** Alumistr BC-DEV
  (BC 29.1, 2026-11-13): po merge masteru chtěly Alumistr appky EM Cutting Plan 28.0.10 (v prostředí PTE 28.0.8), nový EM Cutting Plan
  Opticutter Connector 28.0.10 a EPB Pricing Matrix 28.0.7 (v prostředí 28.0.6, upgrade převádí osy Decimal → Code[50]). PTE upload
  z NuGetu (`schemaSyncMode: Add`) postupně Cutting Plan → Opticutter → Pricing Matrix skončil `Completed` za 1:50 / 0:45 / 1:30.
  Dev buildy Alumistr 29.0.0.0 (base, PMALU, CDS, COALU) a `Claude CNC Test Data` zůstaly `isInstalled = true`, teprve potom dev
  publish nových Alumistr buildů. `$filter` s mezerou v URL (`publisher eq '…'`) curl pošle nezakódovaný → prázdné tělo místo JSONu;
  `…/extensions` stáhni celé a filtruj lokálně.

### 7.25 Závislosti do sdíleného kontejneru `containers.essencebs.com` jako Dev appky (dev endpoint, UserPassword)

Ověřeno 2026-10-08: kontejner kolegy `bc28cu2-dev`, tenant `mnec-ef`, BC 28.2 cz; Essence Distribution Base 28.0.2,
ED Item Sales Disponibility 28.0.0, Essence Shopify Connector 28.0.6 (závislosti cust-sonnentor-bc).

- **URL podle Traefiku (BcContainerHelper):** `launch.json` `serverInstance: "<kontejner>dev"` → dev endpoint
  `https://containers.essencebs.com/<kontejner>dev/dev/…`, API (automation v2.0, OData) `…/<kontejner>rest/api/…`, web client
  `…/<kontejner>/?tenant=<tenant>`. Multitenant → všude `?tenant=<tenant>`. `GET …/<kontejner>dev/dev/metadata` jde bez auth
  (runtime, `webEndpoint`) — rychlý test, že kontejner žije.
- **Auth = Basic (NavUserPassword, `"authentication": "UserPassword"`).** Heslo si nenech psát do chatu: Windows PowerShell 5.1
  `$Host.UI.PromptForCredential(...)` otevře uživateli nativní okno, `Export-Clixml` uloží credential (DPAPI) do scratchpadu,
  další skripty `Import-Clixml`. Z Git Bash nejdřív `$env:PSModulePath` jen na cesty 5.1 (7.23). Login ověří
  `GET …rest/api/microsoft/automation/v2.0/companies?tenant=…` (401 = špatné údaje).
- **Co tam je:** `…/companies(<id>)/extensions` → `displayName`, `versionMajor…Revision`, `isInstalled`, `publishedAs`
  (`Global` = z artifactu, `" Dev"` s mezerou na začátku = dev publish). Microsoft deps (CZ packy, Intrastat Core, Shopify
  Connector) jsou v kontejneru z artifactu jako Global a nainstalované — nenahrávají se.
- **Nejnovější verze z feedu:** `query2?q=<guid>` na BCNugetPackages vrátí i historická package ID se stejným GUIDem (staré
  jméno / publisher: `EssenceInternationalsro.EDItemSalesDisponibility` končí 26.0.1, `EssenceBusinessSolutions.EDPDistribution`
  25.1.4) → ber ID, které má řadu `<major>.x`, verze z `flat2/<id>/index.json`. `.nupkg`: redirect URL s auth
  (`curl -w '%{redirect_url}'`), blob stáhni **bez** auth (7.11). Před publikem zkontroluj v `NavxManifest.xml`
  `Application` / `Platform` ≤ verze kontejneru a závislosti v `.nuspec` (Distribution Base → Microsoft `Intrastat Core`).
- **Publish = `POST …/<kontejner>dev/dev/apps?SchemaUpdateMode=synchronize&tenant=<tenant>`**, multipart s jedním souborem
  (`ContentDisposition` `form-data`, `Name` i `FileName` = název `.app`), Basic auth — totéž, co VS Code F5 nebo
  `Publish-BcContainerApp -useDevEndpoint`. V PS 5.1 `System.Net.Http.HttpClient` + `MultipartFormDataContent`,
  `Timeout = InfiniteTimeSpan`. `200 OK` s prázdným tělem = publikováno, synchronizováno i nainstalováno (1–5 s na appku).
  Pořadí podle závislostí. Dev build v prostředí pak blokuje PTE téže appky (AVS0109, 7.24).

- **`Publish-BcContainerApp` do kontejneru selže na `AL1024 … Symbols for the requested app X … could not be found in the
  database`, i když X v kontejneru nainstalovaná je — jako Dev z VS Code.** Bez `-scope` / `-useDevEndpoint` helper publikuje
  **Global** scope (`Publish-NAVApp`), a globální appka nevidí závislost publikovanou do **Tenant** scope (dev publish z VS Code
  = `PublishedAs " Dev"`, scope Tenant). Server při publishi kompiluje jen proti globálním symbolům → AL1024. Fix: publikovat do
  stejné vrstvy — `Publish-BcContainerApp … -scope Tenant -tenant <tenant>` (u single-tenant `default`), nebo
  `-useDevEndpoint` (totéž, co F5 z VS Code; `-scope Global` s dev endpointem helper odmítne). Alternativa: závislosti
  přepublikovat jako Global (`-scope Global` z `.app`), pak jde i hlavní appka Global — ale dev publish z VS Code na ně pak
  nejde. Ověř `Get-BcContainerAppInfo -containerName <c> -tenantSpecificProperties -sort DependenciesFirst` → sloupec `Scope`
  / `PublishedAs`. (2026-11-04, kontejner suys-dev: Suys Base 26.1 vs. Essence WMS Mobile Inventory 26.0 jako Dev.)

### 7.26 Dev publish do SaaS sandboxu přes `altool` — osiřelá data staré verze, duplicitní package ID, EM závislosti

- **Sandbox s osiřelými daty odinstalované verze** (banner *„There's orphaned data from uninstalled extensions"*): když nová verze
  pole odebrala, `altool publishapp` (Synchronize) skončí *„Pole 'Comment 1 ZLK' nelze nalézt. Odebrání polí není povoleno."*
- **Neúspěšný pokus balíček na serveru stejně zaregistruje** → opakování téhož `.app` hlásí *„A duplicate package ID is detected"*.
  Přelož znovu (každá kompilace = nové package ID) a publikuj s `--schemaupdatemode ForceSync` — **jen DEV**, zahodí data
  odebraných sloupců (7.18).
- **„A duplicate package ID is detected" i u úspěšného publishe do JINÉHO tenantu:** tentýž `.app` (stejné package ID)
  publikovaný do Alumistr BC-DEV a pak do Zlomek BC-DEV druhý publish odmítl. Pro každé prostředí přelož zvlášť (nové
  package ID), verze může zůstat stejná. (2026-11-03, PBI 67458.)
- ⚠️ **Neúspěšný dev publish NAD jiným dev buildem téže appky umí nechat prostředí BEZ appky.** Sonnentor BC-DEV (2026-10-27,
  dev 28.0.167.2 → 28.0.167.308, nainstalovaný závislý dev build `SON CDS Sync`): 1. pokus *„The Extension cannot be unpublished
  because it is in use by the following tenants: …"* + *„Původní rozšíření byla obnovena"*, ale **závislou appku odinstaloval a
  nevrátil**; 2. pokus (nová kompilace) starý build **odpublikoval**, schema sync pak spadl na *„Pole 'X' nelze nalézt. Odebrání polí
  není povoleno."* (pole kolegy z neodmergované práce, v DB ze starého buildu) → nový build publikovaný, nenainstalovaný, starý pryč.
  Proto **před publishem zkontroluj schéma**: `altool` na Synchronize nejdřív zkus jen když víš, že nainstalovaný build nemá pole navíc
  (vlastní build / build masteru); cizí dev build v prostředí = zeptej se předem na ForceSync. Po každém pokusu ověř stav přes
  automation `…/companies(<id>)/extensions` (`isInstalled`, `publishedAs`) — `get_installed_apps` (admin API) ukazuje jen nainstalované
  a starý build v něm „zmizí" bez hlášky. Odinstalované závislé appky vrať `POST …/extensions(<packageId>)/Microsoft.NAV.install` (204).
  Stažení symbolů z dev endpointu (`…/dev/packages?…&versionText=X`) vrací **nejnovější publikovaný** balíček, ne verzi X → obsah
  odpublikovaného buildu už nezjistíš. `versionText` = **minimum**: vyšší než nainstalovaná verze → **404** (minimum z `app.json`
  repa nad stavem prostředí). Dev build pak minima srovnej v kopii `app.json` na nainstalované verze a kompiluj proti symbolům
  z prostředí — 0 chyb = nic z novější verze nevoláš (2026-11-11, Alumistr TEST2: Opticutter 28.0.10 → 28.0.0, COEBS 28.0.41 → 28.0.39).
  **Dev build neznámého původu → porovnej symboly, než publikuješ.** Token z `d365bc-admin get_microsoft_entra_id_token` (aud
  `api.businesscentral.dynamics.com`) projde i na dev endpoint: `curl -4 -H @hdr "https://api.businesscentral.dynamics.com/v2.0/<tenant>/<env>/dev/packages?publisher=…&appName=…&versionText=<nainstalovaná>&appId=<guid>"`
  vrátí symbol nainstalovaného buildu (`Version` v `NavxManifest.xml` ověř, viz výš). Python diff `SymbolReference.json` (rekurzivně
  `Namespaces[]`): pole `Tables` / `TableExtensions` (Id, Name, typ) a `Methods` všech objektů (jméno + počet parametrů) proti čerstvému
  buildu. Nic navíc na straně prostředí = Synchronize projde a závislé PTE zůstanou nainstalované. (2026-11-02, Alumistr BC-TEST2: base dev
  28.0.55.1 bez známého commitu → 28.0.55.67394 z masteru, diff 0/0, PMALU / CDS / COALU PTE dál `installed`.)
- **Update sandboxu (např. 28.5.54151 → 28.5.54976) smaže VŠECHNY dev buildy, data i jejich verze v DB zůstanou.** Den předtím
  kompletní Zlomek stack na BC-DEV2 (PMEBS 28.0.7.6, Zlomek Extension 28.0.3.4, COZLK 28.0.99.0 jako dev) druhý den chyběl i v
  `…/extensions` (ani publikovaný), PTE zůstaly. Release PTE nižší verze pak skončí `Failed` a `Microsoft.NAV.install` vrátí *„Cannot
  install the extension … 28.0.6.0 because a newer version 28.0.7.6 was already installed“* — **ForceSync to nevyřeší** (hlídá verzi
  dat, ne schéma). Cesty: dev build verze ≥ té v datech ze stejné větve (schéma sedí, data zůstanou), nebo smazat osiřelá data
  appky celá (Extension Management → orphaned data) a pak release. Vyšší verze v datech (COZLK 28.0.99.0) zablokuje i budoucí PTE
  release z pipeline → do té doby jen dev buildy `28.0.99.<n>`. Na prostředí, kde se dev buildy „ztratily“, se nejdřív podívej do
  `extensionDeploymentStatus` (historie PTE uploadů) a starších snímků `…/extensions`. (2026-11-05, Zlomek BC-DEV2, 67632.)
- **Token z `d365bc-admin get_microsoft_entra_id_token` platí ~1 h** — dlouhá série PTE uploadů (5–8 min / appka) ho přežije těžko;
  `401 Unauthorized … credentials provided are incorrect` uprostřed = vzít nový token, ne hledat chybu v appce.
- **Na sdíleném DEV leží dev build rozpracované (necommitnuté) větve kolegy / tvé jiné seance → publikuj „combo“, ne čistou
  větev.** Čistý build tvé větve by featuru té druhé z prostředí vymazal (a s novými tabulkami ještě shodil Synchronize). Postup:
  zkopíruj working tree té appky z jejího klonu do scratchpadu (`cp -r app.json *.json *.png src Translations`, i untracked
  soubory), aplikuj svůj diff (`git diff -- <appka> ':!<appka>/Translations' > p.patch`, v kopii `git apply -p<n>`), XLIFF dogeneruj
  skriptem z nového `.g.xlf` (6.x v `bc-al-xliff.md`), verze = nainstalovaná s poslední částí +1 (`28.0.3.66431` → `.66432`, 7.8).
  Kompiluj proti symbolům **přesně nainstalovaných** dev buildů: al-official MCP `al_downloadsymbols` (projekt kopie, `environmentType
  Sandbox`, `environmentName`, `tenant`) — nejdřív `al_addproject` na tu kopii, jinak vrátí „No projects are loaded in the workspace“;
  stáhne jen přímé závislosti, tranzitivní (CZ packy, EM appky závislé base appky) doplň do `.alpackages` kopie ručně. Schéma ověř
  porovnáním `mtime` souborů `table*/` v klonu s časem publikovaného `.app` (scratchpad seance, která publikovala). Kolize ID mezi
  větvemi vyleze právě tady (1.12 v `bc-al-style.md`). Uživateli řekni, že build na DEV teď není ani jedna větev. (2026-11-05,
  Zlomek BC-DEV: COZLK 66431 Pozice + 67632, COEBS 28.0.39.66431 a Zlomek Extension 28.0.3.66431 nechané.)
- Příkaz (token z cache VS Code, bez interaktivního přihlášení, 7.2b v `bc-al-tools.md`): `altool.exe publishapp <app>
  --environmenttype Sandbox --environmentname <env> --tenant <tenantId> [--schemaupdatemode ForceSync]`; výstup filtruj
  `grep -v "^\[MSAL\]\|^\[LogMetrics"`, úspěch = `Success: The package … has been published`.
- **Prázdná `.alpackages` → celá package cache z dev endpointu sandboxu** (verze přesně jako v prostředí): token z `d365bc-admin`, `GET …/<env>/dev/packages?
  publisher=&appName=&versionText=&appId=` pro každou dependency z `app.json` + `System` (`8874ed3a-…`) a `Application` (`c1335042-…`), z `NavxManifest.xml`
  staženého `.app` vyčti `<Dependency>` a rekurzivně dál (python, IPv4). Test knihovny (*Tests-TestLibraries*, *System Application Test Library*) endpoint
  vrátí 404 → MSSymbols (7.12). Ověřeno 2026-11-05, Sonnentor BC-DEV (16 balíčků za ~1 min, alc app i test 0 chyb).
  **Minimum z `app.json` vyšší než verze v prostředí** (po merge masteru se zvednutými deps) vrátí 404. Ten balíček stáhni
  z BCNugetPackages (flat2 `.nupkg`, redirect bez auth, 7.11), zbytek dál z dev endpointu. Stejné `.app` pak poslouží jako PTE upload
  do prostředí (7.24). Vzor skriptu: `getsym.py` (2026-11-13, Alumistr BC-DEV 29.1 — MS 29.1 + Configurator dev 28.0.41.2
  z prostředí, Cutting Plan / Opticutter 28.0.10 a Pricing Matrix 28.0.7 z feedu).
- **al-official MCP `al_downloadsymbols` s víc projekty v jedné seanci:** první projekt (`al_addproject` → `al_downloadsymbols`)
  stáhne přímé závislosti i tranzitivní MS řadu (Application → Base App, Business Foundation, System App, System) do
  `<projekt>\.alpackages`, ne do sdílené `.alpackages` repa (workspace `al.packageCachePath` nečte). Další projekty pak vrací
  „Downloaded 0 of 1" s `cachePath` prvního projektu → zbytek přes dev endpoint skriptem výš. Hotové soubory přesuň do kořenové
  `.alpackages` a podsložku smaž (2026-11-13, AL 18.1.2842859).
- **Schema diff před publishem nad cizím dev buildem stejné verze:** dev endpoint vrátí symbol nainstalovaného buildu
  (`versionText` = nainstalovaná verze, 7.26 výš), porovnej `Tables` / `TableExtensions` a jejich pole s čerstvým buildem.
  Pouze nová pole a objekty na straně buildu znamenají, že Synchronize projde (Alumistr BC-DEV 2026-11-13: PMALU / COALU +
  `Parameter A/B Value` Code[50], `Optim. Requirement COALU`; jedna metoda v prostředí navíc, `BuildCNCSentenceForProdOrder`,
  je jen přejmenování na `…Line`). Stejný diff po publishi (0/0) potvrdí, že v prostředí je opravdu nový build.
- **Essence závislosti z dependency-cache lokálního testovacího kontejneru** (`C:\ProgramData\BcContainerHelper\Extensions\<kontejner>\dependency-cache\…`,
  7.23) jdou do sandboxu dev-publishnout stejně, v pořadí závislostí (EM Alternative BOM and Routing, EM MRP Replenishment, EM Net Make
  to Order, EM Production Batch Planning — v manifestu `<Dependencies />`, jen Application 28.0). `get_installed_apps` (d365bc-admin)
  je pak vrací s `appType: "dev"`. Dev build blokuje PTE téže appky (AVS0109, 7.24).

(2026-10-21, cust-zlomek-bc BC-DEV — ověření PBI 65654 / 65649 / 65149.)

- **Vlastní profil (*Vytvořeno uživatelem*) s role centrem z dev appky** po jednom z dev publishů ukazoval na **Blank Role Center
  (8999)** – úvodní stránka prázdná (desktop jen obrázek prázdného role centra, phone jen menu *Stránka / Systém*), stránky appky
  otevřené přes URL fungovaly. Oprava: *Profily (role)* (9171) → profil → *ID centra rolí* zpět na stránku z appky. Po publishi
  kontroluj úvodní stránku. (2026-10-23, prod-ew-mobileBase-bc BC-DEV, profil EW-MOBILE → 62202.)
