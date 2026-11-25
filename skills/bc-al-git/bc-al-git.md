# BC/AL poznámky — Git, PR a Azure DevOps

> Část rozděleného `bc-al-notes.md`. Sekce 7.7–7.10 vyčleněny z `bc-al-tools.md` 2026-11-20 (soubor přesáhl
> 1000 řádků). **7.1–7.6** (alc, al-mcp, BC source, AL-Go, nová appka, source závislých appek) zůstávají
> v `bc-al-tools.md`, 7.11–7.22 jsou v `bc-al-build.md` a 7.23–7.26 v `bc-al-deploy.md` — odkazy „viz 7.x"
> hledej tam.
> Načítej, když řešíš: git commit / push / PR v pracovních repech, merge masteru, autotesty po push, verzování
> app.json, texty do ADO (popis PR, PBI, Task, komentáře), Azure DevOps MCP / PAT, case-only rename složky.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **7.** Nástroje a workflow — část **7.7–7.10** (7.1–7.6 → `bc-al-tools.md`)

## 7. Nástroje a workflow — git, PR a Azure DevOps (7.7–7.10)

### 7.7 Git commit / push / PR — **nikdy nedělat sám, ani commit**

**Jediná výjimka: notes repo BCALInsights** (sdílené poznámky, GitHub
`essencebs/BCALInsights`; klon podle always-on souboru uživatele nebo
`git -C <adresář skillu> rev-parse --show-toplevel`) — tam se nový poznatek commitne a pushne
rovnou, bez ptaní; smyslem repa je verzovat každou změnu (viz skill `bc-al`).
Všechno níže platí pro pracovní repa (cust-*, prod-*).

Lokální git operace, které jsou OK bez vyžádání:

- `git checkout` / `git checkout -b` (přepínání a vytváření branchů)
- `git add` / `git restore --staged` (stage / unstage do indexu — neměnný
  hash, jen příprava)
- `git cherry-pick`, `git merge`, `git rebase` (pokud uživatel nepoví jinak)
- `git stash`, `git restore` (lokální správa working tree)
- `git fetch`, `git pull --ff-only` (synchronizace s origin pro read)
- `git reset --soft` / `git reset` (zpětné rušení commitů, když uživatel
  řekne; měnit historii bez pokynu ne)

**Co NEDĚLAT bez explicitního vyžádání:**

- `git commit` (ani na feature branch, ani amend) — *commit* už mění
  historii, kterou bude uživatel potřebovat upravit / squashnout / zahodit
- `git push` (ani `-u origin`, ani `--force`, ani na nový branch)
- `git push --delete` / mazání remote branchů
- Vytváření Pull Requestů (`mcp__azure-devops__repo_create_pull_request`,
  `gh pr create`, jakákoli jiná cesta)
- Mergování do master / shared branche

**Po dokončení lokální práce:**

1. Změny nech jako **unstaged / staged** v working tree, **necommituj**.
2. Zastav a oznam uživateli: *„Změny pro `<task>` jsou připravené v
   working tree — můžeš zkontrolovat a zacommitovat / pushnout."* Uveď
   stručný souhrn co se změnilo a v jakých souborech.
3. Čekej na další pokyn. *Commit / push / PR provedu, až dostanu výslovný
   povel* („zacommituj to", „push to", „otevři PR", apod.).

**⚠️ Worktree/branch z CIZÍ upstream + holý `git push` = tichý push do cizí větve.**
`git worktree add -b NováVětev origin/CizíVětev` (nebo `git checkout -b`) nastaví
nové lokální větvi **upstream na `origin/CizíVětev`**. Pak holý `git push` (nebo
`push.default=simple/upstream`) pošle commity **do té cizí větve**, ne pod jménem
tvé nové — a když je tvůj HEAD fast-forward nad jejím tipem, **projde to bez
varování** (cizí větev + její PR se posunou o tvé commity). Prevence: hned po
založení buď `git branch --unset-upstream <větev>`, nebo první push dělej vždy
explicitně `git push -u origin <NováVětev>` (jméno větve v příkazu přebije špatný
upstream a rovnou nastaví správný tracking). Zachyceno: cust-alumistr-bc 2026-07-09
(větev ConfiguratorExtensionOdPNEZ omylem pushnutá do kolegovy ConfiguratorExtension).

**⚠️ Vrátit cizí větev zpět NEJDE — dev nemá ForcePush.** V essencebs ADO běžný
vývojář **nemá `Git 'ForcePush'` permission** na (sdílené) větve → jakýkoli
non-fast-forward push (reset větve na starší commit) skončí `TF401027: You need
the Git 'ForcePush' permission`. `--force-with-lease` na tom nic nezmění (právo je
server-side). Takže když omylem posuneš cizí větev dopředu, **sám ji nevrátíš** —
revert nech na **autorovi větve** (má práva na svou branch) nebo na **adminovi
repa**. Nouzově jde přidat *revert-commity* dopředu (fast-forward, bez force), ale
to zašpiní historii i cizí PR — poslední volba.

**Proč:**

- Uživatel chce konsolidovat víc změn do jednoho commitu / PR podle
  vlastního uvážení (parent PBI vs. dělené tasky), volit přesné commit
  message, případně z části změn slevit.
- Commit, push a PR mají dopad na CI pipeline a review timing — to je
  rozhodnutí uživatele, ne moje.
- Když rovnou commitnu / pushnu, vede to k nadbytečným reset/rebase
  manévrům na úklid.

**Čistá větev bez rozdělané práce v druhém klonu (`git clone <lokální repo> <repo>-<task>`):** klon z lokální cesty má jako
`origin/*` **lokální větve původního repa**, ne jeho `origin/*` — `origin/master` v klonu = zastaralý lokální `master` (v
cust-londonPharma-bc o několik PR pozadu, chyběla celá test appka). Větev zakládej na **SHA `origin/master` původního repa**
(`git -C <orig> rev-parse origin/master`), pak `git remote set-url origin <ADO URL>`, `git fetch --prune origin`,
`git branch -f master origin/master`, `git remote set-head origin -a` a smaž zkopírované lokální větve. Změny přenes kopií souborů,
když `HEAD` původního repa = `origin/master` (patch z `git diff` se kvůli CRLF/LF nemusí aplikovat); ověř `git diff --stat`
proti původnímu. Do klonu dokopíruj `.alpackages` a `.vscode` (gitignored). Větev zpět do původního repa:
`git -C <orig> fetch <klon> <větev>:<větev>`. (2026-11-25, cust-londonPharma-bc 67750.)

### 7.7b Merge masteru — na startu seance a před každým `commitni` / `pushni`

Pokyn uživatele (2026-09-22, cust-alumistr-bc): *„na začátku sessiony mergni master a vyřeš konflikty; a když napíšu
commitni nebo pushni nebo oboje, tak taky. Ať na to nemusím myslet."* Platí pro pracovní repa (`cust-*`, `prod-*`),
notes repo má vlastní režim (7.7).

**Na startu AL/BC seance** (krok 0 v rozcestníku `bc-al`), pokud stojíš na feature větvi:

1. `git fetch origin`
2. `git merge origin/master` (na masteru místo toho `git pull --ff-only`). Merge commit je tady výjimka z „commit nikdy sám" —
   je to synchronizace, ne práce uživatele.
3. Konflikty **vyřeš sám** podle smyslu obou stran (obě změny mají zůstat funkční; u `app.json` verzí ber master, u XLIFF obě
   sady trans-unitů, u object ID kolizí rozhodují nasazená data — 7.14 v `bc-al-build.md`). Po vyřešení zkompiluj dotčené appky.
4. Oznam: co se mergovalo (počet commitů / poslední sha masteru), které soubory měly konflikt a jak jsi ho rozhodl.
   Bez konfliktů stačí jedna věta („master mergnutý, bez konfliktů").
5. Merge odmítne kvůli **necommitnutým změnám** v souborech, kterých se master dotkl (*Your local changes … would be
   overwritten by merge*) → **nestashuj a nezahazuj**; řekni to uživateli a nech rozhodnutí na něm (commitnout rozdělané,
   nebo merge odložit). Pracuješ-li v `git worktree` z čerstvého `origin/master`, krok je no-op — jen to ověř `git status -sb`.

**Před vyžádaným `commitni` / `pushni` / obojím:**

- `commitni` → nejdřív **commit práce** (aby merge neblokovaly necommitnuté soubory), pak fetch + merge `origin/master`,
  vyřešit konflikty, znovu zkompilovat dotčené appky, teprve pak ohlásit hotovo. Výsledek = commit práce + případný merge commit.
- `pushni` → fetch + merge `origin/master` + konflikty + kompilace, pak `git push -u origin <větev>` (jméno větve vždy
  explicitně, viz past s cizím upstreamem výše) a **až po pushi autotesty v lokálním kontejneru** (níže).
- `oboje` → commit práce → merge masteru → push → autotesty.

**Autotesty po push** (pokyn uživatele 2026-10-05: *„Pokud napíšu push nebo něco, co ti řekne push, tak zapni kontejner a
pusť autotesty. Ať pushujeme větev, která pak nespadne na testech po PR, a zároveň ať se nezdržujeme čekáním na testy po
každé malé změně."*; pořadí upraveno 2026-10-09: *„Když napíšu push, tak pushni a pak pusť autotesty. Kdyby náhodou vyhořel
noťas, tak ať je ta větev aspoň online a aktuální."*). Platí pro každý pokyn, který vede k push (`pushni`, `oboje`,
„commitni a pushni", „pošli to na server"…). PR buildy testy spouštět nemusí (liší se per repo, 7.23 v `bc-al-deploy.md`), bez toho by nový test
poprvé běžel až na masteru. Starší znění always-on věty („autotesty před každým push“) se čte stejně — pořadí určuje tahle
sekce.

**Jen pro uživatele s lokálním testovacím kontejnerem** (rozhodnutí v `SETUP.md` krok 9, pokyn uživatele 2026-10-05):
always-on soubor uživatele má větu `Lokální testovací kontejner: ano …`, nebo — bez té věty — existuje
`<PRACOVNÍ-REPA>\bc-test-container\settings.json`. Věta `Lokální testovací kontejner: ne …` (kontejner v setupu odmítl,
na znění za pomlčkou nezáleží) = autotesty **nepouštěj nikdy**, neptej se na ně, nenabízej je a neříkej, že chybí —
pushni podle zbytku 7.7b a skonči.

1. Po merge masteru, kompilaci a **pushi** pusť **celé** testy repa v lokálním kontejneru (7.23 v `bc-al-deploy.md`), na pozadí:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "<PRACOVNÍ-REPA>\bc-test-container\Test-Repo.ps1" -RepoPath <kořen repa>`.
   Skript sám nastartuje Docker Desktop i kontejner; výsledek = řádek `SUMMARY: <n> tests, <n> failed` + exit code
   (konfigurátor ~6 min). `<PRACOVNÍ-REPA>` je v always-on souboru uživatele. Skripty jsou kopie šablony
   `<KLON>\setup\bc-test-container\` — liší-li se (po `git pull` notes), nejdřív zkopíruj `*.ps1` + `README.md`.
2. **0 failů → hotovo**, ohlas výsledek (`SUMMARY`). Fail → push se **nevrací**: ukaž faily (test + hláška) a oprav je
   dalším commitem + push (je-li to tvoje změna, jinak se zeptej); PR k merge neposílej, dokud není zeleno. Fail, který
   padá i na masteru (ne regrese větve), řekni a rozhodnutí nech na uživateli.
3. Repo bez testovací appky (`nothing to run`) → jen to zmiň. Kontejner uživatel má, ale teď nenaběhne (Docker
   nestartuje, kontejner smazaný) → push už je venku, řekni to a nabídni běh později.
4. **Jen v rámci push** — ne po každé změně, ne u samotného `commitni`, ne po kompilaci a ne „pro ověření“ po dokončení
   implementace (pokyn uživatele 2026-10-09: *„Proč rovnou pouštíš autotesty? To máš dělat, až napíšu push.“*). **Ani nově
   napsané nebo upravené testy se předem „pro jistotu“ nespouští** — stačí je zkompilovat, případné chyby v nich se opraví
   až po běhu u push (pokyn uživatele 2026-10-06: *„Chyby v testech se prostě opraví až na konci.“*).
   **Oprava spadlého testu, která sahá jen na test, se po pushi ověří jen tím testem** — `Test-Repo.ps1 … -TestCodeunit <id>
   -TestFunction <název>`, ne znovu celé repo (pokyn uživatele 2026-11-12, cust-alumistr-bc 67834: *„stačilo pustit jen ten
   jeden test“*; zbytek repa prošel v běhu, kde test spadl, a kód se nezměnil).

Nikdy `rebase` místo merge bez pokynu (přepisuje historii větve, kterou může mít kolega stažen) a nikdy `--force`.
Case-only kolize složek po merge zkontroluj `git ls-tree -r HEAD --name-only | sort -f | uniq -di` (7.10).

### 7.8 Verzování `app.json` — nepovyšovat sám

`version` v `app.json` (ani jinou formu verzování extension) **neměnit z
vlastní iniciativy** — verze je součást release procesu, který si řídí
uživatel ručně podle vlastní konvence (kdy se major povyšuje).

- **Pro PR** musí být verze ve tvaru **`XX.0.0.0`** (jen major, zbytek nuly —
  např. `27.0.0.0`). Mezilehlé tvary (`27.0.5.1`) můžou být přechodné během
  vývoje, ale do PR je uživatel sám sníží na `XX.0.0.0`.
- **Lokální zvýšení verze (`28.0.0.1`) je jen pro nahrávání do databáze — nikdy ho necommituj.** `app.json` patří do
  commitu, jen když se mění **závislosti** nebo **`idRanges`** (případně jiné skutečné nastavení); v tom případě stage
  s verzí `XX.0.0.0`, lokální vývojovou verzi uživateli nech v pracovním stromu. Samotná změna verze = `app.json`
  necommitovat vůbec. V masteru je vždy major verze, build verzi dává pipeline. (DNEM, 2026-10-14,
  prod-ess-dotykackaConnector-bc.)
- **Ruční / dev buildy pro nahrání: poslední část verze zvyšuj vždy jen o 1; nikdy do ní nedávej číslo PBI/tasku.**
  Např. `28.0.55.7` → `28.0.55.8`, nikoliv `28.0.55.65437`. Před sestavením ověř nejvyšší verzi, která už byla
  v cílovém prostředí použita (i dříve nainstalovanou); nová musí být vyšší. Pokud tam historicky je revize `67394`,
  pokračuj `67395`, ne `8` — části verze jsou celá čísla a BC downgrade odmítne. Číslo PBI patří do názvu větve,
  dokumentace nebo popisu buildu, ne do verze appky. Verzi měň jen v kopii projektu pro sestavení (viz výše),
  pokud uživatel výslovně nechce jinak. Pokyn DNEM 2026-11-04 po nasazování Alumistr TNG 67244 na BC-TEST2.
- Když uživatel **výslovně** řekne „povyš verzi na X" → uděláš.
- V dokumentačních MD (sekce 8) **nezmiňuj aktuální verzi** extension jako
  součást scope ticketu — verze se mění nezávisle.
- Při code review neobvyklý tvar verze (`27.0.5.1`) jen **zmiň**, neřeš za
  uživatele.

**Proč:** Automatický bump rozhodí release workflow / PR validaci. Verzování
je rozhodnutí uživatele, ne moje (stejná logika jako git commit/push/PR — 7.7).

### 7.9 Azure DevOps MCP — tickety, PRs, pipelines

Tickety a repa Essence BC projektů (Zlomek, Kalas, JIRI, produktové appky…)
žijí v Azure DevOps org **`essencebs`**, projekt **`Projects`**. Work item URL:
`https://dev.azure.com/essencebs/Projects/_workitems/edit/<ID>`.

Když uživatel zmíní číslo ticketu („task 64359", „bug 62667") nebo pošle
`dev.azure.com/essencebs/...` URL, sáhni po MCP serveru **`azure-devops`**
(`@azure-devops/mcp` spouštěný launcherem `MCP_PAT\ado-mcp.mjs`, globálně v `~/.claude.json`,
PAT auth, loaduje se sám):

- `wit_work_item` — `action: get` (`id`, `expand: All` přitáhne relations = parent / child
  tasky), `get_batch`, `list_comments`, `my` (moje tickety)
- `wit_work_item_attachment` (`attachmentId` = GUID z URL obrázku v popisu / Acceptance Criteria,
  `…/_apis/wit/attachments/<GUID>?fileName=…`) — screenshoty ze zadání; obrázek přijde inline,
  hláška „OUTPUT TRUNCATED" pod ním je jen o base64 textu, obrázek je vidět
- `search_workitem` (fulltext)
- `wit_work_item_write`, `wit_work_item_comment_write`, `wit_work_item_link_write`,
  `repo_pull_request_write` (zápisové — s read-only PAT vrátí 401, viz ⚠️ níže)
- `repo_*`, `pipelines_*`, `wiki_*`, `core_*` — PRs, buildy, wiki, identity

**Vazba na repo:** Ticket většinou neuvádí, do kterého repa patří — odvoď z
**CWD** (`cust-zlomek-bc` = Zlomek, `prod-epb-pricingMatrix-bc` = produktová
Pricing Matrix…), z Area Path a Iteration Path.

**PAT:** surový token v `<MCP_PAT>\DevOpsPAT.txt` (typicky `<složka pracovních rep>\MCP_PAT`,
mimo git), **v žádném konfigu není**. Launcher `ado-mcp.mjs` vedle něj (šablona `setup/ado-mcp.mjs`
v notes repu) ho při startu MCP serveru = startu seance přečte, zakóduje jako base64(`:PAT`) do
`PERSONAL_ACCESS_TOKEN`, nastaví výchozí projekt `ado_mcp_project=Projects` (tooly bez `project`
se pak neptají na výběr) a spustí `@azure-devops/mcp essencebs --authentication pat`; token pak
drží běžící proces, agent ho nikdy nevidí. Stejný launcher volají Claude Code, Codex, Copilot
i Antigravity (jeden soubor pro všechny). Scope záměrně jen **Read** (viz ⚠️ níže), expiruje
~90 dní (firemní policy). Po expiraci vygeneruj nový na
`https://dev.azure.com/essencebs/_usersSettings/tokens`, **přepiš `DevOpsPAT.txt`** a restartuj
seanci (`/mcp` → reconnect stačí taky); konfigy se nemění. Nastavení od nuly: `SETUP.md` /
`mcp-setup.md` krok 3 v kořeni notes repa. (2026-10-05; dřív base64 `email:PAT` přímo
v `env` `.claude.json`.)

**⚠️ PAT je read-only ZÁMĚRNĚ — 401 na zápisy NEobcházet:** MCP PAT má jen Read scopes **schválně** — Pull Requesty (a další zápisy do ADO) si uživatel dělá **sám**. Když `repo_create_pull_request` / `wit_link_work_item_to_pull_request` vrátí 401, **není to chyba k opravě** — je to záměrná zábrana. **Nikdy** neobcházet jiným credentialem (token z Git Credential Manageru přes `git credential fill`, az CLI, cokoliv jiného) — přesně to se stalo 2026-07-07 (PR 9096, prod-epb-pricingMatrix-bc) a uživatel to výslovně zakázal. Správný postup: připravit větev (merge, resoluce, push pokud je vyžádán), předat uživateli shrnutí + navrhovaný title/description PR a **nechat založení PR na něm**. Platí i když uživatel řekne „potřebuju udělat PR" — tím myslí, že ho udělá on, ne já.

**Texty do ADO (popis PR, Description / Acceptance Criteria PBI a Tasků, komentáře) posílej VŽDY jako Markdown
v bloku ` ```markdown `, bez ručního zalamování.** Pokyn uživatele 2026-10-14 (cust-zlomek-bc PR 66711): text zalomený
na šířku (120 znaků) se po zkopírování z terminálu rozpadne na řádky v půlce věty a vykreslený Markdown v terminálu
přijde o formátování. Proto:

- celý text do jednoho ` ```markdown ` bloku – terminál ho nevykreslí a zkopíruje se syrový Markdown, který ADO
  v popisu PR i ve work itemu vykreslí,
- každý odstavec a každý bod na **jednom řádku**, žádné zalomení uvnitř věty,
- struktura Markdownem: `###` nadpisy sekcí, `-` body, `**tučně**` jen podstatné (příčina, „do té doby nemergovat“),
  identifikátory objektů, polí a procedur v backtickách, captiony z UI kurzívou,
- název PR zvlášť v jednořádkovém bloku, work itemy (`#66711`) pod blokem,
- **popis PR max 4000 znaků** (limit popisu PR v ADO) – cíl do ~3000, před předáním spočítej (`len()` v pythonu) a
  počet uveď; tabulky testů, rozhodnutí a review patří do dokumentace MD, v PR jen odkaz. Uživatel to opakoval
  víckrát, naposledy 2026-11-20 (cust-zlomek-bc PR 66431, návrh přes limit).

Platí pro všechno, co uživatel do ADO vkládá ručně (PR, PBI, Task, Bug, komentáře work itemů i PR threadů).

- **`search_code` vrací multi-MB blob (5–6 MB i pro 14 hitů)** — výsledek se uloží do souboru a
  Read ho nepřečte. Repo + cestu vytáhni pythonem regexem (`"path":"..."`, `"repository":{"name"`),
  pak soubor stáhni `repo_file get_content`. Hledá jen indexovaná repa — když CUEBS/… objekt
  nenajde, ověř `repo_repository list` s `repoNameFilter`. (2026-09-01)
- **Přejmenované repo → `TF401019 … does not exist` / `repository … not found` při fetch.** Repa se v ADO
  přejmenovávají (např. `prod-ef-documentAttachments-bc` → `prod-ess-documentAttachments-bc`). Nové jméno najdi
  přes `repo_repository list` s `repoNameFilter` (kus jména, který zůstal), pak `git remote set-url origin <nová URL>`
  a `git fetch`; že je to totéž repo, ověř `git merge-base --is-ancestor <starší sha z lokálního masteru> origin/master`.
  Tracking větví funguje dál (jméno remotu se nemění). Spolu s repem se často přejmenovává i `*.code-workspace` na
  masteru → lokálně upravený starý workspace soubor zablokuje merge masteru (7.7b, nestashovat). Lokální složka
  může nést staré jméno, gitu to nevadí. (prod-ess-documentAttachments-bc, 2026-11-24)

**Gotcha — IPv6 reset (ECONNRESET):** Některé MS endpointy (`aex.dev.azure.com`)
resolvují primárně na IPv6 a corp síť/firewall jejich spojení **resetuje**
(`fetch failed` / „Failed to fetch tenant for ADO org essencebs"). IPv4 přes
stejný host funguje. Fix: u `azure-devops` to řeší launcher (`dns.setDefaultResultOrder('ipv4first')`,
u npx fallbacku `NODE_OPTIONS`); u jiných Node/npm MCP serverů volajících MS API (Graph, M365…)
`NODE_OPTIONS=--dns-result-order=ipv4first` v `env` sekci toho serveru v `.claude.json` (ne globálně).

### 7.10 Case-only rename složky appky = časovaná bomba na Windows build agentech

Git je case-sensitive, NTFS ne. Když jedna větev drží složku `configuratorExtension`
a druhá `ConfiguratorExtension` (case-only rozdíl), **merge commit může obsahovat
OBĚ cesty najednou** (git je bere jako nezávislé adds → žádný konflikt). Na
Windows build agentovi se pak při checkoutu obě složky **sesypou do jedné** —
soubory se stejnou relativní cestou přepíší (přežije jeden `app.json`, druhý
zmizí), soubory unikátní pro každou stranu se smíchají dohromady.

**Příznaky v Essence buildu:** `Sort-AppFoldersByDependencies` na začátku
Compile AL Apps hlásí `WARNING: Dependency <guid>:<publisher>_<name>_<ver>.app
not found` pro appku, která "v repu je" — a když na ní závisí jiná appka
(testovací), kompilace spadne na `Error downloading symbols ... 404 (Not Found)`
(symboly nejsou v NuGetu, v containeru, ani se nekompilují ze zdrojáků, protože
její `app.json` checkout přepsal).

**Detekce case-only duplicit ve stromu** (spustit před pushem po mergi):

```bash
git ls-tree -r HEAD --name-only | sort -f | uniq -di
```

Prázdný výstup = OK. **Fix:** nikdy nedělat case-only rename složky; převzít
casing masteru. Na Windows (case-insensitive checkout) rename dvoukrokově:
`git mv SlozkaX tmp && git mv tmp slozkaX`. Zachyceno: cust-alumistr-bc PR 8756
(build 27263, 2026-07-08) — merge obsahoval `configuratorExtension` (master) i
`ConfiguratorExtension` (větev) současně.
