# Grafico ln(concentrazione) vs tempo con retta di regressione
grafico_decadimento <- function(mg) {
  p <- mg$punti
  if (is.null(p) || !any(p$usato)) {
    plot.new(); text(0.5, 0.5, "Nessun prelievo inserito"); return(invisible())
  }
  ok <- p$usato
  xmax <- max(c(p$t_min, 0), na.rm = TRUE) * 1.05
  y <- p$conc[ok]
  ylim <- range(c(y, if (!is.null(mg$c0)) mg$c0), na.rm = TRUE)
  op <- par(mar = c(4.2, 4.5, 1.5, 1)); on.exit(par(op))
  plot(p$t_min[ok], y, log = "y", pch = 19, col = "#1f5a96", cex = 1.4,
       xlim = c(0, xmax), ylim = ylim * c(0.85, 1.15),
       xlab = "Tempo dall'iniezione (min)", ylab = "Ioexolo (mg/L, scala log)",
       las = 1, bty = "l")
  grid(col = "grey90", lty = 1)
  if (!is.null(mg$c0)) {
    tt <- seq(0, xmax, length.out = 100)
    lines(tt, mg$c0 * exp(-mg$k * tt), col = "#c0392b", lwd = 2)
    points(0, mg$c0, pch = 1, col = "#c0392b", cex = 1.4)
    legend("topright", bty = "n",
           legend = c("Prelievi utilizzati",
                      sprintf("C(t) = %.1f · e^(-%.5f · t)", mg$c0, mg$k)),
           pch = c(19, NA), lty = c(NA, 1), col = c("#1f5a96", "#c0392b"), lwd = c(NA, 2))
  }
  points(p$t_min[ok], y, pch = 19, col = "#1f5a96", cex = 1.4)
  text(p$t_min[ok], y, p$prelievo[ok], pos = 4, cex = 0.85)
}
