# Deployment on a Shiny server (no RStudio)

How to publish the app on **Shiny Server** (open source, Posit) on a Debian/Ubuntu Linux server.
Everything is done from a terminal (SSH); RStudio is not needed.
When finished, both versions are available at:

- `http://SERVER:3838/iohexol/it/` – Italian version
- `http://SERVER:3838/iohexol/en/` – English version

> **Patient data.** The app handles personal health data (name, date of birth, lab results).
> Open-source Shiny Server **has no authentication**: publish it only on an internal network/VPN
> or behind a reverse proxy with HTTPS and access control (see step 8), in compliance with GDPR
> and your institution's rules. The app writes nothing permanent to disk: data live in the browser
> session and the report is built in a temporary folder.

## 1. R and pandoc

```bash
sudo apt update
sudo apt install -y r-base pandoc git
```

R ≥ 4.1 is required. For a newer R than the distribution's, follow
https://cran.r-project.org/bin/linux/ubuntu/ (or `.../debian/`).
**pandoc is mandatory** to generate the HTML report (rmarkdown looks for it on the `PATH`;
with `apt` it is installed as `/usr/bin/pandoc`).

## 2. R packages (system library)

Install them as root so that the `shiny` user running the server can see them.
After cloning the repository (step 4) you can use the bundled script:

```bash
sudo Rscript /opt/iohexol_calc/deploy/install_packages.R
```

or directly:

```bash
sudo Rscript -e 'install.packages(c("shiny", "bslib", "rmarkdown", "knitr"), lib = .Library.site[1], repos = "https://cloud.r-project.org")'
```

## 3. Shiny Server

Download the latest `.deb` package for your distribution from
https://posit.co/download/shiny-server/ and install it, for example:

```bash
sudo apt install -y gdebi-core
```

```bash
wget https://download3.rstudio.org/ubuntu-20.04/x86_64/shiny-server-<VERSION>-amd64.deb
```

```bash
sudo gdebi shiny-server-<VERSION>-amd64.deb
```

(replace `<VERSION>` with the one shown on the download page). The service starts automatically
on port 3838: `sudo systemctl status shiny-server`.

## 4. Copy the app to the server

```bash
sudo git clone https://github.com/davidenegrini/iohexol_calc.git /opt/iohexol_calc
```

(if the repository is private, clone it with your credentials, or copy the folder with
`scp -r` / `rsync`). The two apps are the `it/` and `en/` subfolders: each has its own `app.R`.

The `shiny` user must be able to read the files:

```bash
sudo chown -R shiny:shiny /opt/iohexol_calc
```

## 5. Shiny Server configuration

Install the example configuration (publishes only the two apps, under `/iohexol/it/` and
`/iohexol/en/`; the other files of the repository are not exposed):

```bash
sudo cp /etc/shiny-server/shiny-server.conf /etc/shiny-server/shiny-server.conf.orig
```

```bash
sudo cp /opt/iohexol_calc/deploy/shiny-server.conf /etc/shiny-server/shiny-server.conf
```

If other apps are already published on the server, do not replace the file: just add the two
`location /iohexol/it { ... }` and `location /iohexol/en { ... }` blocks inside the existing `server` block.
Do not clone the repository inside `/srv/shiny-server/`: with the default configuration `README`,
`tests/` and the `.git` folder would also be served as static files.

## 6. UTF-8 locale (recommended)

The app already copes with a non-UTF-8 locale (it switches to `C.UTF-8` by itself), but it is
good practice to set it for the service as well:

```bash
sudo systemctl edit shiny-server
```

and add:

```ini
[Service]
Environment="LANG=C.UTF-8"
```

## 7. Start and check

```bash
sudo systemctl restart shiny-server
```

Open `http://SERVER:3838/iohexol/en/`, fill in a test case and download the HTML report.
If something fails, check the logs (one file per app start):

```bash
sudo ls -lt /var/log/shiny-server/ | head
```

Typical errors:
- *"pandoc version 1.12.3 or higher is required"* → pandoc not installed (step 1);
- *"there is no package called 'bslib'"* → packages installed only in a personal library (step 2);
- page greys out / disconnects behind a proxy → WebSocket support missing (step 8).

Before publishing you can run the tests (formulas, Italian/English consistency, app start-up and
report generation):

```bash
cd /opt/iohexol_calc && Rscript tests/test_formule.R
```

## 8. HTTPS and access control (nginx reverse proxy, recommended)

Example nginx block exposing the apps over HTTPS with basic authentication; then close port 3838
to the outside (firewall). Shiny uses WebSockets: the `Upgrade`/`Connection` lines are required.

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
  listen 443 ssl;
  server_name mgfr.example.org;
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

To restrict Shiny Server to localhost, use `listen 3838 127.0.0.1;` in its configuration file.

## 9. Updates

```bash
cd /opt/iohexol_calc && sudo -u shiny git pull
```

```bash
sudo -u shiny touch /opt/iohexol_calc/it/restart.txt /opt/iohexol_calc/en/restart.txt
```

`restart.txt` makes the apps restart at the next session (or run `sudo systemctl restart shiny-server`).

## Alternatives

- **Posit Connect** (commercial, with authentication) or **shinyapps.io** (cloud): from a terminal,
  without RStudio, with the `rsconnect` package:
  `Rscript -e 'rsconnect::deployApp("en", appName = "mgfr-iohexol-en")'` (after configuring the
  account with `rsconnect::setAccountInfo()`). Note: shinyapps.io is an external cloud service;
  assess whether it is suitable for health data.
- **Plain R, no Shiny Server** (e.g. a quick test on a PC in the network):
  `Rscript -e 'shiny::runApp("en", host = "0.0.0.0", port = 3838)'`.
