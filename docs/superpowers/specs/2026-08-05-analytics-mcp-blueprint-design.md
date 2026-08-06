# analytics-mcp-blueprint — design

Data: 2026-08-05
Stato: approvato (design), da implementare

## 1. Obiettivo

Un repository open source che permetta a chiunque abbia (a) un account Google con accessi
GA4 e Google Search Console e (b) un progetto Google Cloud, di costruirsi un **hub locale
multi-tenant** per analisi SEO/traffico guidate da Claude Code, tramite i server MCP
`analytics-mcp` (GA4) e `search-console-mcp` (GSC).

Il repo è un **blueprint**: si clona, si personalizza, e da quel momento è la propria cartella
di lavoro. Non è una libreria né un pacchetto da installare.

Origine: generalizzazione dell'hub privato `~/code/analyticsmcp`, ripulito da dati e
identificativi dei clienti.

## 2. Non-obiettivi

- Non automatizza i passaggi che richiedono la console web di Google Cloud (creazione OAuth
  client, consent screen): li guida.
- Non scrive automaticamente `~/.claude.json`: stampa il blocco da incollare.
- Non include dati, property ID, client ID o siti reali.
- Non supporta (per ora) Bing Webmaster Tools: annotato come espansione futura.
- Non fornisce una libreria di playbook completa: fornisce l'albero e una ricetta d'esempio.

## 3. Decisioni prese

| Tema | Decisione |
|---|---|
| Automazione | Documentazione + script bash guidati e ispezionabili. Nessun wizard monolitico. |
| Lingua | Bilingue: `README.md` (EN) + `README.it.md` (IT). Docs in EN con controparte IT dove il valore lo giustifica. |
| Credenziali | Default: ADC singolo condiviso (OAuth utente, 3 scope). Opzionale documentato: profili ADC per account. |
| Contenuti extra | Template tenant, troubleshooting completo, skill Claude Code, albero playbook con 1 entry. |
| Bing | Espansione futura, documentata in una sezione dedicata. |
| Pubblicazione | Repo locale in `~/code/analytics-mcp-blueprint`. Nessuna creazione su GitHub in questa fase. |
| Portabilità | Script bash primari (macOS/Linux), scritti per essere **convertibili a PowerShell** senza riprogettare nulla. Vedi §13. |

## 3bis. Stato upstream verificato (2026-08-05)

| Componente | Fonte | Versione |
|---|---|---|
| `search-console-mcp` | npm / [saurabhsharma2u/search-console-mcp](https://github.com/saurabhsharma2u/search-console-mcp) | **2.0.1** (2026-08-03) |
| `analytics-mcp` | PyPI / [googleanalytics/google-analytics-mcp](https://github.com/googleanalytics/google-analytics-mcp) | **0.7.0** |

Conseguenze per il blueprint:

1. **`re2` non è più una dipendenza.** PR #81 mergiata, issue #80 chiusa. Il build locale del fork
   re2-free **non fa più parte del setup**: `npx -y search-console-mcp` è il percorso normale.
   Il fallback locale resta documentato solo in `99-troubleshooting.md`, come rimedio storico.
2. **Nuova dipendenza nativa `@napi-rs/keyring`** (più `node-machine-id`): il server usa il
   portachiavi di sistema. Prebuild ampi, ma è il nuovo candidato n.1 a rompersi su Node
   inusuali; `doctor.sh` deve intercettarlo. Va inoltre chiarito in `03-auth-and-rapt.md` il
   rapporto fra portachiavi e ADC, perché tocca la storia credenziali del blueprint.
3. **v2.0.0 ha consolidato ~96 tool in 7 "fluent domain tools"**
   (`sites_list`, `analytics_query`, `seo_audit`, `indexing_submit`, `inspection_inspect`,
   `sitemaps_list`, `site_health_check`), con backward compatibility dichiarata per i legacy.
   `05-usage.md` documenta **v2**, con una nota sui nomi legacy.
4. **Bing è supportato upstream** via `BING_API_KEY`. Resta fuori scope, ma `06-bing-future.md`
   si riduce a una nota di attivazione anziché a un progetto di integrazione.
5. **v2 offre transport HTTP/SSE** oltre a stdio. Il blueprint usa stdio; l'alternativa è
   menzionata in `02-mcp-servers.md`.

## 4. Struttura del repository

```
analytics-mcp-blueprint/
├── README.md                     # quickstart EN
├── README.it.md                  # quickstart IT
├── CLAUDE.md.template            # CLAUDE.md dell'hub, tabella tenant vuota
├── .env.example
├── .gitignore
├── LICENSE                       # MIT
├── docs/
│   ├── 01-google-cloud-setup.md
│   ├── 02-mcp-servers.md
│   ├── 03-auth-and-rapt.md
│   ├── 04-multi-tenant.md
│   ├── 05-usage.md
│   ├── 06-bing-future.md
│   └── 99-troubleshooting.md
├── scripts/
│   ├── setup.sh
│   ├── reconnect.sh
│   ├── doctor.sh
│   └── new-tenant.sh
├── templates/
│   └── tenant/
│       ├── CLAUDE.md
│       ├── README.md
│       ├── data/.gitkeep
│       ├── exports/.gitkeep
│       └── analysis/.gitkeep
├── playbooks/
│   ├── README.md                 # come si scrive un playbook, come estendere l'albero
│   └── organic-traffic-drop.md   # ricetta d'esempio
└── .claude/
    └── skills/
        ├── new-tenant/SKILL.md
        ├── reconnect/SKILL.md
        └── health-check/SKILL.md
```

**Principio vincolante:** nessun path assoluto hardcodato. Tutta la configurazione locale passa
da `.env` (non committato), letto dagli script.

## 5. Configurazione (`.env`)

| Variabile | Descrizione |
|---|---|
| `GCP_PROJECT_ID` | Progetto Google Cloud che ospita l'OAuth client e le API abilitate. |
| `GOOGLE_ACCOUNT` | Account Google atteso al login (check di coerenza, non enforcement). |
| `OAUTH_CLIENT_FILE` | Path al JSON dell'OAuth client desktop. Default `.secrets/oauth-client.json`. |
| `ADC_FILE` | Path del file ADC in uso. Default `~/.config/gcloud/application_default_credentials.json`; con un account named, `.secrets/gcloud/<email>/application_default_credentials.json`. |
| `GSC_MCP_MODE` | `npx` (default) oppure `local` (build da sorgenti, solo come rimedio). Impostato da `setup.sh`. |
| `GSC_MCP_PATH` | Path a `dist/index.js` quando `GSC_MCP_MODE=local`. |

## 6. Modello credenziali

### Default: ADC singolo

OAuth utente (non service account) con scope:
`analytics.readonly`, `webmasters.readonly`, `cloud-platform`.

Entrambi i server MCP leggono lo stesso file ADC. Le librerie Google Auth lo trovano per
convenzione nel path di default anche senza `GOOGLE_APPLICATION_CREDENTIALS`, ma la config MCP
lo dichiara esplicitamente.

`cloud-platform` è imposto da `gcloud` e non è rimovibile. È lo scope che attiva la policy
**RAPT** di Google, che impone un re-login periodico (~24h). Non è un bug e non ha workaround
via gcloud: il blueprint lo documenta come costo operativo noto e fornisce `reconnect.sh`.

Sintomi di scadenza: `invalid_rapt`, `invalid_grant`, `reauthentication needed`, `401`.

### Multi-account: un albero per account Google

Revisione del 2026-08-05, decisa in corso d'implementazione dopo che la review ha dimostrato che
il meccanismo previsto in origine non funzionava (vedi §15).

I tenant non stanno alla radice dell'hub: stanno **dentro la cartella del loro account Google**.

```
accounts/
└── me@example.com/          ← master folder di un account
    ├── CLAUDE.md            ← tabella dei tenant DI QUESTO ACCOUNT
    ├── acme/                ← tenant
    └── globex/              ← tenant
```

Le credenziali sono per account, non condivise: `reconnect.sh --account <email>` esegue il login
con `CLOUDSDK_CONFIG` puntato a `.secrets/gcloud/<email>/`, e l'ADC finisce quindi in
`.secrets/gcloud/<email>/application_default_credentials.json`. È il meccanismo che gcloud onora
davvero: `gcloud auth application-default login` scrive **sempre** nella posizione ADC derivata
dalla config dir, e ignora `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE`, che serve solo in lettura.

Senza `--account`, `reconnect.sh` usa la posizione ADC di default: è il percorso semplice per chi
ha un solo account, e resta il default.

**Conseguenza da documentare:** le env dei server MCP sono statiche, quindi **ogni account richiede
il proprio blocco** in `~/.claude.json` (es. `search-console-mcp-acme` accanto a
`search-console-mcp-globex`), ciascuno con il proprio `GOOGLE_APPLICATION_CREDENTIALS`. Non si
commuta un server fra account a runtime.

## 7. Script

Ogni script è POSIX-ish bash, `set -euo pipefail`, con `--help`, e fallisce con un messaggio
che dice cosa fare — mai in silenzio.

### `setup.sh`

Sequenza di check che si ferma e istruisce l'utente:

1. Prerequisiti: `gcloud`, `node >= 22`, `git`. Se mancano, istruzioni d'installazione.
2. `.env`: se assente, lo crea da `.env.example` chiedendo i valori.
3. Abilita sul progetto GCP: `analyticsadmin.googleapis.com`, `analyticsdata.googleapis.com`,
   `searchconsole.googleapis.com`.
4. Guida alla creazione dell'**OAuth client desktop** in console (passaggi manuali, con nota su
   consent screen: Internal evita la scadenza dei refresh token a 7 giorni tipica di External
   in testing).
5. Login ADC con i tre scope.
6. Installazione server GSC: `npx -y search-console-mcp` (v2.x, senza `re2`). Smoke test; se il
   server non parte per un modulo nativo mancante (oggi il candidato è `@napi-rs/keyring`), lo
   script si ferma e rimanda alla sezione corrispondente di `99-troubleshooting.md` — non tenta
   build automatici alle spalle dell'utente.
7. Stampa il blocco JSON `mcpServers` da incollare in `~/.claude.json`, con nota di backup.
8. Esegue `doctor.sh`.

### `reconnect.sh`

Rigenera l'ADC con gli scope corretti leggendo `.env`. Opzione `--profile <nome>`. Ricorda di
lanciare `/mcp` in Claude Code al termine.

### `doctor.sh`

Diagnostica non distruttiva:
- versioni `node` / `gcloud`;
- esistenza e validità del file ADC;
- scope effettivamente presenti nel token;
- smoke test del server GSC (attende `✔ Google` sullo stdio banner);
- API abilitate sul progetto GCP.

Output: righe `OK` / `WARN` / `FAIL` con rimando alla sezione di `99-troubleshooting.md`.

### `new-tenant.sh <nome>`

1. Copia `templates/tenant/` in `<nome>/`.
2. Chiede GA4 property ID e URL del sito GSC (entrambi opzionali, compilabili dopo).
3. Sostituisce i placeholder nel `CLAUDE.md` del tenant.
4. Aggiunge la riga corrispondente alla tabella tenant nel `CLAUDE.md` dell'hub.

## 8. Multi-tenant

Un tenant = una sottocartella **della cartella del suo account Google**
(`accounts/<email>/<tenant>/`). L'hub contiene solo strumenti, credenziali e runbook trasversali.

Ogni cartella account ha il proprio `CLAUDE.md` con la tabella dei tenant di quell'account
(nome, GA4 property ID, sito GSC, stato): è la mappa che Claude legge quando lavora lì.
Il `CLAUDE.md` dell'hub elenca gli account, non i tenant.

`.gitignore` esclude di default `*/data/`, `*/exports/`, `.secrets/`, `.env`, `gsc-mcp/` e
qualunque file ADC: i dati dei clienti non finiscono nel repo per errore.

## 9. Playbook

`playbooks/` è un albero pensato per essere esteso dall'utente. Contiene:

- `README.md`: cos'è un playbook, la struttura attesa (contesto → domande → query MCP →
  interpretazione → output), e come aggiungerne uno.
- `organic-traffic-drop.md`: una ricetta d'esempio completa — diagnosi di un calo di traffico
  organico, con separazione brand/non-brand, confronto periodi su GSC, incrocio con le landing
  page GA4, e le ipotesi da escludere in ordine (indicizzazione, crawl, stagionalità, bot).
  Nessun dato reale: solo placeholder e struttura del ragionamento.

## 10. Skill Claude Code

In `.claude/skills/`, tre skill sottili che chiamano gli script e ne interpretano l'output:

- `new-tenant` — crea e registra un nuovo tenant.
- `reconnect` — riconosce gli errori di auth e guida il rinnovo ADC + `/mcp`.
- `health-check` — lancia `doctor.sh` e traduce i FAIL in azioni.

## 11. Documentazione — contenuti chiave

`99-troubleshooting.md` copre i problemi già risolti nell'hub originale:
`re2` assente su Node ≥ 25, RAPT / `invalid_rapt`, scope mancanti nell'ADC, consent screen
Internal vs External, API GCP non abilitate, e le insidie d'uso dei tool.

`05-usage.md` copre le note operative dei server:
- GSC: parametro righe `limit` (non `rowLimit`), default 1000 / max 25.000; `dataState: "all"`
  per i dati preliminari; operatori di filtro; `format: "csv"`.
- GA4: campi in `snake_case` (`date_ranges`, `dimension_filter`, `string_filter`, `match_type`);
  dimensione `landingPage` per l'organico per pagina; filtri `PARTIAL_REGEXP`.

`06-bing-future.md` annota che il server GSC espone anche una superficie Bing Webmaster Tools,
non coperta dal blueprint: requisiti (API key Bing), e cosa servirebbe per integrarla.

## 12. Criteri di successo

Una persona esterna, partendo da zero su una macchina pulita con un account Google che ha
accessi GA4/GSC:

1. clona il repo, esegue `setup.sh` e arriva a `doctor.sh` tutto verde;
2. incolla il blocco MCP, riavvia Claude Code, e ottiene risposta da `sites_list` (GSC) e
   `get_account_summaries` (GA4);
3. crea un tenant con `new-tenant.sh` e lo vede comparire nel `CLAUDE.md` dell'hub;
4. quando l'auth scade il giorno dopo, riconosce il sintomo e lo risolve con `reconnect.sh`.

## 13. Portabilità Windows

Requisito: il progetto è pensato per agenti, ma **deve poter essere convertito per girare in
shell Windows (PowerShell)** senza riprogettarlo. La conversione non è nello scope della prima
implementazione; la *convertibilità* sì, ed è vincolante.

### Regole vincolanti sugli script bash

- Nessun costrutto specifico BSD/macOS: niente `sed -i ''`, `realpath`, `readlink -f`, `mktemp -t`,
  `grep -P`, `date -j`. Solo forme che esistono anche su GNU coreutils.
- Nessuna dipendenza da tool non garantiti (`jq`): il parsing JSON passa da `node -e`, che è già
  un prerequisito del progetto.
- Path sempre costruiti da variabili, mai concatenati a mano con `/` letterali nei punti che
  toccano il filesystem dell'utente.
- Ogni script ha un **contratto esplicito** documentato in testa: input (variabili `.env` lette),
  output (stdout strutturato), exit code (`0` OK, `1` errore utente, `2` prerequisito mancante).
  Il contratto è ciò che la porta PowerShell deve rispettare, non l'implementazione.
- La logica non banale (ordine dei check, messaggi, mapping errore → sezione di troubleshooting)
  vive in **dati**, non sparsa nel flusso di controllo, così la porta è meccanica.

### Differenze di piattaforma da documentare

`docs/07-windows.md` elenca i punti che una porta deve gestire: path dell'ADC su Windows
(`%APPDATA%\gcloud\application_default_credentials.json`), posizione di `~/.claude.json`,
`gcloud` come `gcloud.cmd`, il portachiavi usato da `@napi-rs/keyring` (Credential Manager),
e la nota che WSL è la via più semplice se non si vuole portare nulla.

### Fase 2 (non in questa implementazione)

`scripts/windows/*.ps1` come porte 1:1 dei contratti sopra. La struttura di cartelle le prevede
fin da ora, così l'aggiunta non muove nulla.

## 14. Rischi noti

- **Deriva upstream**: se la PR re2-free viene mergiata e pubblicata su npm, il fallback locale
  diventa inutile. `setup.sh` prova sempre `npx` per primo, quindi degrada correttamente da solo.
- **Manutenzione bilingue**: `README.it.md` può divergere. Mitigazione: il contenuto normativo
  vive nei `docs/` in EN; i README sono quickstart brevi.
- **Variabilità della console GCP**: le istruzioni con screenshot invecchiano. Mitigazione:
  descrizione testuale dei passaggi, senza screenshot.

## 15. Revisioni in corso d'implementazione

**2026-08-05 — `--profile` sostituito da `--account`, con gerarchia per account.**
La review del Task 4 ha rilevato due difetti Critical nel `reconnect.sh` prescritto dal piano:

1. Il comando veniva costruito per concatenazione ed eseguito con `eval`, senza quoting del valore
   di `--profile`: un argomento come `x"; touch /tmp/PWNED; echo "y` eseguiva il comando iniettato.
   Sostituito da un array bash eseguito direttamente — `eval` non serviva, il comando ha forma fissa.
2. `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` non fa ciò che il piano assumeva: indica a gcloud quale
   file di credenziali **leggere**, mentre `gcloud auth application-default login` scrive sempre
   nella posizione ADC standard. `--profile acme` avrebbe quindi promesso isolamento per-tenant
   scrivendo in silenzio sul file condiviso — il caso peggiore, perché nessuno se ne accorge finché
   non mescola i dati di due clienti.

La correzione adottata usa `CLOUDSDK_CONFIG` per account e riorganizza l'albero per account
(vedi §6). Il flag si chiama ora `--account <email>` perché è ciò che rappresenta.
