# =============================================================================
# Test di coerenza / consistency tests
#   - formule ricalcolate a mano (valori di riferimento indipendenti)
#   - versione italiana (it/) e inglese (en/) devono dare risultati identici
#   - avvio di entrambe le app Shiny e generazione del report HTML
# Uso / usage (dalla radice del repository / from the repository root):
#   Rscript tests/test_formule.R
# =============================================================================
ok <- TRUE
check <- function(desc, cond) {
  cat(if (isTRUE(cond)) "  OK   " else "  FAIL ", desc, "\n", sep = "")
  if (!isTRUE(cond)) ok <<- FALSE
}
near <- function(a, b, tol = 1e-9) isTRUE(all.equal(unname(a), unname(b), tolerance = tol))

it <- new.env(); eval(parse("it/R/calcoli.R", encoding = "UTF-8"), envir = it)
en <- new.env(); eval(parse("en/R/calculations.R", encoding = "UTF-8"), envir = en)

# ---- caso di esempio / example case -----------------------------------------
dose <- 3235000; t0 <- "08:00"
ore  <- c("10:00", "11:00", "12:00", "", "")
conc <- c(120, 95, 76, NA, NA)
nasc <- as.Date("1960-05-10"); prel <- as.Date("2026-11-20")

cat("Formule (valori ricalcolati a mano)\n")
# BSA Gehan & George
bsa_ref <- 0.0235 * 175^0.42246 * 75^0.51456
check("BSA Gehan & George", near(it$bsa_gehan_george(75, 175), bsa_ref))
check("eta' in anni compiuti", it$eta_anni(nasc, prel) == 66 &&
        it$eta_anni(as.Date("1960-11-21"), prel) == 65 && it$eta_anni(as.Date("1960-11-20"), prel) == 66)
check("eta' NA se nascita dopo prelievo", is.na(it$eta_anni(prel + 1, prel)))
# slope-intercept
tt <- c(120, 180, 240); fit <- lm(log(c(120, 95, 76)) ~ tt)
c0 <- exp(coef(fit)[1]); k <- -coef(fit)[2]; cl <- dose / (c0 / k)
gfr_abs <- 0.990778 * cl - 0.001218 * cl^2
mg <- it$calcola_mgfr(t0, ore, conc, dose, bsa_ref)
check("CL = Dose / (C0/k)", near(mg$cl, cl))
check("Brochner-Mortensen su CL assoluta", near(mg$gfr_abs, gfr_abs))
check("normalizzazione 1,73 m2 dopo BM", near(mg$gfr_norm, gfr_abs * 1.73 / bsa_ref))
check("emivita = ln2/k", near(mg$emivita_min, log(2) / k))
check("conversione umol/L", near(mg$punti$conc_umol[1], 120 / 821.14 * 1000))
# EKFC
check("EKFC crea (M, 66 a, Scr 1,1)", near(it$ekfc_crea(1.1, "M", 66)$egfr, 107.3 * (1.1 / 0.9)^-1.132 * 0.99^26))
check("EKFC crea (F, 30 a, Scr 0,6)", near(it$ekfc_crea(0.6, "F", 30)$egfr, 107.3 * (0.6 / 0.7)^-0.322))
check("EKFC cys (66 a): Q = 0,83 + 0,005*16", near(it$ekfc_cys(1.2, 66)$q, 0.91) &&
        near(it$ekfc_cys(1.2, 66)$egfr, 107.3 * (1.2 / 0.91)^-1.132 * 0.99^26))
check("EKFC cys (45 a): Q = 0,83", near(it$ekfc_cys(0.7, 45)$egfr, 107.3 * (0.7 / 0.83)^-0.322 * 0.99^5))
# CKD-EPI 2021
check("CKD-EPI 2021 crea M", near(it$ckdepi2021_crea(1.1, "M", 66), 142 * (1.1 / 0.9)^-1.2 * 0.9938^66))
check("CKD-EPI 2021 crea F", near(it$ckdepi2021_crea(0.6, "F", 30), 142 * (0.6 / 0.7)^-0.241 * 0.9938^30 * 1.012))
check("CKD-EPI 2021 crea+cys M", near(it$ckdepi2021_crea_cys(1.1, 1.2, "M", 66),
                                      135 * (1.1 / 0.9)^-0.544 * (1.2 / 0.8)^-0.778 * 0.9961^66))
check("CKD-EPI 2021 crea+cys F", near(it$ckdepi2021_crea_cys(0.6, 0.7, "F", 30),
                                      135 * (0.6 / 0.7)^-0.219 * (0.7 / 0.8)^-0.323 * 0.9961^30 * 0.963))
check("classi KDIGO", identical(vapply(c(95, 90, 60, 59.9, 45, 30, 15, 14.9), it$classe_kdigo, ""),
                                c("G1", "G1", "G2", "G3a", "G3a", "G3b", "G4", "G5")))

cat("Coerenza it/ <-> en/\n")
casi <- list(
  list(sesso = "M", scr = 1.1, scys = 1.2, nasc = nasc, peso = 75, alt = 175, conc = conc, ore = ore),
  list(sesso = "F", scr = 0.6, scys = 0.7, nasc = as.Date("2003-01-01"), peso = 55, alt = 160,
       conc = c(80, 60, 45, 34, NA), ore = c("10:05", "11:00", "12:10", "13:00", "")),
  list(sesso = "F", scr = 3.4, scys = 2.9, nasc = as.Date("1940-02-29"), peso = 62, alt = 158,
       conc = c(300, 280, NA, 0, 250), ore = c("09:00", "11:00", "12:00", "13:00", "14:00")),
  list(sesso = NA, scr = NA, scys = 1.0, nasc = NA, peso = NA, alt = 170, conc = conc, ore = ore))
for (i in seq_along(casi)) {
  x <- casi[[i]]
  ri <- it$calcola_tutto(list(data_nascita = x$nasc, data_prelievo = prel, sesso = x$sesso, peso = x$peso,
                              altezza = x$alt, scr = x$scr, scys = x$scys, dose_ug = dose, t0 = t0,
                              ore = x$ore, conc = x$conc))
  re <- en$calc_all(list(birth_date = x$nasc, sample_date = prel, sex = x$sesso, weight = x$peso,
                         height = x$alt, scr = x$scr, scys = x$scys, dose_ug = dose, t0 = t0,
                         times = x$ore, conc = x$conc))
  vi <- it$tabella_risultati(ri)$Valore; ve <- en$results_table(re)$Value
  check(sprintf("caso %d: stessi risultati (%s)", i, paste(it$fmt(vi), collapse = " | ")),
        identical(is.na(vi), is.na(ve)) && near(vi[!is.na(vi)], ve[!is.na(ve)], 0))
  check(sprintf("caso %d: stesso numero di errori/avvisi", i),
        length(ri$mgfr$errori) == length(re$mgfr$errors) &&
          length(ri$mgfr$avvisi) == length(re$mgfr$warnings) &&
          length(ri$avvisi_egfr) == length(re$egfr_warnings))
}

cat("App Shiny e report\n")
suppressMessages(library(shiny))
prova_app <- function(dir, inputs, out_tab, out_report) {
  owd <- setwd(dir); on.exit(setwd(owd))
  esito <- list()
  testServer(shinyAppDir("."), {
    do.call(session$setInputs, inputs)
    esito$tab <<- output[[out_tab]]
    esito$file <<- output[[out_report]]
    esito$html <<- paste(readLines(esito$file, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  })
  esito
}
comuni <- list(scr = 1.1, scys = 1.2, dose_ug = dose, t0 = t0, conc1 = 120, conc2 = 95, conc3 = 76,
               conc4 = NA, conc5 = NA)
a_it <- prova_app("it", c(comuni, list(richiesta = "1", cognome = "Rossi", nome = "Mario", sesso = "M",
  data_nascita = nasc, data_prelievo = prel, peso = 75, altezza = 175, quesito = "",
  ora1 = ore[1], ora2 = ore[2], ora3 = ore[3], ora4 = "", ora5 = "")), "tab_risultati", "report_html")
a_en <- prova_app("en", c(comuni, list(request_id = "1", surname = "Rossi", first_name = "Mario", sex = "M",
  birth_date = nasc, sample_date = prel, weight = 75, height = 175, clinical_question = "",
  time1 = ore[1], time2 = ore[2], time3 = ore[3], time4 = "", time5 = "")), "results_tab", "report_html")
check("app it: tabella risultati con mGFR 53,4", grepl("53,4", a_it$tab))
check("app en: results table with mGFR 53.4", grepl("53.4", a_en$tab, fixed = TRUE))
check("report it generato, con mGFR e lettere accentate corrette",
      grepl("53,4", a_it$html) && grepl("Età al prelievo", a_it$html) && !grepl("<U+", a_it$html, fixed = TRUE))
check("report en generated, with mGFR and correct symbols",
      grepl("53.4", a_en$html, fixed = TRUE) && grepl("µmol/L", a_en$html) && !grepl("<U+", a_en$html, fixed = TRUE))

cat(if (ok) "\nTUTTI I TEST SUPERATI / ALL TESTS PASSED\n" else "\nALCUNI TEST FALLITI / SOME TESTS FAILED\n")
if (!ok) quit(status = 1)
