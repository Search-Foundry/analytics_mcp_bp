# analytics-mcp-blueprint

English: [README.md](README.md)

Un repo-template per un hub locale e multi-tenant di analisi: GA4 e Google Search
Console, guidati da [Claude Code](https://claude.com/claude-code) tramite due server MCP
(`analytics-mcp` e `search-console-mcp`). Clonalo, esegui lo script di setup e inizia a
chiedere a Claude del traffico organico dei tuoi siti.

Questo è un **blueprint da clonare**, non una libreria da installare. Fai fork o
`git clone`, personalizzalo e tieni i dati dei tuoi tenant nella tua copia — niente qui
parla con un backend condiviso.

## Cosa serve

- Un account Google con accesso a GA4 e Search Console (basta Viewer) sui siti da
  analizzare.
- Un progetto Google Cloud sotto il tuo controllo, per ospitare un client OAuth e
  abilitare tre API.
- [Node.js 22+](https://nodejs.org) e [gcloud](https://cloud.google.com/sdk/docs/install).

## Quickstart

```
git clone https://github.com/<tu>/analytics-mcp-blueprint.git my-hub
cd my-hub
cp CLAUDE.md.template CLAUDE.md
./scripts/setup.sh
# incolla il blocco di configurazione MCP stampato in ~/.claude.json, poi in Claude Code: /mcp
./scripts/new-tenant.sh acme --account me@example.com --ga4 <id> --gsc <url>
```

`setup.sh` guida interattivamente il resto: verifica dei prerequisiti, creazione di
`.env`, abilitazione delle API Google Cloud, generazione delle credenziali, e stampa del
blocco di configurazione MCP da incollare in `~/.claude.json`.

## La gerarchia `accounts/<email>/<tenant>/`

Le credenziali sono per account Google, e lo stesso nome di tenant può legittimamente
esistere sotto due account diversi — quindi i tenant vivono annidati sotto l'account con
cui vengono acceduti, non in un'unica cartella piatta `tenants/`. Ogni cartella
`accounts/<email>/` ha il proprio `CLAUDE.md` con la tabella dei tenant di quell'account;
il `CLAUDE.md` dell'hub (da `CLAUDE.md.template`) elenca gli account, non i tenant.
Dettagli: `docs/04-multi-tenant.md`.

## Il costo operativo quotidiano: re-login ogni ~24h

gcloud impone lo scope `cloud-platform`, che attiva la policy RAPT di Google: circa ogni
24 ore entrambi i server MCP iniziano a rispondere con `invalid_rapt`, `invalid_grant`,
`reauthentication needed` o `401`, e il rimedio è eseguire `./scripts/reconnect.sh`
(apre un browser — un passo che solo tu puoi fare) e poi `/mcp` in Claude Code. È un
comportamento atteso, non un bug. Spiegazione completa: `docs/03-auth-and-rapt.md`.

## Documentazione

- `docs/01-google-cloud-setup.md` — creazione del progetto Google Cloud, API, client OAuth.
- `docs/02-mcp-servers.md` — installazione e configurazione di entrambi i server MCP.
- `docs/03-auth-and-rapt.md` — ADC condiviso, i tre scope, RAPT, setup multi-account.
- `docs/04-multi-tenant.md` — la struttura `accounts/<email>/<tenant>/` in dettaglio.
- `docs/05-usage.md` — la superficie degli strumenti MCP: i 7 tool fluenti di GSC, i campi
  dei report GA4.
- `docs/06-bing-future.md` — la superficie Bing Webmaster Tools inclusa, fuori scope per ora.
- `docs/07-windows.md` — usare WSL oggi, cosa servirebbe per un port nativo.
- `docs/99-troubleshooting.md` — una sezione per ogni check di `doctor.sh`.

## Contribuire

Esegui la suite di test prima di aprire una PR:

```
bash tests/run.sh
```

Non ha dipendenze esterne — semplici assert in Bash, nessun framework da installare. Gli
script sono Bash pensati per la portabilità (vedi i vincoli in `docs/07-windows.md`):
niente `sed -i ''`, `realpath`, `readlink -f`, `jq`, né `eval`.

## Licenza

MIT — vedi `LICENSE`.
