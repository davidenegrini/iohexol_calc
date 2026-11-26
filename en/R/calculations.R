# =============================================================================
# calculations.R - Calculation functions for mGFR (iohexol) and eGFR
# All functions are "pure": same inputs -> same outputs, no side effects.
# They are used both by the Shiny app and by the report.
# English translation of it/R/calcoli.R: formulas and constants MUST stay
# identical.
# =============================================================================

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- Constants --------------------------------------------------------------
DEFAULT_DOSE_UG <- 3235000   # 5 mL Omnipaque 300 (647 mg iohexol/mL) = 3235 mg
IOHEXOL_MW <- 821.14         # g/mol (C19H26I3N3O9): umol/L = mg/L / 821.14 * 1000
BM_A <- 0.990778             # Brochner-Mortensen 1972
BM_B <- 0.001218

# ---- Demographic / anthropometric data -------------------------------------

#' Converts to Date; NA if the value is empty or cannot be parsed
as_date_safe <- function(x) {
  if (is.null(x) || length(x) == 0) return(as.Date(NA))
  tryCatch(as.Date(x[[1]]), error = function(e) as.Date(NA))
}

#' Age in completed years at the sampling date
age_years <- function(birth_date, sample_date) {
  birth_date <- as_date_safe(birth_date); sample_date <- as_date_safe(sample_date)
  if (is.na(birth_date) || is.na(sample_date)) return(NA_real_)
  if (as.Date(birth_date) > as.Date(sample_date)) return(NA_real_)  # birth after sampling
  b <- as.POSIXlt(as.Date(birth_date)); s <- as.POSIXlt(as.Date(sample_date))
  years <- s$year - b$year
  if (s$mon < b$mon || (s$mon == b$mon && s$mday < b$mday)) years <- years - 1
  as.numeric(years)
}

#' BSA according to Gehan & George (1970), m^2
bsa_gehan_george <- function(weight_kg, height_cm) {
  if (is.na(weight_kg) || is.na(height_cm) || weight_kg <= 0 || height_cm <= 0) return(NA_real_)
  0.0235 * height_cm^0.42246 * weight_kg^0.51456
}

#' Converts "HH:MM" (or "HH.MM") to minutes after midnight
time_to_minutes <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(trimws(x))) return(NA_real_)
  x <- gsub("[.,]", ":", trimws(x))
  if (!grepl("^\\d{1,2}:\\d{2}$", x)) return(NA_real_)
  p <- as.numeric(strsplit(x, ":")[[1]])
  if (p[1] > 23 || p[2] > 59) return(NA_real_)
  p[1] * 60 + p[2]
}

# ---- mGFR: slope-intercept method (one compartment) -------------------------

#' Full mGFR calculation from 2-5 iohexol samples
#'
#' @param t0         injection time "HH:MM"
#' @param times      vector of sampling times "HH:MM" (NA/empty allowed)
#' @param conc       vector of iohexol concentrations (mg/L)
#' @param dose_ug    injected dose in micrograms
#' @param bsa        BSA in m^2
#'
#' Brochner-Mortensen correction in its original formulation (1972):
#' the correction is applied to the absolute clearance and normalisation to
#' 1.73 m2 is performed AFTER the correction.
calc_mgfr <- function(t0, times, conc, dose_ug, bsa) {
  t0_min <- time_to_minutes(t0)
  times  <- unname(as.character(times))
  t_min  <- unname(vapply(times, time_to_minutes, numeric(1), USE.NAMES = FALSE)) - t0_min
  conc   <- suppressWarnings(as.numeric(conc))

  points <- data.frame(
    sample = paste0("T", seq_along(times)),
    time = ifelse(is.na(times), "", times),
    t_min = t_min, conc = conc,
    conc_umol = conc / IOHEXOL_MW * 1000,
    ln_conc = ifelse(!is.na(conc) & conc > 0, log(conc), NA_real_),
    stringsAsFactors = FALSE
  )
  points$used <- !is.na(points$t_min) & !is.na(points$ln_conc)
  used <- points[points$used, ]

  warnings <- character(0); errors <- character(0)
  if (is.na(t0_min)) errors <- c(errors, "Injection time T0 missing or invalid (format HH:MM).")
  if (nrow(used) < 2) errors <- c(errors, "At least 2 complete samples (time + concentration) are required.")
  if (is.na(dose_ug) || dose_ug <= 0) errors <- c(errors, "Injected dose missing or invalid.")
  if (is.na(bsa)) errors <- c(errors, "BSA cannot be calculated: weight and/or height missing or invalid.")
  if (any(!is.na(points$t_min) & points$t_min <= 0))
    errors <- c(errors, "One or more samples are earlier than or equal to T0: check the times.")
  # partial data: time without concentration or vice versa
  partial <- xor(!is.na(points$t_min), !is.na(points$conc))
  if (any(partial))
    warnings <- c(warnings, paste0("Sample(s) ", paste(points$sample[partial], collapse = ", "),
                                   " incomplete (time or concentration missing): excluded from the calculation."))
  # concentration <= 0: the logarithm does not exist, the sample is excluded
  non_pos <- !is.na(points$conc) & points$conc <= 0
  if (any(non_pos))
    warnings <- c(warnings, paste0("Sample(s) ", paste(points$sample[non_pos], collapse = ", "),
                                   " with concentration <= 0: excluded from the calculation."))

  out <- list(points = points, n_points = nrow(used), warnings = warnings, errors = errors,
              dose_ug = dose_ug, bsa = bsa)
  if (length(errors) > 0) return(out)

  fit <- lm(ln_conc ~ t_min, data = used)
  ln_c0 <- unname(coef(fit)[1]); slope <- unname(coef(fit)[2])
  if (slope >= 0) {
    out$errors <- c(out$errors, "Concentration does not decrease over time (slope >= 0): implausible data.")
    return(out)
  }
  c0  <- exp(ln_c0)            # mg/L
  k   <- abs(slope)            # 1/min
  auc <- c0 / k                # mg/L * min
  cl  <- dose_ug / auc         # ug / (ug/mL * min) = mL/min
  r2  <- if (nrow(used) > 2) summary(fit)$r.squared else NA_real_

  gfr_abs  <- BM_A * cl - BM_B * cl^2         # BM correction on absolute CL
  gfr_norm <- gfr_abs * 1.73 / bsa            # then normalisation to 1.73 m2

  # quality checks (informative)
  if (min(used$t_min) < 110)
    out$warnings <- c(out$warnings, "First sample used taken earlier than about 2 hours (< 110 min) after injection: the one-compartment model may overestimate clearance.")
  if (!is.na(r2) && r2 < 0.98)
    out$warnings <- c(out$warnings, sprintf("R^2 of the log-linear regression = %.3f (< 0.98): check the samples.", r2))
  if (nrow(used) == 2)
    out$warnings <- c(out$warnings, "Calculation based on only 2 samples: R^2 cannot be assessed.")

  modifyList(out, list(fit = fit, ln_c0 = ln_c0, slope = slope, c0 = c0, k = k,
                       half_life_min = log(2) / k, auc = auc, cl = cl,
                       r2 = r2, gfr_abs = gfr_abs, gfr_norm = gfr_norm))
}

# ---- eGFR: EKFC -------------------------------------------------------------
# Pottel et al. Ann Intern Med 2021 (creatinine); Pottel et al. NEJM 2023
# (cystatin C). Same mathematical form, only the Q value changes.

.ekfc_core <- function(x, age) {
  alpha <- if (x < 1) -0.322 else -1.132
  egfr <- 107.3 * x^alpha
  if (age > 40) egfr <- egfr * 0.990^(age - 40)
  list(egfr = egfr, alpha = alpha)
}

#' EKFC creatinine Q (mg/dL) as a function of sex and age.
#' 2-25 years: Pottel et al. Ann Intern Med 2021 polynomials (Q in umol/L,
#' converted to mg/dL by dividing by 88.4); > 25 years: fixed adult Q
#' (80 umol/L = 0.90 mg/dL M; 62 umol/L = 0.70 mg/dL F).
#' Returns NA below 2 years (outside the EKFC validity range).
ekfc_q_creat <- function(sex, age) {
  if (is.na(age) || age < 2) return(NA_real_)
  if (age > 25) return(if (sex == "M") 0.90 else 0.70)
  ln_q <- if (sex == "M")
    3.200 + 0.259 * age - 0.543 * log(age) - 0.00763 * age^2 + 0.0000790 * age^3
  else
    3.080 + 0.177 * age - 0.223 * log(age) - 0.00596 * age^2 + 0.0000686 * age^3
  exp(ln_q) / 88.4
}

#' EKFC creatinine (age-dependent Q for 2-25 years, fixed adult Q above; valid 2-100 years)
ekfc_creat <- function(scr, sex, age) {
  if (any(is.na(c(scr, age))) || is.null(sex) || !sex %in% c("M", "F")) return(NULL)
  q <- ekfc_q_creat(sex, age)
  if (is.na(q)) return(NULL)
  x <- scr / q; r <- .ekfc_core(x, age)
  list(q = q, ratio = x, alpha = r$alpha, egfr = r$egfr)
}

#' EKFC cystatin C (Q = 0.83 mg/L from 2 to < 50 years, sex-independent;
#' 0.83 + 0.005*(age-50) if >= 50)
ekfc_cys <- function(scys, age) {
  if (any(is.na(c(scys, age))) || age < 2) return(NULL)
  q <- if (age < 50) 0.83 else 0.83 + 0.005 * (age - 50)
  x <- scys / q; r <- .ekfc_core(x, age)
  list(q = q, ratio = x, alpha = r$alpha, egfr = r$egfr)
}

#' Combined EKFC = arithmetic mean of EKFC-creat and EKFC-cys
ekfc_combined <- function(e_cr, e_cys) {
  if (is.null(e_cr) || is.null(e_cys)) return(NA_real_)
  (e_cr$egfr + e_cys$egfr) / 2
}

# ---- eGFR: CKD-EPI 2021 -----------------------------------------------------
# Inker et al. NEJM 2021 (equations without race coefficient)

#' CKD-EPI 2021 creatinine only
ckdepi2021_creat <- function(scr, sex, age) {
  if (any(is.na(c(scr, age))) || is.null(sex) || !sex %in% c("M", "F")) return(NA_real_)
  f <- sex == "F"
  k <- if (f) 0.7 else 0.9
  a <- if (f) -0.241 else -0.302
  142 * min(scr / k, 1)^a * max(scr / k, 1)^-1.200 * 0.9938^age * (if (f) 1.012 else 1)
}

#' CKD-EPI 2021 creatinine + cystatin C
ckdepi2021_creat_cys <- function(scr, scys, sex, age) {
  if (any(is.na(c(scr, scys, age))) || is.null(sex) || !sex %in% c("M", "F")) return(NA_real_)
  f <- sex == "F"
  k <- if (f) 0.7 else 0.9
  a <- if (f) -0.219 else -0.144
  135 * min(scr / k, 1)^a * max(scr / k, 1)^-0.544 *
    min(scys / 0.8, 1)^-0.323 * max(scys / 0.8, 1)^-0.778 *
    0.9961^age * (if (f) 0.963 else 1)
}

# ---- Overall calculation ----------------------------------------------------

#' Runs all calculations from a list of inputs
#' (fields: sample_date, birth_date, sex, weight, height, scr, scys,
#'  dose_ug, t0, times[5], conc[5])
calc_all <- function(inp) {
  age <- age_years(inp$birth_date, inp$sample_date)
  bsa <- bsa_gehan_george(inp$weight, inp$height)
  mg  <- calc_mgfr(inp$t0, inp$times, inp$conc, inp$dose_ug, bsa)
  e_cr  <- if (!is.na(age)) ekfc_creat(inp$scr, inp$sex, age) else NULL
  e_cys <- if (!is.na(age)) ekfc_cys(inp$scys, age) else NULL
  egfr_warnings <- character(0)
  if (!is.na(age) && age < 2)
    egfr_warnings <- c(egfr_warnings, "Age < 2 years: the EKFC equation is not validated and is not calculated.")
  else if (!is.na(age) && age <= 25)
    egfr_warnings <- c(egfr_warnings, sprintf("Age \u2264 25 years: EKFC creatinine calculated with age- and sex-dependent Q (Q = %.3f mg/dL).",
                                              if (is.null(e_cr)) NA_real_ else e_cr$q))
  if (!is.na(age) && age < 18)
    egfr_warnings <- c(egfr_warnings, "Paediatric patient: the CKD-EPI equations are not validated below 18 years.")
  list(
    age = age, bsa = bsa, mgfr = mg,
    ekfc_cr = e_cr, ekfc_cys = e_cys,
    ekfc_crcys = ekfc_combined(e_cr, e_cys),
    ckdepi_cr = if (!is.na(age)) ckdepi2021_creat(inp$scr, inp$sex, age) else NA_real_,
    ckdepi_crcys = if (!is.na(age)) ckdepi2021_creat_cys(inp$scr, inp$scys, inp$sex, age) else NA_real_,
    egfr_warnings = egfr_warnings
  )
}

#' Summary table of results (for app and report)
results_table <- function(r) {
  mg <- r$mgfr
  val <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NA_real_ else x
  data.frame(
    Method = c("mGFR iohexol (absolute)",
               "mGFR iohexol (normalised)",
               "eGFR EKFC creatinine",
               "eGFR EKFC cystatin C",
               "eGFR EKFC creatinine + cystatin C",
               "eGFR CKD-EPI 2021 creatinine",
               "eGFR CKD-EPI 2021 creatinine + cystatin C"),
    Value = c(val(mg$gfr_abs), val(mg$gfr_norm),
              val(r$ekfc_cr$egfr), val(r$ekfc_cys$egfr), val(r$ekfc_crcys),
              val(r$ckdepi_cr), val(r$ckdepi_crcys)),
    Unit = c("mL/min", rep("mL/min/1.73 m²", 6)),
    stringsAsFactors = FALSE
  )
}

#' KDIGO GFR category (G1-G5)
kdigo_category <- function(gfr) {
  if (is.na(gfr)) return(NA_character_)
  if (gfr >= 90) "G1" else if (gfr >= 60) "G2" else if (gfr >= 45) "G3a" else
    if (gfr >= 30) "G3b" else if (gfr >= 15) "G4" else "G5"
}

fmt <- function(x, d = 1) ifelse(is.na(x), "—", formatC(x, format = "f", digits = d, big.mark = ",", decimal.mark = "."))
