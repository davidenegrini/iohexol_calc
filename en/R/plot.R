# Plot of ln(concentration) vs time with regression line
decay_plot <- function(mg) {
  p <- mg$points
  if (is.null(p) || !any(p$used)) {
    plot.new(); text(0.5, 0.5, "No samples entered"); return(invisible())
  }
  ok <- p$used
  xmax <- max(c(p$t_min, 0), na.rm = TRUE) * 1.05
  y <- p$conc[ok]
  ylim <- range(c(y, if (!is.null(mg$c0)) mg$c0), na.rm = TRUE)
  op <- par(mar = c(4.2, 4.5, 1.5, 1)); on.exit(par(op))
  plot(p$t_min[ok], y, log = "y", pch = 19, col = "#1f5a96", cex = 1.4,
       xlim = c(0, xmax), ylim = ylim * c(0.85, 1.15),
       xlab = "Time after injection (min)", ylab = "Iohexol (mg/L, log scale)",
       las = 1, bty = "l")
  grid(col = "grey90", lty = 1)
  if (!is.null(mg$c0)) {
    tt <- seq(0, xmax, length.out = 100)
    lines(tt, mg$c0 * exp(-mg$k * tt), col = "#c0392b", lwd = 2)
    points(0, mg$c0, pch = 1, col = "#c0392b", cex = 1.4)
    legend("topright", bty = "n",
           legend = c("Samples used",
                      sprintf("C(t) = %.1f · e^(-%.5f · t)", mg$c0, mg$k)),
           pch = c(19, NA), lty = c(NA, 1), col = c("#1f5a96", "#c0392b"), lwd = c(NA, 2))
  }
  points(p$t_min[ok], y, pch = 19, col = "#1f5a96", cex = 1.4)
  text(p$t_min[ok], y, p$sample[ok], pos = 4, cex = 0.85)
}
