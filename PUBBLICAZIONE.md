# Pubblicazione su un server Shiny (senza RStudio)

Istruzioni per pubblicare l'app su **Shiny Server** (open source, Posit) installato su un server
Linux Debian/Ubuntu. Tutto si fa da terminale (SSH); RStudio non serve.
Al termine le due versioni saranno raggiungibili a:

- `http://SERVER:3838/iohexol/it/` – versione italiana
- `http://SERVER:3838/iohexol/en/` – versione inglese

> **Dati dei pazienti.** L'app tratta dati personali e sanitari (nome, data di nascita, esami).
> Shiny Server open source **non ha autenticazione**: pubblicarla solo su rete interna/VPN oppure
> dietro un reverse proxy con HTTPS e accesso controllato (vedi punto 8), nel rispetto del GDPR
> e delle regole dell'azienda sanitaria. L'app non salva nulla su disco: i dati restano nella
> sessione del browser e il report viene creato in una cartella temporanea.

## 1. R e pandoc

```bash
sudo apt update
sudo apt install -y r-base pandoc git
```

Serve R ≥ 4.1. Per una versione di R più recente di quella della distribuzione seguire
https://cran.r-project.org/bin/linux/ubuntu/ (o `.../debian/`).
**pandoc è indispensabile** per generare il report HTML (rmarkdown lo cerca nel `PATH`; con
`apt` finisce in `/usr/bin/pandoc`).

## 2. Pacchetti R (nella libreria di sistema)

Vanno installati da root, così li vede anche l'utente `shiny` con cui gira il server.
Dopo aver clonato il repository (punto 4) si può usare lo script incluso:

```bash
sudo Rscript /opt/iohexol_calc/deploy/install_packages.R
```

oppure direttamente:

```bash
sudo Rscript -e 'install.packages(c("shiny", "bslib", "rmarkdown", "knitr"), lib = .Library.site[1], repos = "https://cloud.r-project.org")'
```

## 3. Shiny Server

Scaricare il pacchetto `.deb` più recente per la propria distribuzione da
https://posit.co/download/shiny-server/ e installarlo, ad esempio:

```bash
sudo apt install -y gdebi-core
```

```bash
wget https://download3.rstudio.org/ubuntu-20.04/x86_64/shiny-server-<VERSIONE>-amd64.deb
```

```bash
sudo gdebi shiny-server-<VERSIONE>-amd64.deb
```

(sostituire `<VERSIONE>` con quella indicata nella pagina di download). Il servizio parte da solo
sulla porta 3838: `sudo systemctl status shiny-server`.

## 4. Copia dell'app sul server

```bash
sudo git clone https://github.com/davidenegrini/iohexol_calc.git /opt/iohexol_calc
```

(se il repository è privato: clonarlo con le proprie credenziali, oppure copiare la cartella con
`scp -r` / `rsync`). Le due app sono le sottocartelle `it/` ed `en/`: ciascuna contiene il proprio `app.R`.

L'utente `shiny` deve poter leggere i file:

```bash
sudo chown -R shiny:shiny /opt/iohexol_calc
```

## 5. Configurazione di Shiny Server

Copiare la configurazione di esempio (pubblica solo le due app, sotto `/iohexol/it/` e `/iohexol/en/`;
gli altri file del repository non vengono esposti):

```bash
sudo cp /etc/shiny-server/shiny-server.conf /etc/shiny-server/shiny-server.conf.orig
```

```bash
sudo cp /opt/iohexol_calc/deploy/shiny-server.conf /etc/shiny-server/shiny-server.conf
```

Se sul server sono già pubblicate altre app, invece di sostituire il file aggiungere solo i due
blocchi `location /iohexol/it { ... }` e `location /iohexol/en { ... }` dentro il blocco `server` esistente.
Non clonare il repository dentro `/srv/shiny-server/`: con la configurazione predefinita verrebbero
serviti come file statici anche `README`, `tests/` e la cartella `.git`.

## 6. Locale UTF-8 (consigliato)

L'app è già robusta a una locale non UTF-8 (passa da sola a `C.UTF-8`), ma è bene impostarla
anche per il servizio:

```bash
sudo systemctl edit shiny-server
```

e inserire:

```ini
[Service]
Environment="LANG=C.UTF-8"
```

## 7. Avvio e verifica

```bash
sudo systemctl restart shiny-server
```

Aprire `http://SERVER:3838/iohexol/it/`, compilare un caso di prova e scaricare il report HTML.
In caso di errori controllare i log (un file per ogni avvio dell'app):

```bash
sudo ls -lt /var/log/shiny-server/ | head
```

Errori tipici:
- *"pandoc version 1.12.3 or higher is required"* → pandoc non installato (punto 1);
- *"there is no package called 'bslib'"* → pacchetti installati solo nella libreria personale (punto 2);
- pagina che resta grigia / si disconnette dietro un proxy → manca il supporto WebSocket (punto 8).

Prima della pubblicazione si possono eseguire i test (formule, coerenza italiano/inglese, avvio
delle app e creazione del report):

```bash
cd /opt/iohexol_calc && Rscript tests/test_formule.R
```

## 8. HTTPS e accesso (reverse proxy nginx, consigliato)

Esempio di blocco nginx che espone le app in HTTPS con autenticazione di base; la porta 3838
va poi chiusa verso l'esterno (firewall). Shiny usa i WebSocket: le righe `Upgrade`/`Connection`
sono necessarie.

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
  listen 443 ssl;
  server_name mgfr.esempio.it;
  ssl_certificate     /etc/ssl/certs/mgfr.crt;
  ssl_certificate_key /etc/ssl/private/mgfr.key;

  location /iohexol/ {
    auth_basic           "mGFR";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass         http://127.0.0.1:3838/iohexol/;
    proxy_http_version 1.1;
    proxy_set_header   Upgrade $http_upgrade;
    proxy_set_header   Connection $connection_upgrade;
    proxy_read_timeout 600s;
  }
}
```

Per limitare Shiny Server al solo localhost, nel file di configurazione usare `listen 3838 127.0.0.1;`.

## 9. Aggiornamenti

```bash
cd /opt/iohexol_calc && sudo -u shiny git pull
```

```bash
sudo -u shiny touch /opt/iohexol_calc/it/restart.txt /opt/iohexol_calc/en/restart.txt
```

Il file `restart.txt` fa ripartire le app alla sessione successiva (in alternativa
`sudo systemctl restart shiny-server`).

## Alternative

- **Posit Connect** (commerciale, con autenticazione) o **shinyapps.io** (cloud): da terminale,
  senza RStudio, con il pacchetto `rsconnect`:
  `Rscript -e 'rsconnect::deployApp("it", appName = "mgfr-ioexolo-it")'` (dopo aver configurato
  l'account con `rsconnect::setAccountInfo()`). Attenzione: shinyapps.io è un servizio cloud
  esterno, valutare l'idoneità per dati sanitari.
- **Solo R, senza Shiny Server** (es. per una prova su un PC della rete):
  `Rscript -e 'shiny::runApp("it", host = "0.0.0.0", port = 3838)'`.
