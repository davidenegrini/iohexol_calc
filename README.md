# iohexol_calc

Shiny app for measured GFR (mGFR) with iohexol (slope-intercept + Brøchner-Mortensen) and eGFR
(EKFC, CKD-EPI 2021), with a downloadable HTML report.
App Shiny per la misura del filtrato glomerulare (mGFR) con ioexolo ed eGFR, con report HTML.

| Cartella / Folder | Contenuto / Content |
|---|---|
| [`it/`](it/) | Versione italiana – vedi [`it/LEGGIMI.md`](it/LEGGIMI.md) |
| [`en/`](en/) | English version – see [`en/README.md`](en/README.md) |
| [`tests/`](tests/) | Test di formule e coerenza it/en – formula and it/en consistency tests |
| [`deploy/`](deploy/) | Configurazione Shiny Server e installazione pacchetti – Shiny Server config and package installer |

## Avvio rapido / Quick start

```bash
Rscript -e 'install.packages(c("shiny", "bslib", "rmarkdown", "knitr"))'
```

```bash
Rscript -e 'shiny::runApp("it", port = 3838, launch.browser = TRUE)'
```

```bash
Rscript -e 'shiny::runApp("en", port = 3838, launch.browser = TRUE)'
```

pandoc must be installed for the report (`sudo apt install pandoc`) – serve pandoc per il report.

## Pubblicazione / Deployment

- 🇮🇹 [PUBBLICAZIONE.md](PUBBLICAZIONE.md) – Shiny Server su Linux, senza RStudio
- 🇬🇧 [DEPLOYMENT.md](DEPLOYMENT.md) – Shiny Server on Linux, no RStudio

## Test

```bash
Rscript tests/test_formule.R
```
