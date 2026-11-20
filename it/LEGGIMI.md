# App Shiny – mGFR con ioexolo ed eGFR (versione italiana)

## Avvio
1. Installare (una volta) i pacchetti: `install.packages(c("shiny", "bslib", "rmarkdown", "knitr"))`
   (bslib ≥ 0.5).
2. Installare **pandoc** (serve a rmarkdown per creare il report HTML): https://pandoc.org/installing.html
   (su Debian/Ubuntu: `sudo apt install pandoc`). RStudio lo include già, ma RStudio **non** è necessario.
3. Avvio locale da terminale, dalla radice del repository:
   `Rscript -e 'shiny::runApp("it", port = 3838, launch.browser = TRUE)'`
4. Pubblicazione su un server Shiny: vedere [`../PUBBLICAZIONE.md`](../PUBBLICAZIONE.md).

## Struttura
- `app.R` – interfaccia e logica Shiny
- `R/calcoli.R` – tutte le formule (mGFR, Brøchner-Mortensen, EKFC, CKD-EPI 2021)
- `R/grafico.R` – grafico della curva di decadimento
- `report.Rmd` – modello del report (HTML)

La versione inglese (`../en/`) usa le stesse formule e costanti; `tests/test_formule.R`
verifica che le due versioni diano risultati identici.

## Scelte di calcolo
- mGFR slope-intercept; correzione di Brøchner-Mortensen (0,990778 · CL − 0,001218 · CL²) sulla clearance assoluta, poi normalizzazione a 1,73 m² (formulazione originale 1972).
  *Nota:* le linee guida BNMS (Fleming et al. 2004) applicano invece la correzione alla clearance già normalizzata a 1,73 m². La differenza è piccola quando la BSA è vicina a 1,73 m² (≈ 0,5 mL/min/1,73 m² nel caso di esempio) e cresce per BSA lontane da 1,73 m² e GFR elevati.
- BSA secondo Gehan & George (1970).
- Concentrazioni di ioexolo mostrate anche in µmol/L (mg/L × 1000 / 821,14); il calcolo usa mg/L.
- eGFR: EKFC creatinina, cistatina C e media delle due; CKD-EPI 2021 creatinina e creatinina + cistatina C.
- Classe KDIGO calcolata sui valori normalizzati (non sulla mGFR assoluta).
- Report solo in HTML (stampabile in PDF dal browser).

## Cose da ricordare per il futuro
- EKFC creatinina usa il Q adulto fisso: per età < 25 anni servirebbe il Q dipendente dall'età (l'app mostra un avviso).
- Controlli di qualità attivi: numero di prelievi, R², primo prelievo < 110 min, prelievi incompleti, concentrazioni ≤ 0.
- Il calcolo dei minuti non gestisce il passaggio della mezzanotte (un prelievo dopo le 24:00 risulta "precedente a T0" e blocca il calcolo).
