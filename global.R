# ==============================================================================
# goSorensen ProAnalytics V 2.4
# ==============================================================================

library(shiny)
library(bslib)
library(shinyjs)
library(DT)
library(goSorensen)
library(AnnotationDbi)
library(org.Hs.eg.db)
library(org.Mm.eg.db) 
library(org.Rn.eg.db) 
library(GO.db)
library(ggplot2)
library(ggrepel)
library(plotly)
library(readxl)
library(shinycssloaders)
library(htmltools)

# --- Funciones Auxiliares ---
format_contingency_html <- function(tab, nameA, nameB) {
  if (is.null(tab)) return(NULL)
  tab <- as.matrix(tab)
  
  dn_names <- names(dimnames(tab))
  if (!is.null(dn_names) && length(dn_names) == 2) {
    row_label <- dn_names[1]
    col_label <- dn_names[2]
  } else {
    row_label <- paste("Enriquecido en", nameA)
    col_label <- paste("Enriquecido en", nameB)
  }
  
  v11 <- tab["TRUE",  "TRUE"]
  v12 <- tab["TRUE",  "FALSE"]
  v21 <- tab["FALSE", "TRUE"]
  v22 <- tab["FALSE", "FALSE"]
  
  HTML(paste0(
    "<div class='table-responsive' style='margin-top:10px;'>",
    "<table class='table table-sm table-bordered table-hover' style='width:auto;'>",
    "<thead class='table-dark'>",
    "<tr><th></th><th colspan='2' class='text-center'>", col_label, "</th></tr>",
    "<tr><th>", row_label, "</th><th class='text-center'>SÍ</th><th class='text-center'>NO</th></tr>",
    "</thead>",
    "<tbody>",
    "<tr><th class='bg-light'>SÍ</th><td class='text-center'>", v11, "</td><td class='text-center'>", v12, "</td></tr>",
    "<tr><th class='bg-light'>NO</th><td class='text-center'>", v21, "</td><td class='text-center'>", v22, "</td></tr>",
    "</tbody>",
    "</table></div>"
  ))
}

get_go_description <- function(go_id) {
  tryCatch({
    desc <- Term(GOTERM[[go_id]])
    if(is.null(desc) || is.na(desc)) return("Descripción no disponible")
    return(desc)
  }, error = function(e) return("No encontrado en GO.db"))
}

format_equiv_html <- function(test_obj, nameA, nameB) {
  est  <- test_obj$estimate
  se   <- attr(test_obj$estimate, "se")
  ci   <- test_obj$conf.int
  stat <- test_obj$statistic
  pval <- test_obj$p.value
  method <- test_obj$method
  
  pval_color <- ifelse(pval < 0.05, "#E74C3C", "#2C3E50")
  pval_format <- ifelse(pval < 0.0001, "< 0.0001", signif(pval, 4))
  
  HTML(paste0(
    "<div class='card shadow-sm border-0' style='background:#ffffff; border-radius:12px; font-family:Arial;'>",
    "<div class='card-body p-4'>",
    "<h4 style='color:#1A3B5C; margin-top:0; font-weight:bold;'>",
    "Comparación: <span style='color:#18BC9C;'>", nameA, "</span> vs <span style='color:#18BC9C;'>", nameB, "</span>",
    "</h4>",
    "<p class='text-muted small mb-3'><i>", method, "</i></p>",
    "<hr>",
    "<div class='row mb-3 text-center'>",
    "  <div class='col-sm-6'>",
    "    <h6 class='text-uppercase text-muted mb-1'>Disimilaridad</h6>",
    "    <span style='font-size:28px; color:#18BC9C; font-weight:bold;'>", round(est, 4), "</span>",
    "  </div>",
    "  <div class='col-sm-6'>",
    "    <h6 class='text-uppercase text-muted mb-1'>P-Valor</h6>",
    "    <span style='font-size:28px; color:", pval_color, "; font-weight:bold;'>", pval_format, "</span>",
    "  </div>",
    "</div>",
    "<hr>",
    "<div style='font-size: 16px; color: #34495e;'>",
    "<p style='margin-bottom:8px;'><b>Error Estándar:</b> ", round(se, 4), "</p>",
    "<p style='margin-bottom:8px;'><b>Estadístico Z:</b> ", round(stat, 4), "</p>",
    "<p style='margin-bottom:0;'><b>Intervalo de Confianza (95%):</b> [ ", round(ci[1], 4), " , ", round(ci[2], 4), " ]</p>",
    "</div>",
    "</div></div>"
  ))
}
