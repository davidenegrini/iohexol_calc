# =============================================================================
# App Shiny - mGFR con ioexolo ed eGFR (EKFC, CKD-EPI 2021)
# Avvio locale (senza RStudio):  Rscript -e 'shiny::runApp("it", port = 3838)'
# Pubblicazione su Shiny Server: vedere la cartella deploy/ nella radice del repository
# Pacchetti richiesti: shiny, bslib (>= 0.5), rmarkdown, knitr
# Il report HTML viene generato da rmarkdown, che richiede pandoc installato
# =============================================================================
library(shiny)
library(bslib)

# Se il server gira con una locale non UTF-8 (es. LANG=C), lettere accentate e
# simboli (µ, ², ≥) nel report diventerebbero "<U+00E0>": si passa a una locale UTF-8
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  for (loc in c("C.UTF-8", "C.utf8", "en_US.UTF-8", "it_IT.UTF-8"))
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
}

DIR_APP <- normalizePath(".")   # cartella dell'app (fissata all'avvio)

# parse(encoding = "UTF-8") invece di source(): funziona anche se il server
# gira con una locale non UTF-8 (es. LANG=C), dove source() fallirebbe
carica <- function(f) eval(parse(file.path(DIR_APP, f), encoding = "UTF-8"), envir = parent.frame())
carica("R/calcoli.R")
carica("R/grafico.R")

campo_ora <- function(id, label, value = "") textInput(id, label, value, placeholder = "HH:MM")

ui <- page_sidebar(
  title = "mGFR ioexolo – calcolo e report",
  theme = bs_theme(bootswatch = "flatly"),
  sidebar = sidebar(
    width = 430,
    accordion(
      open = c("Paziente", "Laboratorio", "Prelievi ioexolo"),
      accordion_panel("Paziente",
        textInput("richiesta", "N. richiesta"),
        layout_columns(textInput("cognome", "Cognome"), textInput("nome", "Nome")),
        layout_columns(
          radioButtons("sesso", "Sesso", c("M", "F"), inline = TRUE, selected = character(0)),
          suppressWarnings(dateInput("data_nascita", "Data di nascita", value = NA, format = "dd/mm/yyyy",
                    language = "it", startview = "decade"))),
        layout_columns(numericInput("peso", "Peso (kg)", NA, min = 1, step = 0.1),
                       numericInput("altezza", "Altezza (cm)", NA, min = 30, step = 1)),
        textAreaInput("quesito", "Quesito clinico", rows = 2)
      ),
      accordion_panel("Laboratorio",
        dateInput("data_prelievo", "Data prelievo", value = Sys.Date(),
                  format = "dd/mm/yyyy", language = "it"),
        layout_columns(numericInput("scr", "Creatinina (mg/dL)", NA, min = 0, step = 0.01),
                       numericInput("scys", "Cistatina C (mg/L)", NA, min = 0, step = 0.01))
      ),
      accordion_panel("Prelievi ioexolo",
        layout_columns(
          numericInput("dose_ug", "Dose iniettata (µg)", DOSE_DEFAULT_UG, min = 0, step = 1000),
          campo_ora("t0", "T0 iniezione")),
        helpText("Default 3.235.000 µg = 5 mL Omnipaque 300. Inserire da 2 a 5 prelievi; le righe vuote vengono ignorate."),
        lapply(1:5, function(i) layout_columns(
          campo_ora(paste0("ora", i), paste0("T", i, " ora")),
          numericInput(paste0("conc", i), paste0("IOEX", i, " (mg/L)"), NA, min = 0, step = 0.01)))
      )
    ),
    actionButton("pulisci", "Svuota modulo", icon = icon("eraser"), class = "btn-outline-secondary")
  ),

  layout_columns(
    col_widths = c(12, 7, 5, 12),
    uiOutput("box_avvisi"),
    card(card_header("Risultati"), tableOutput("tab_risultati")),
    card(card_header("Curva di decadimento"), plotOutput("grafico", height = 300)),
    card(card_header("Dettaglio prelievi e passaggi"), tableOutput("tab_punti"),
         uiOutput("passaggi"))
  ),
  card(
    card_header("Report"),
    downloadButton("report_html", "Scarica report HTML", class = "btn-primary"),
    helpText("Il report HTML si apre in qualsiasi browser e si stampa in PDF da lì.")
  )
)

server <- function(input, output, session) {

  # ---- svuota modulo --------------------------------------------------------
  riempi <- function(e) {
    updateTextInput(session, "richiesta", value = e$richiesta %||% "")
    updateTextInput(session, "cognome", value = e$cognome %||% "")
    updateTextInput(session, "nome", value = e$nome %||% "")
    updateRadioButtons(session, "sesso", selected = e$sesso %||% character(0))
    suppressWarnings(updateDateInput(session, "data_nascita", value = e$data_nascita %||% NA))
    updateDateInput(session, "data_prelievo", value = e$data_prelievo %||% Sys.Date())
    updateNumericInput(session, "peso", value = e$peso %||% NA)
    updateNumericInput(session, "altezza", value = e$altezza %||% NA)
    updateNumericInput(session, "scr", value = e$scr %||% NA)
    updateNumericInput(session, "scys", value = e$scys %||% NA)
    updateNumericInput(session, "dose_ug", value = e$dose_ug %||% DOSE_DEFAULT_UG)
    updateTextInput(session, "t0", value = e$t0 %||% "")
    updateTextAreaInput(session, "quesito", value = e$quesito %||% "")
    for (i in 1:5) {
      o <- if (is.null(e$ore)) NA else e$ore[i]
      cc <- if (is.null(e$conc)) NA else e$conc[i]
      updateTextInput(session, paste0("ora", i), value = if (is.na(o)) "" else o)
      updateNumericInput(session, paste0("conc", i), value = cc)
    }
  }
  observeEvent(input$pulisci, {
    riempi(list())
  })

  # ---- input raccolti in una lista -----------------------------------------
  dati <- reactive({
    nn <- function(x) if (is.null(x) || length(x) == 0) NA else x
    list(
      richiesta = input$richiesta, cognome = input$cognome, nome = input$nome,
      sesso = nn(input$sesso), data_nascita = nn(input$data_nascita),
      data_prelievo = nn(input$data_prelievo),
      peso = nn(input$peso), altezza = nn(input$altezza),
      scr = nn(input$scr), scys = nn(input$scys),
      dose_ug = nn(input$dose_ug), t0 = input$t0,
      ore = vapply(1:5, function(i) input[[paste0("ora", i)]] %||% "", ""),
      conc = vapply(1:5, function(i) as.numeric(nn(input[[paste0("conc", i)]])), 0),
      quesito = input$quesito
    )
  })
  ris <- reactive(calcola_tutto(dati()))

  # ---- output a video ------------------------------------------------------
  output$box_avvisi <- renderUI({
    r <- ris(); err <- c(r$mgfr$errori, r$errori_egfr); avv <- c(r$mgfr$avvisi, r$avvisi_egfr)
    if (is.na(r$eta)) err <- c(err, "Età non calcolabile: inserire data di nascita e data prelievo.")
    tagList(
      if (length(err)) div(class = "alert alert-danger", HTML(paste(err, collapse = "<br>"))),
      if (length(avv)) div(class = "alert alert-warning", HTML(paste(avv, collapse = "<br>")))
    )
  })

  output$tab_risultati <- renderTable({
    r <- ris(); t <- tabella_risultati(r)
    t$`Classe KDIGO` <- c("", vapply(t$Valore[-1], classe_kdigo, ""))
    t$`Classe KDIGO`[is.na(t$`Classe KDIGO`)] <- ""
    t$Valore <- fmt(t$Valore)
    t
  }, striped = TRUE, align = "lrll")

  output$grafico <- renderPlot(grafico_decadimento(ris()$mgfr))

  output$tab_punti <- renderTable({
    p <- ris()$mgfr$punti
    data.frame(Prelievo = p$prelievo, Ora = p$ora,
               `Min da T0` = fmt(p$t_min, 0), `mg/L` = fmt(p$conc, 2), `µmol/L` = fmt(p$conc_umol, 2),
               `ln C` = fmt(p$ln_conc, 4), Usato = ifelse(p$usato, "sì", "no"),
               check.names = FALSE)
  }, striped = TRUE, align = "llrrrrc")

  output$passaggi <- renderUI({
    r <- ris(); mg <- r$mgfr
    if (is.null(mg$c0)) return(NULL)
    tags$ul(
      tags$li(sprintf("Età %s anni · BSA %s m²", fmt(r$eta, 0), fmt(r$bsa, 3))),
      tags$li(sprintf("Prelievi usati: %d%s", mg$n_punti,
                      if (is.na(mg$r2)) "" else sprintf(" · R² = %s", fmt(mg$r2, 4)))),
      tags$li(sprintf("C0 = %s mg/L · k = %s min⁻¹ · emivita %s min",
                      fmt(mg$c0, 2), formatC(mg$k, format = "e", digits = 4, decimal.mark = ","), fmt(mg$emivita_min, 0))),
      tags$li(sprintf("AUC = %s mg·min/L · CL = %s mL/min",
                      fmt(mg$auc, 0), fmt(mg$cl, 1))),
      tags$li(sprintf("Brøchner-Mortensen sulla CL assoluta: %s mL/min → normalizzata: %s mL/min/1,73 m²",
                      fmt(mg$gfr_abs, 1), fmt(mg$gfr_norm, 1)))
    )
  })

  # ---- report --------------------------------------------------------------
  nome_file <- function(ext) {
    d <- dati()
    base <- paste("mGFR", d$cognome, d$nome, format(come_data(d$data_prelievo), "%Y%m%d"), sep = "_")
    paste0(gsub("[^A-Za-z0-9_-]+", "", gsub(" ", "_", base)), ".", ext)
  }
  genera <- function(formato, file) {
    id <- showNotification("Generazione del report in corso…", duration = NULL)
    on.exit(removeNotification(id))
    tmp <- tempfile("report_"); dir.create(tmp)
    file.copy(file.path(DIR_APP, "report.Rmd"), tmp)
    out <- rmarkdown::render(file.path(tmp, "report.Rmd"), output_format = formato,
                             params = list(inp = dati(), dir_app = DIR_APP),
                             envir = new.env(), quiet = TRUE)
    file.copy(out, file, overwrite = TRUE)
  }
  output$report_html <- downloadHandler(function() nome_file("html"),
                                        function(file) genera("html_document", file))
}

shinyApp(ui, server)
