# iohexol_calc

Shiny app for measured GFR (mGFR) with iohexol (slope-intercept + Brøchner-Mortensen) and eGFR
(EKFC, CKD-EPI 2021), with a downloadable HTML report.
App Shiny per la misura del filtrato glomerulare (mGFR) con ioexolo ed eGFR, con report HTML.

> **Avvertenza.** Strumento di calcolo a scopo di supporto e ricerca: non è un dispositivo medico marcato CE (Regolamento UE 2017/745). I risultati devono essere verificati e interpretati da personale qualificato. Software fornito senza alcuna garanzia (vedi licenza).
>
> **Disclaimer.** Calculation tool for support and research purposes: it is not a CE-marked medical device (EU Regulation 2017/745). Results must be verified and interpreted by qualified personnel. Software provided without any warranty (see licence).

Copyright (C) 2026 Davide Negrini – distribuito con licenza GNU AGPL v3, vedi [LICENSE](LICENSE)

| Cartella / Folder | Contenuto / Content |
|---|---|
| [`it/`](it/) | Versione italiana – vedi [`it/LEGGIMI.md`](it/LEGGIMI.md) |
| [`en/`](en/) | English version – see [`en/README.md`](en/README.md) |
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
