# =============================================================================
# calcoli.R - Funzioni di calcolo per mGFR (ioexolo) ed eGFR
# Tutte le funzioni sono "pure": stessi input -> stessi output, nessun effetto
# collaterale. Vengono usate sia dall'app Shiny sia dal report.
# =============================================================================

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- Costanti ---------------------------------------------------------------
DOSE_DEFAULT_UG <- 3235000   # 5 mL Omnipaque 300 (647 mg ioexolo/mL) = 3235 mg
IOEXOLO_MW <- 821.14         # g/mol (C19H26I3N3O9): umol/L = mg/L / 821,14 * 1000
BM_A <- 0.990778             # Brochner-Mortensen 1972
BM_B <- 0.001218

# ---- Dati anagrafici / antropometrici --------------------------------------

#' Converte in Date; NA se il valore e' vuoto o non interpretabile
come_data <- function(x) {
  if (is.null(x) || length(x) == 0) return(as.Date(NA))
  tryCatch(as.Date(x[[1]]), error = function(e) as.Date(NA))
}

#' Eta' in anni compiuti alla data del prelievo
eta_anni <- function(data_nascita, data_prelievo) {
  data_nascita <- come_data(data_nascita); data_prelievo <- come_data(data_prelievo)
  if (is.na(data_nascita) || is.na(data_prelievo)) return(NA_real_)
  if (as.Date(data_nascita) > as.Date(data_prelievo)) return(NA_real_)  # nascita successiva al prelievo
  dn <- as.POSIXlt(as.Date(data_nascita)); dp <- as.POSIXlt(as.Date(data_prelievo))
  anni <- dp$year - dn$year
  if (dp$mon < dn$mon || (dp$mon == dn$mon && dp$mday < dn$mday)) anni <- anni - 1
  as.numeric(anni)
}

#' BSA secondo Gehan & George (1970), m^2
bsa_gehan_george <- function(peso_kg, altezza_cm) {
  if (is.na(peso_kg) || is.na(altezza_cm) || peso_kg <= 0 || altezza_cm <= 0) return(NA_real_)
  0.0235 * altezza_cm^0.42246 * peso_kg^0.51456
}

#' Converte "HH:MM" (o "HH.MM") in minuti dalla mezzanotte
ora_in_minuti <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(trimws(x))) return(NA_real_)
  x <- gsub("[.,]", ":", trimws(x))
  if (!grepl("^\\d{1,2}:\\d{2}$", x)) return(NA_real_)
  p <- as.numeric(strsplit(x, ":")[[1]])
  if (p[1] > 23 || p[2] > 59) return(NA_real_)
  p[1] * 60 + p[2]
}

# ---- mGFR: metodo slope-intercept (un compartimento) ------------------------

#' Calcolo completo della mGFR da 2-5 prelievi di ioexolo
#'
#' @param t0         ora dell'iniezione "HH:MM"
#' @param ore        vettore di orari "HH:MM" dei prelievi (anche con NA/vuoti)
#' @param conc       vettore di concentrazioni ioexolo (mg/L)
#' @param dose_ug    dose iniettata in microgrammi
#' @param bsa        BSA in m^2
#'
#' Correzione di Brochner-Mortensen secondo la formulazione originale (1972):
#' la correzione si applica alla clearance assoluta e la normalizzazione a
#' 1,73 m2 si esegue DOPO la correzione.
calcola_mgfr <- function(t0, ore, conc, dose_ug, bsa) {
  t0_min <- ora_in_minuti(t0)
  ore    <- unname(as.character(ore))
  t_min  <- unname(vapply(ore, ora_in_minuti, numeric(1), USE.NAMES = FALSE)) - t0_min
  conc   <- suppressWarnings(as.numeric(conc))

  punti <- data.frame(
    prelievo = paste0("T", seq_along(ore)),
    ora = ifelse(is.na(ore), "", ore),
    t_min = t_min, conc = conc,
    conc_umol = conc / IOEXOLO_MW * 1000,
    ln_conc = ifelse(!is.na(conc) & conc > 0, log(conc), NA_real_),
    stringsAsFactors = FALSE
  )
  punti$usato <- !is.na(punti$t_min) & !is.na(punti$ln_conc)
  usati <- punti[punti$usato, ]

  avvisi <- character(0); errori <- character(0)
  if (is.na(t0_min)) errori <- c(errori, "Ora T0 (iniezione) mancante o non valida (formato HH:MM).")
  if (nrow(usati) < 2) errori <- c(errori, "Servono almeno 2 prelievi completi (ora + concentrazione).")
  if (is.na(dose_ug) || dose_ug <= 0) errori <- c(errori, "Dose iniettata mancante o non valida.")
  if (is.na(bsa)) errori <- c(errori, "BSA non calcolabile: peso e/o altezza mancanti o non validi.")
  if (any(!is.na(punti$t_min) & punti$t_min <= 0))
    errori <- c(errori, "Uno o pi\u00f9 prelievi risultano precedenti o uguali a T0: controllare gli orari.")
  # dati parziali: ora senza concentrazione o viceversa
  parziali <- xor(!is.na(punti$t_min), !is.na(punti$conc))
  if (any(parziali))
    avvisi <- c(avvisi, paste0("Prelievo/i ", paste(punti$prelievo[parziali], collapse = ", "),
                               " incompleto/i (manca ora o concentrazione): escluso/i dal calcolo."))
  # concentrazione <= 0: il logaritmo non esiste, il prelievo viene escluso
  non_pos <- !is.na(punti$conc) & punti$conc <= 0
  if (any(non_pos))
    avvisi <- c(avvisi, paste0("Prelievo/i ", paste(punti$prelievo[non_pos], collapse = ", "),
                               " con concentrazione <= 0: escluso/i dal calcolo."))

  out <- list(punti = punti, n_punti = nrow(usati), avvisi = avvisi, errori = errori,
              dose_ug = dose_ug, bsa = bsa)
  if (length(errori) > 0) return(out)

  fit <- lm(ln_conc ~ t_min, data = usati)
  ln_c0 <- unname(coef(fit)[1]); pend <- unname(coef(fit)[2])
  if (pend >= 0) {
    out$errori <- c(out$errori, "La concentrazione non decresce nel tempo (pendenza >= 0): dati non plausibili.")
    return(out)
  }
  c0  <- exp(ln_c0)            # mg/L
  k   <- abs(pend)             # 1/min
  auc <- c0 / k                # mg/L * min
  cl  <- dose_ug / auc         # ug / (ug/mL * min) = mL/min
  r2  <- if (nrow(usati) > 2) summary(fit)$r.squared else NA_real_

  gfr_abs  <- BM_A * cl - BM_B * cl^2         # correzione BM sulla CL assoluta
  gfr_norm <- gfr_abs * 1.73 / bsa            # poi normalizzazione a 1,73 m2

  # controlli di qualita (informativi)
  if (min(usati$t_min) < 110)
    out$avvisi <- c(out$avvisi, "Primo prelievo utilizzato prima di circa 2 ore (< 110 min) dall'iniezione: il modello monocompartimentale potrebbe sovrastimare la clearance.")
  if (!is.na(r2) && r2 < 0.98)
    out$avvisi <- c(out$avvisi, sprintf("R^2 della regressione log-lineare = %.3f (< 0,98): verificare i prelievi.", r2))
  if (nrow(usati) == 2)
    out$avvisi <- c(out$avvisi, "Calcolo basato su 2 soli prelievi: R^2 non valutabile.")

  modifyList(out, list(fit = fit, ln_c0 = ln_c0, pendenza = pend, c0 = c0, k = k,
                       emivita_min = log(2) / k, auc = auc, cl = cl,
                       r2 = r2, gfr_abs = gfr_abs, gfr_norm = gfr_norm))
}

# ---- eGFR: EKFC -------------------------------------------------------------
# Pottel et al. Ann Intern Med 2021 (creatinina); Pottel et al. NEJM 2023
# (cistatina C). Stessa forma matematica, cambia solo il valore Q.

.ekfc_core <- function(x, eta) {
  alfa <- if (x < 1) -0.322 else -1.132
  egfr <- 107.3 * x^alfa
  if (eta > 40) egfr <- egfr * 0.990^(eta - 40)
  list(egfr = egfr, alfa = alfa)
}

#' Q della creatinina EKFC (mg/dL) in funzione di sesso ed et\u00e0.
#' 2-25 anni: polinomi di Pottel et al. Ann Intern Med 2021 (Q in umol/L,
#' convertito in mg/dL dividendo per 88,4); > 25 anni: Q adulto fisso
#' (80 umol/L = 0,90 mg/dL M; 62 umol/L = 0,70 mg/dL F).
#' Restituisce NA sotto i 2 anni (fuori dal range di validit\u00e0 EKFC).
ekfc_q_crea <- function(sesso, eta) {
  if (is.na(eta) || eta < 2) return(NA_real_)
  if (eta > 25) return(if (sesso == "M") 0.90 else 0.70)
  ln_q <- if (sesso == "M")
    3.200 + 0.259 * eta - 0.543 * log(eta) - 0.00763 * eta^2 + 0.0000790 * eta^3
  else
    3.080 + 0.177 * eta - 0.223 * log(eta) - 0.00596 * eta^2 + 0.0000686 * eta^3
  exp(ln_q) / 88.4
}

#' EKFC creatinina (Q dipendente dall'et\u00e0 per 2-25 anni, Q adulto fisso oltre; valida 2-100 anni)
ekfc_crea <- function(scr, sesso, eta) {
  if (any(is.na(c(scr, eta))) || is.null(sesso) || !sesso %in% c("M", "F")) return(NULL)
  q <- ekfc_q_crea(sesso, eta)
  if (is.na(q)) return(NULL)
  x <- scr / q; r <- .ekfc_core(x, eta)
  list(q = q, ratio = x, alfa = r$alfa, egfr = r$egfr)
}

#' EKFC cistatina C (Q = 0,83 mg/L da 2 a < 50 anni, senza differenze di sesso;
#' 0,83 + 0,005*(eta-50) se >= 50)
ekfc_cys <- function(scys, eta) {
  if (any(is.na(c(scys, eta))) || eta < 2) return(NULL)
  q <- if (eta < 50) 0.83 else 0.83 + 0.005 * (eta - 50)
  x <- scys / q; r <- .ekfc_core(x, eta)
  list(q = q, ratio = x, alfa = r$alfa, egfr = r$egfr)
}

#' EKFC combinata = media aritmetica di EKFC-crea ed EKFC-cys
ekfc_combinata <- function(e_cr, e_cys) {
  if (is.null(e_cr) || is.null(e_cys)) return(NA_real_)
  (e_cr$egfr + e_cys$egfr) / 2
}

# ---- eGFR: CKD-EPI 2021 -----------------------------------------------------
# Inker et al. NEJM 2021 (equazioni senza coefficiente razziale)

#' CKD-EPI 2021 sola creatinina
ckdepi2021_crea <- function(scr, sesso, eta) {
  if (any(is.na(c(scr, eta))) || is.null(sesso) || !sesso %in% c("M", "F")) return(NA_real_)
  f <- sesso == "F"
  k <- if (f) 0.7 else 0.9
  a <- if (f) -0.241 else -0.302
  142 * min(scr / k, 1)^a * max(scr / k, 1)^-1.200 * 0.9938^eta * (if (f) 1.012 else 1)
}

#' CKD-EPI 2021 creatinina + cistatina C
ckdepi2021_crea_cys <- function(scr, scys, sesso, eta) {
  if (any(is.na(c(scr, scys, eta))) || is.null(sesso) || !sesso %in% c("M", "F")) return(NA_real_)
  f <- sesso == "F"
  k <- if (f) 0.7 else 0.9
  a <- if (f) -0.219 else -0.144
  135 * min(scr / k, 1)^a * max(scr / k, 1)^-0.544 *
    min(scys / 0.8, 1)^-0.323 * max(scys / 0.8, 1)^-0.778 *
    0.9961^eta * (if (f) 0.963 else 1)
}

# ---- Calcolo complessivo ----------------------------------------------------

#' Esegue tutti i calcoli a partire da una lista di input
#' (campi: data_prelievo, data_nascita, sesso, peso, altezza, scr, scys,
#'  dose_ug, t0, ore[5], conc[5])
calcola_tutto <- function(inp) {
  eta <- eta_anni(inp$data_nascita, inp$data_prelievo)
  bsa <- bsa_gehan_george(inp$peso, inp$altezza)
  mg  <- calcola_mgfr(inp$t0, inp$ore, inp$conc, inp$dose_ug, bsa)
  e_cr  <- if (!is.na(eta)) ekfc_crea(inp$scr, inp$sesso, eta) else NULL
  e_cys <- if (!is.na(eta)) ekfc_cys(inp$scys, eta) else NULL
  avvisi_egfr <- character(0)
  if (!is.na(eta) && eta < 2)
    avvisi_egfr <- c(avvisi_egfr, "Et\u00e0 < 2 anni: l'equazione EKFC non \u00e8 validata e non viene calcolata.")
  else if (!is.na(eta) && eta <= 25)
    avvisi_egfr <- c(avvisi_egfr, sprintf("Et\u00e0 \u2264 25 anni: EKFC creatinina calcolata con Q dipendente da et\u00e0 e sesso (Q = %.3f mg/dL).",
                                          if (is.null(e_cr)) NA_real_ else e_cr$q))
  if (!is.na(eta) && eta < 18)
    avvisi_egfr <- c(avvisi_egfr, "Paziente pediatrico: le equazioni CKD-EPI non sono validate sotto i 18 anni.")
  list(
    eta = eta, bsa = bsa, mgfr = mg,
    ekfc_cr = e_cr, ekfc_cys = e_cys,
    ekfc_crcys = ekfc_combinata(e_cr, e_cys),
    ckdepi_cr = if (!is.na(eta)) ckdepi2021_crea(inp$scr, inp$sesso, eta) else NA_real_,
    ckdepi_crcys = if (!is.na(eta)) ckdepi2021_crea_cys(inp$scr, inp$scys, inp$sesso, eta) else NA_real_,
    avvisi_egfr = avvisi_egfr
  )
}

#' Tabella riassuntiva dei risultati (per app e report)
tabella_risultati <- function(r) {
  mg <- r$mgfr
  val <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NA_real_ else x
  tab <- data.frame(
    Metodo = c("mGFR ioexolo (assoluta)",
               "mGFR ioexolo (normalizzata)",
               "eGFR EKFC creatinina",
               "eGFR EKFC cistatina C",
               "eGFR EKFC creatinina + cistatina C",
               "eGFR CKD-EPI 2021 creatinina",
               "eGFR CKD-EPI 2021 creatinina + cistatina C"),
    Valore = c(val(mg$gfr_abs), val(mg$gfr_norm),
               val(r$ekfc_cr$egfr), val(r$ekfc_cys$egfr), val(r$ekfc_crcys),
               val(r$ckdepi_cr), val(r$ckdepi_crcys)),
    Unita = c("mL/min", rep("mL/min/1,73 m\u00b2", 6)),
    stringsAsFactors = FALSE
  )
  names(tab)[3] <- "Unit\u00e0"
  tab
}

#' Classe KDIGO di GFR (G1-G5)
classe_kdigo <- function(gfr) {
  if (is.na(gfr)) return(NA_character_)
  if (gfr >= 90) "G1" else if (gfr >= 60) "G2" else if (gfr >= 45) "G3a" else
    if (gfr >= 30) "G3b" else if (gfr >= 15) "G4" else "G5"
}

fmt <- function(x, d = 1) ifelse(is.na(x), "—", formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","))
