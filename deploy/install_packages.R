# Installa i pacchetti R necessari nella libreria di sistema (eseguire come root)
# Installs the required R packages into the system library (run as root)
#   sudo Rscript deploy/install_packages.R
pkgs <- c("shiny", "bslib", "rmarkdown", "knitr")
lib  <- .Library.site[1]
if (is.na(lib)) lib <- .libPaths()[1]
install.packages(pkgs, lib = lib, repos = "https://cloud.r-project.org")
for (p in pkgs) cat(sprintf("%-10s %s\n", p, as.character(packageVersion(p, lib.loc = lib))))
if (packageVersion("bslib") < "0.5.0") stop("bslib >= 0.5 richiesto / required")
cat("pandoc:", if (rmarkdown::pandoc_available()) as.character(rmarkdown::pandoc_version())
               else "NON TROVATO / NOT FOUND (sudo apt install pandoc)", "\n")
