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

# ==============================================================================
# SERVER
# ==============================================================================
server <- function(input, output, session) {
  
  rv <- reactiveValues(
    active_gene_lists=NULL,
    tabla_cont=NULL,
    diss_mat=NULL,
    test_obj=NULL,
    params_core=NULL,
    user_confirmed_list=NULL,
    user_unmapped_list=NULL,
    user_data_ready=FALSE,
    mapping_stats=NULL,
    rescued_ids_report=NULL,
    mapping_trace=NULL,
    rescue_summary=NULL
  )
  
  # --- Lógica de Carga y Conversión ---
  
  user_raw_df <- reactive({
    req(input$user_file)
    ext <- tools::file_ext(input$user_file$name)
    tryCatch({
      if (ext %in% c("xls", "xlsx")) {
        readxl::read_excel(input$user_file$datapath)
      } else {
        # fill=TRUE y na.strings evitan pérdida de datos cuando las columnas tienen distinto tamaño
        read.csv(input$user_file$datapath, sep = input$file_sep, stringsAsFactors = FALSE, na.strings = c("", "NA", " "), fill = TRUE)
      }
    }, error = function(e) { showNotification("Error al leer archivo", type="error"); return(NULL) })
  })
  
  output$raw_data_preview <- renderDT({
    req(user_raw_df())
    # Activada paginación completa para mostrar todos los datos originales
    datatable(user_raw_df(), options = list(
      scrollX = TRUE, 
      pageLength = 10, 
      lengthMenu = c(10, 25, 50, 100),
      dom = 'lrtip'
    ))
  })
  
  output$user_mapping_ui <- renderUI({
    df <- user_raw_df()
    req(df)
    if(input$data_format == "long") {
      tagList(
        selectInput("col_gene", "Columna de Genes:", choices = colnames(df)), 
        selectInput("col_group", "Columna de Grupos:", choices = colnames(df))
      )
    } else { 
      helpText("Cada columna será tratada como una lista de genes independiente.") 
    }
  })
  
  # --- FUNCIÓN DE CONVERSIÓN MODIFICADA ---
  #----------------------------------------------------------
  # Mapeo híbrido robusto con rescate automático multi-ID
  #----------------------------------------------------------
  map_to_entrez <- function(
    genes,
    db_pkg,
    source_type,
    rescue_types=c(
      "SYMBOL",
      "ENSEMBL",
      "ALIAS",
      "UNIPROT",
      "REFSEQ"
    )
  ){
    
    db <- get(db_pkg)
    
    clean_genes <- unique(
      trimws(
        as.character(
          genes[!is.na(genes) & genes!=""]
        )
      )
    )
    
    if(length(clean_genes)==0){
      return(
        list(
          mapped=character(0),
          unmapped=character(0),
          rescued=NULL,
          trace=NULL
        )
      )
    }
    
    #################################################
    # ENTREZ directo
    #################################################
    
    if(source_type=="ENTREZID"){
      
      trace_df <- data.frame(
        Original_ID=clean_genes,
        Mapping_Method="Directo",
        Detected_Type="ENTREZID",
        ENTREZID=clean_genes,
        MultiMatch="No",
        stringsAsFactors=FALSE
      )
      
      return(
        list(
          mapped=clean_genes,
          unmapped=character(0),
          rescued=NULL,
          trace=trace_df
        )
      )
      
    }
    
    #################################################
    # Mapeo principal
    #################################################
    
    primary_map <- tryCatch(
      mapIds(
        db,
        keys=clean_genes,
        column="ENTREZID",
        keytype=source_type,
        multiVals="first"
      ),
      error=function(e)
        setNames(
          rep(NA,length(clean_genes)),
          clean_genes
        )
    )
    
    mapped_primary <- as.character(
      unique(primary_map[!is.na(primary_map)])
    )
    
    trace_direct <- data.frame(
      Original_ID=names(primary_map)[!is.na(primary_map)],
      Mapping_Method="Directo",
      Detected_Type=source_type,
      ENTREZID=as.character(primary_map[!is.na(primary_map)]),
      MultiMatch="No",
      stringsAsFactors=FALSE
    )
    
    failed <- names(primary_map)[is.na(primary_map)]
    
    #################################################
    # Rescate multi keytype
    #################################################
    
    rescue_types <- setdiff(
      rescue_types,
      source_type
    )
    
    rescued_ids <- c()
    
    rescue_log <- data.frame(
      Original_ID=character(),
      Mapping_Method=character(),
      Detected_Type=character(),
      ENTREZID=character(),
      MultiMatch=character(),
      stringsAsFactors=FALSE
    )
    
    if(length(failed)>0){
      
      for(kt in rescue_types){
        
        ids_found <- tryCatch(
          mapIds(
            db,
            keys=failed,
            column="ENTREZID",
            keytype=kt,
            multiVals="first"
          ),
          error=function(e)
            setNames(
              rep(NA,length(failed)),
              failed
            )
        )
        
        hit <- !is.na(ids_found)
        
        if(any(hit)){
          
          tmp <- data.frame(
            Original_ID=names(ids_found)[hit],
            Mapping_Method="Rescatado",
            Detected_Type=kt,
            ENTREZID=as.character(ids_found[hit]),
            MultiMatch="No",
            stringsAsFactors=FALSE
          )
          
          rescue_log <- rbind(
            rescue_log,
            tmp
          )
          
          rescued_ids <- c(
            rescued_ids,
            as.character(ids_found[hit])
          )
          
          failed <- setdiff(
            failed,
            names(ids_found)[hit]
          )
          
        }
        
        if(length(failed)==0) break
        
      }
      
    }
    
    mapped_all <- unique(
      c(
        mapped_primary,
        rescued_ids
      )
    )
    
    trace_all <- rbind(
      trace_direct,
      rescue_log
    )
    
    return(
      list(
        mapped=mapped_all,
        unmapped=failed,
        rescued=rescue_log,
        trace=trace_all
      )
    )
    
  }
  
  observeEvent(input$confirm_user_data, {
    df <- user_raw_df()
    req(df, input$org_package)
    
    withProgress(message = "Convirtiendo IDs a EntrezID...", value = 0, {
      
      raw_lists <- if(input$data_format == "long") split(df[[input$col_gene]], df[[input$col_group]]) else as.list(df)
      incProgress(0.5, detail = "Mapeando contra base de datos...")
      
      map_results <- lapply(raw_lists, function(g) map_to_entrez(g, input$org_package, input$user_keytype))
      
      rv$mapping_trace <- do.call(
        rbind,
        lapply(
          names(map_results),
          function(nm){
            
            x <- map_results[[nm]]$trace
            
            if(is.null(x)) return(NULL)
            
            x$Lista <- nm
            x
            
          }
        )
      )
      
      rv$rescued_ids_report <- do.call(
        rbind,
        lapply(names(map_results), function(nm){
          
          x <- map_results[[nm]]$rescued
          
          if(is.null(x) || nrow(x)==0) return(NULL)
          
          x$Lista <- nm
          x
        })
      )
      
      if(!is.null(rv$rescued_ids_report)){
        
        rv$rescue_summary <- as.data.frame(
          table(
            rv$rescued_ids_report$Detected_Type
          )
        )
        
        colnames(rv$rescue_summary) <- c(
          "Tipo_ID_Rescate",
          "Frecuencia"
        )
        
      }
      
      rv$user_confirmed_list <- lapply(map_results, `[[`, "mapped")
      rv$user_unmapped_list  <- lapply(map_results, `[[`, "unmapped")
      rv$user_data_ready     <- TRUE # Activamos bandera para la UI
      
      rv$mapping_stats <- data.frame(
        Lista=names(raw_lists),
        Originales=sapply(raw_lists,function(x)
          length(unique(x[!is.na(x) & x!=""])
          )),
        Mapeados_Finales=sapply(
          rv$user_confirmed_list,
          length
        ),
        Rescatados=sapply(
          map_results,
          function(x)
            if(is.null(x$rescued)) 0
          else nrow(x$rescued)
        ),
        No_Mapeados_Finales=sapply(
          rv$user_unmapped_list,
          length
        ),
        check.names=FALSE
      )
    })
    showNotification("Homologación completada con éxito.", type = "message")
  })
  
  output$user_data_status <- renderDT({
    req(rv$mapping_stats)
    datatable(
      rv$mapping_stats,
      rownames = FALSE,
      options = list(
        dom = 't',
        pageLength = 10,
        scrollX = TRUE
      ),
      class = 'cell-border stripe hover compact'
    )
  })
  
  # --- PESTAÑAS DINÁMICAS (EXPLORADOR DE GENES) ---
  output$dynamic_gene_explorer <- renderUI({
    
    is_ready <- (input$data_source_type == 'example') || 
      (input$data_source_type == 'user' && rv$user_data_ready)
    
    req(is_ready)
    
    tabs <- list(
      nav_panel(
        "Mapeados con Éxito (EntrezID)",
        uiOutput("genes_lists_view")
      )
    )
    
    if(input$data_source_type=="user"){
      
      tabs[[length(tabs)+1]] <- nav_panel(
        "Genes No Mapeados",
        uiOutput("unmapped_genes_view")
      )
      
      tabs[[length(tabs)+1]] <- nav_panel(
        "Trazabilidad de Rescate",
        card(
          card_header("Detalle de Genes Rescatados (solo rescates automáticos)"),
          
          div(
            style="
      background:#eef7fb;
      border-left:4px solid #18BC9C;
      padding:12px;
      margin-bottom:15px;
      border-radius:8px;",
            
            strong("Nota: "),
            "Los genes rescatados son identificadores que no lograron mapearse con el tipo de ID principal seleccionado, ",
            "pero fueron recuperados automáticamente mediante equivalencias en otros sistemas de identificación ",
            "(por ejemplo SYMBOL, ENSEMBL, UNIPROT o ALIAS), evitando pérdida de información para el análisis."
          ),
          
          DTOutput("rescue_trace_table")
        )
      )
      
    }
    
    do.call(
      navset_card_underline,
      c(list(title = "Explorador de Genes"), tabs)
    )
    
  })
  
  output$list_selector_ui <- renderUI({
    choices <- if(input$data_source_type == "example") {
      data(list = input$dataset_choice, package = "goSorensen"); names(get(input$dataset_choice))
    } else { req(rv$user_confirmed_list); names(rv$user_confirmed_list) }
    selectInput("ex_lists", "2. Seleccione Listas:", choices = choices, multiple = TRUE, selected = choices[1:min(length(choices), 4)])
  })
  
  output$rescue_trace_table <- renderDT({
    
    req(rv$rescued_ids_report)
    
    if(is.null(rv$rescued_ids_report) || nrow(rv$rescued_ids_report)==0){
      
      return(
        datatable(
          data.frame(
            Mensaje="No hubo genes rescatados; todos fueron mapeados por el ID principal."
          ),
          rownames=FALSE,
          options=list(dom='t')
        )
      )
      
    }
    
    rescates <- rv$rescued_ids_report[
      order(
        rv$rescued_ids_report$Lista,
        rv$rescued_ids_report$Detected_Type
      ),
      c(
        "Lista",
        "Original_ID",
        "Detected_Type",
        "ENTREZID"
      )
    ]
    
    colnames(rescates) <- c(
      "Lista",
      "ID_Original",
      "Tipo_ID_Rescate",
      "ENTREZID_Final"
    )
    
    datatable(
      rescates,
      extensions="Buttons",
      rownames=FALSE,
      options=list(
        scrollX=TRUE,
        pageLength=15,
        dom='Bfrtip',
        buttons=c(
          'copy',
          'csv',
          'excel'
        )
      )
    )
    
  })
  
  
  # --- SINCRONIZACIÓN DE SELECTORES ---
  observeEvent(input$ex_lists, {
    req(input$ex_lists)
    sel_1 <- if(!is.null(input$cont_pair_1) && input$cont_pair_1 %in% input$ex_lists) input$cont_pair_1 else input$ex_lists[1]
    updateSelectInput(session, "cont_pair_1", choices = input$ex_lists, selected = sel_1)
    
    sel_test_1 <- if(!is.null(input$test_pair_1) && input$test_pair_1 %in% input$ex_lists) input$test_pair_1 else input$ex_lists[1]
    updateSelectInput(session, "test_pair_1", choices = input$ex_lists, selected = sel_test_1)
  })
  
  observe({
    req(input$ex_lists, input$cont_pair_1)
    opciones_restantes <- setdiff(input$ex_lists, input$cont_pair_1)
    sel_2 <- if(!is.null(input$cont_pair_2) && input$cont_pair_2 %in% opciones_restantes) input$cont_pair_2 else opciones_restantes[1]
    updateSelectInput(session, "cont_pair_2", choices = opciones_restantes, selected = sel_2)
  })
  
  observe({
    req(input$ex_lists, input$test_pair_1)
    opciones_restantes <- setdiff(input$ex_lists, input$test_pair_1)
    sel_2 <- if(!is.null(input$test_pair_2) && input$test_pair_2 %in% opciones_restantes) input$test_pair_2 else opciones_restantes[1]
    updateSelectInput(session, "test_pair_2", choices = opciones_restantes, selected = sel_2)
  })
  
  observeEvent(input$cont_pair_1, {
    if(!is.null(input$test_pair_1) && input$cont_pair_1 != input$test_pair_1) {
      updateSelectInput(session, "test_pair_1", selected = input$cont_pair_1)
    }
  }, ignoreInit = TRUE)
  
  observeEvent(input$cont_pair_2, {
    if(!is.null(input$test_pair_2) && input$cont_pair_2 != input$test_pair_2) {
      updateSelectInput(session, "test_pair_2", selected = input$cont_pair_2)
    }
  }, ignoreInit = TRUE)
  
  observeEvent(input$test_pair_1, {
    if(!is.null(input$cont_pair_1) && input$test_pair_1 != input$cont_pair_1) {
      updateSelectInput(session, "cont_pair_1", selected = input$test_pair_1)
    }
  }, ignoreInit = TRUE)
  
  observeEvent(input$test_pair_2, {
    if(!is.null(input$cont_pair_2) && input$test_pair_2 != input$cont_pair_2) {
      updateSelectInput(session, "cont_pair_2", selected = input$test_pair_2)
    }
  }, ignoreInit = TRUE)
  
  # --- RENDER DE GENES ---
  output$genes_lists_view <- renderUI({
    req(input$ex_lists)
    listas_fuente <- if(input$data_source_type == "example") get(input$dataset_choice) else rv$user_confirmed_list
    listas <- listas_fuente[input$ex_lists]
    
    div(style = "display:grid; grid-template-columns:repeat(auto-fit, minmax(300px, 1fr)); gap:20px;", lapply(names(listas), function(nm) {
      accordion(accordion_panel(
        title = paste(nm, "(", length(listas[[nm]]), " IDs)"), 
        div(style = "max-height: 300px; overflow-y: auto; display:grid; grid-template-columns:repeat(auto-fill, minmax(60px, 1fr)); gap:5px; padding: 5px;", 
            lapply(listas[[nm]], function(g) div(style="background:#1A3B5C; color:white; font-size:10px; text-align:center; border-radius:3px;", g)))
      ))
    }))
  })
  
  output$unmapped_genes_view <- renderUI({
    req(rv$user_unmapped_list, input$ex_lists)
    listas <- rv$user_unmapped_list[input$ex_lists]
    
    div(style = "display:grid; grid-template-columns:repeat(auto-fit, minmax(300px, 1fr)); gap:20px;", lapply(names(listas), function(nm) {
      accordion(accordion_panel(
        title = HTML(paste0("<span style='color:#E74C3C;'>", nm, " (", length(listas[[nm]]), " No Mapeados)</span>")), 
        div(style = "max-height: 300px; overflow-y: auto; display:grid; grid-template-columns:repeat(auto-fill, minmax(80px, 1fr)); gap:5px; padding: 5px;", 
            if(length(listas[[nm]]) > 0) {
              lapply(listas[[nm]], function(g) div(style="background:#E74C3C; color:white; font-size:10px; text-align:center; border-radius:3px; word-break: break-all;", g))
            } else {
              p("Todos los genes mapeados exitosamente.")
            })
      ))
    }))
  })
  
  # --- EJECUCIÓN ---
  observeEvent(input$run_analysis, {
    req(length(input$ex_lists) >= 2)
    listas_fuente <- if(input$data_source_type == "example") get(input$dataset_choice) else rv$user_confirmed_list
    listas_obj <- listas_fuente[input$ex_lists]
    current_core <- list(src = input$data_source_type, db = input$dataset_choice, lists = sort(input$ex_lists), onto = input$ex_onto, level = input$ex_golevel, org = input$org_package)
    
    withProgress(message = "Calculando Enriquecimiento GO...", value = 0, {
      if (is.null(rv$tabla_cont) || !identical(rv$params_core, current_core)) {
        univ <- keys(get(input$org_package), keytype = "ENTREZID")
        incProgress(0.2, detail = "Tablas de contingencia...")
        rv$tabla_cont <- buildEnrichTable(listas_obj, geneUniverse = univ, orgPackg = input$org_package, onto = input$ex_onto, GOLevel = input$ex_golevel)
        incProgress(0.5, detail = "Matriz de Disimilaridades...")
        rv$diss_mat <- sorenThreshold(rv$tabla_cont, trace = FALSE)
        incProgress(0.8, detail = "Tests de equivalencia globales...")
        rv$test_obj <- equivTestSorensen(rv$tabla_cont, d0 = input$ex_d0, conf.level = input$ex_conf, boot = input$ex_boot, nboot = input$ex_nboot)
        rv$params_core <- current_core
      } else {
        incProgress(0.5, detail = "Actualizando parámetros del test...")
        rv$test_obj <- upgrade(rv$test_obj, d0 = input$ex_d0, conf.level = input$ex_conf, boot = input$ex_boot, nboot = input$ex_nboot)
      }
    })
  })
  
  # --- RENDERS DE RESULTADOS ---
  output$contingency_html_output <- renderUI({
    req(rv$tabla_cont, input$cont_pair_1, input$cont_pair_2)
    tab <- rv$tabla_cont[[input$cont_pair_1]][[input$cont_pair_2]]
    if(is.null(tab)) tab <- rv$tabla_cont[[input$cont_pair_2]][[input$cont_pair_1]]
    if(is.null(tab)) return(HTML("<p class='text-danger'>Tabla no disponible.</p>"))
    format_contingency_html(tab, input$cont_pair_1, input$cont_pair_2)
  })
  
  output$enrich_matrix_dt <- renderDT({
    req(rv$tabla_cont)
    datatable(as.data.frame(attr(rv$tabla_cont, "enriched")), 
              options = list(
                scrollX = TRUE, 
                pageLength = 10, 
                lengthMenu = c(10, 25, 50, 100, 500),
                dom = 'lfrtip'
              ))
  })
  
  output$equiv_results_html_interactive <- renderUI({
    req(rv$test_obj, input$test_pair_1, input$test_pair_2)
    result_pair <- rv$test_obj[[input$test_pair_1]][[input$test_pair_2]]
    if(is.null(result_pair)) result_pair <- rv$test_obj[[input$test_pair_2]][[input$test_pair_1]]
    if(is.null(result_pair)) return(HTML("<div class='alert alert-warning text-center mt-3'>No se encontró resultado.</div>"))
    return(format_equiv_html(result_pair, input$test_pair_1, input$test_pair_2))
  })
  
  output$dissimilarity_matrix_dt <- renderDT({
    req(rv$diss_mat)
    mat <- as.matrix(rv$diss_mat)
    datatable(round(mat, 4), options = list(scrollX = TRUE, dom = 't', ordering = FALSE), class = 'cell-border hover compact') |>
      formatStyle(columns = colnames(mat), backgroundColor = styleColorBar(range(mat, na.rm = TRUE), '#e0f2f1'), backgroundSize = '100% 90%', backgroundRepeat = 'no-repeat', backgroundPosition = 'center')
  })
  
  output$dendro_plot <- renderPlot({
    req(rv$diss_mat)
    clust.threshold <- hclustThreshold(rv$diss_mat)
    par(mar = c(3, 4, 2, 1), cex = 1.1)
    plot(clust.threshold, main = "", xlab = "", sub = "", ylab = "Altura (Disimilaridad)", col = "#1A3B5C", col.main = "#1A3B5C", lwd = 2)
  })
  
  output$mds_plot <- renderPlotly({
    req(rv$diss_mat)
    diss <- as.matrix(rv$diss_mat)
    n <- nrow(diss)
    k_dim <- min(2, n - 1)
    
    mds_res <- cmdscale(diss, k = k_dim, eig = TRUE)
    eigenvalues <- mds_res$eig
    positive_eigen <- eigenvalues[eigenvalues > 0]
    total_var <- sum(positive_eigen)
    
    var_dim1 <- if(length(positive_eigen) >= 1) round((positive_eigen[1] / total_var) * 100, 1) else 0
    var_dim2 <- if(length(positive_eigen) >= 2) round((positive_eigen[2] / total_var) * 100, 1) else 0
    
    df <- as.data.frame(mds_res$points)
    colnames(df)[1:k_dim] <- paste0("Dim", 1:k_dim)
    if(k_dim == 1) df$Dim2 <- 0
    df$Lista <- rownames(diss)
    
    p <- ggplot(df, aes(x = Dim1, y = Dim2, text = Lista)) + 
      geom_hline(yintercept = 0, linetype = "dashed", color = "gray80") +
      geom_vline(xintercept = 0, linetype = "dashed", color = "gray80") +
      geom_point(size = 4, color = "#18BC9C", alpha = 0.9) + 
      geom_text_repel(aes(label = Lista), fontface = "bold", color = "#1A3B5C") + 
      theme_minimal() + labs(x = paste0("Dimensión 1 (", var_dim1, "%)"), y = paste0("Dimensión 2 (", var_dim2, "%)"))
    
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })
  
  # LÓGICA DINÁMICA DE TÉRMINOS GO ENRIQUECIDOS PARA DOS DIMENSIONES
  output$go_diff_table <- renderDT({
    req(rv$diss_mat, rv$tabla_cont, input$mds_dim_target)
    
    diss <- as.matrix(rv$diss_mat)
    n_lists <- nrow(diss)
    target_dim <- as.numeric(input$mds_dim_target)
    
    if(n_lists < 3 && target_dim == 2) {
      return(datatable(data.frame(Aviso = "La Dimensión 2 requiere al menos 3 listas para ser calculada."), rownames = FALSE))
    }
    
    mds_res <- cmdscale(diss, k = min(2, n_lists - 1))
    coords <- mds_res[, target_dim]
    
    # paso1: Split axis (20% - 60% - 20%)
    prop <- c(0.2, 0.6, 0.2)
    sorted_coords <- sort(coords)
    rng <- range(sorted_coords)
    cutpoints <- (cumsum(prop)[1:2] * diff(rng)) + rng[1]
    
    lleft <- names(coords[coords < cutpoints[1]])
    lright <- names(coords[coords > cutpoints[2]])
    
    # estructural
    if(length(lleft) == 0) lleft <- names(sorted_coords)[1]
    if(length(lright) == 0) lright <- names(sorted_coords)[length(sorted_coords)]
    
    # paso2: Extract Enrichment Matrices
    enr_mat <- attr(rv$tabla_cont, "enriched")
    tableleft <- enr_mat[, lleft, drop = FALSE]
    tableright <- enr_mat[, lright, drop = FALSE]
    
    # paso3: Compute Means and Variances
    mean_sd <- function(x) { c("mean" = mean(x), "sd" = ifelse(length(x) <= 1, 0, sd(x))) }
    lmnsd <- apply(tableleft, 1, mean_sd)
    rmnsd <- apply(tableright, 1, mean_sd)
    
    # paso4 Establish Statistic (t_stat)
    nl <- ncol(tableleft)
    nr <- ncol(tableright)
    t_stat <- abs(lmnsd[1, ] - rmnsd[1, ]) / sqrt((((lmnsd[2, ] / nl) + (rmnsd[2, ] / nr))) + 0.00000001)
    
    # paso5: Select Max Statistics 
    top_indices <- order(t_stat, decreasing = TRUE)[1:15]
    result_vals <- t_stat[top_indices]
    
    res <- data.frame(
      GO_ID = names(result_vals), 
      Stat = as.numeric(result_vals), 
      Descripcion = sapply(names(result_vals), get_go_description, USE.NAMES = FALSE)
    )
    
    datatable(res, rownames = FALSE, 
              options = list(pageLength = 10, dom = 't', scrollX = TRUE), 
              selection = 'none', class = 'cell-border stripe hover') |>
      formatRound('Stat', 4) |>
      formatStyle('Stat', 
                  background = styleColorBar(range(res$Stat), '#18BC9C'), 
                  backgroundSize = '98% 80%', backgroundRepeat = 'no-repeat', backgroundPosition = 'center')
  })
}
