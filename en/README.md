# Shiny app – mGFR with iohexol and eGFR (English version)

## Start
1. Install the packages once: `install.packages(c("shiny", "bslib", "rmarkdown", "knitr"))`
   (bslib ≥ 0.5).
2. Install **pandoc** (needed by rmarkdown to build the HTML report): https://pandoc.org/installing.html
   (Debian/Ubuntu: `sudo apt install pandoc`). RStudio bundles it, but RStudio is **not** required.
3. Local start from a terminal, in the repository root:
   `Rscript -e 'shiny::runApp("en", port = 3838, launch.browser = TRUE)'`
4. Deployment on a Shiny server.

## Structure
- `app.R` – Shiny user interface and server logic
- `R/calculations.R` – all formulas (mGFR, Brøchner-Mortensen, EKFC, CKD-EPI 2021)
- `R/plot.R` – decay curve plot
- `report.Rmd` – report template (HTML)

The Italian version (`../it/`) uses the same formulas and constants.

## Calculation choices
- Slope-intercept mGFR; Brøchner-Mortensen correction (0.990778 · CL − 0.001218 · CL²) on the absolute clearance, then normalisation to 1.73 m² (original 1972 formulation).
  *Note:* the BNMS guidelines (Fleming et al. 2004) apply the correction to the clearance already normalised to 1.73 m². The difference is small when BSA is close to 1.73 m² (≈ 0.5 mL/min/1.73 m² in the example case) and grows for BSA far from 1.73 m² and high GFR.
- BSA according to Gehan & George (1970).
- Iohexol concentrations also shown in µmol/L (mg/L × 1000 / 821.14); the calculation uses mg/L.
- eGFR: EKFC creatinine, cystatin C and their mean; CKD-EPI 2021 creatinine and creatinine + cystatin C.
- KDIGO category computed on normalised values (not on absolute mGFR).
- Numbers use the decimal point; dates are shown as YYYY-MM-DD.
- HTML report only (can be printed to PDF from the browser).

## Known limitations
- EKFC creatinine uses the fixed adult Q: for age < 25 years an age-dependent Q is required (the app shows a warning).
- Active quality checks: number of samples, R², first sample < 110 min, incomplete samples, concentrations ≤ 0.
- Minute calculation does not handle crossing midnight (a sample after 24:00 appears "earlier than T0" and blocks the calculation).
