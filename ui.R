
# ==============================================================================
# UI
# ==============================================================================
ui <- page_navbar(
  title = "goSorensen ProAnalytics",
  id = "main_nav",
  theme = bs_theme(version = 5, bootswatch = "yeti", primary = "#1A3B5C", secondary = "#18BC9C"),
  
  header = tagList(
    useShinyjs(),
    tags$head(tags$style(HTML("
      body { background-color: #f8f9fa; }
      /* Mejoras visuales para las pestañas de navegación */
      .nav-pills .nav-link.active, .nav-tabs .nav-link.active, .bslib-navs .nav-link.active { 
          background-color: #1A3B5C !important; 
          color: white !important; 
          font-weight: bold;
      }
      .nav-link { color: #1A3B5C; }
      .nav-link:hover { color: #18BC9C; }
      .wizard-step { background-color: white; border-radius: 10px; padding: 15px; margin-bottom: 15px; border-left: 5px solid #1A3B5C; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
      .step-header { font-weight: bold; color: #1A3B5C; border-bottom: 2px solid #18BC9C; margin-bottom: 15px; }
      .card-header { font-weight: bold; text-transform: uppercase; letter-spacing: 0.5px; }
    ")))
  ),
  
  sidebar = sidebar(
    title = "Panel de Control",
    width = 350,
    
    selectInput("data_source_type", "1. Origen de Datos:", 
                choices = c("Bases de Datos de Ejemplo" = "example", "Cargar mis propios datos" = "user")),
    
    conditionalPanel(
      condition = "input.data_source_type == 'example'",
      selectInput("dataset_choice", "Seleccione Base de Datos:", choices = c("allOncoGeneLists", "pbtGeneLists"))
    ),
    
    uiOutput("list_selector_ui"),
    hr(),
    
    accordion(
      open = "params_go",
      accordion_panel(
        "Configuración GO", icon = icon("dna"), id = "params_go",
        selectInput("ex_onto", "Ontología:", choices = c("BP", "CC", "MF")),
        numericInput("ex_golevel", "Nivel GO:", value = 4, min = 3, max = 10),
        selectInput("org_package", "Organismo (Anotación):", 
                    choices = c("Humano" = "org.Hs.eg.db", "Ratón" = "org.Mm.eg.db", "Rata" = "org.Rn.eg.db"))
      ),
      accordion_panel(
        "Parámetros del Test", icon = icon("vial"), id = "params_test",
        numericInput("ex_d0", "Límite d0:", value = 0.4444, step = 0.01),
        numericInput("ex_conf", "Confianza:", value = 0.95, min = 0.8, max = 0.99),
        checkboxInput("ex_boot", "Usar Bootstrap", FALSE),
        conditionalPanel(
          condition = "input.ex_boot == true",
          numericInput("ex_nboot", "N° Simulaciones:", 10000, min = 1000)
        )
      )
    ),
    
    actionButton("run_analysis", "Ejecutar / Actualizar", class = "btn-primary w-100 mt-3", icon = icon("play"))
  ),
  
  # ==============================================================================
  # PESTAÑA 1
  # GESTIÓN DE DATOS
  # ==============================================================================
  nav_panel("Gestión de Datos", icon = icon("database"),
            div(class = "fade-in",
                conditionalPanel(
                  condition = "input.data_source_type == 'user'",
                  h3(class = "step-header", "Asistente de Importación y Conversión de IDs"),
                  layout_columns(
                    col_widths = c(4, 8),
                    div(class = "wizard-step",
                        h5("1. Carga de Archivo"),
                        fileInput("user_file", NULL, accept = c(".csv", ".xlsx", ".xls", ".txt")),
                        radioButtons("file_sep", "Separador:", choices = c("Coma" = ",", "Punto y coma" = ";", "Tab" = "\t"), inline = TRUE),
                        
                        hr(),
                        h5("2. Mapeo de Columnas"),
                        radioButtons("data_format", "Formato:", 
                                     choices = c("Ancho (columnas = listas)" = "wide", "Largo (columna de grupo)" = "long")),
                        uiOutput("user_mapping_ui"),
                        
                        hr(),
                        h5("3. Conversión de IDs"),
                        selectInput("user_keytype", "Tipo de ID en tu archivo:", 
                                    choices = c("SYMBOL", "ENTREZID", "ENSEMBL", "UNIPROT", "REFSEQ", "ALIAS")),
                        helpText("Nota: Se convertirán automáticamente a ENTREZID para el análisis."),
                        
                        br(),
                        actionButton("confirm_user_data", "Validar, Convertir y Confirmar", class = "btn-success w-100", icon = icon("sync"))
                    ),
                    div(
                      card(
                        card_header("Vista Previa (Datos Originales)"), 
                        DTOutput("raw_data_preview") |> withSpinner()
                      ),
                      card(
                        card_header("Estado de la Homologación"), 
                        DTOutput("user_data_status") |> withSpinner()
                      )
                    )
                  )
                ),
                # Panel Dinámico (Se inyecta desde el server para controlar las sub-pestañas)
                uiOutput("dynamic_gene_explorer")
            )
  ),
  
  # ==============================================================================
  # PESTAÑA 2
  # TABLAS Y MATRIZ GO
  # ==============================================================================
  nav_panel("Tablas y Matriz GO", icon = icon("table-cells"),
            layout_columns(
              col_widths = c(4, 8),
              card(
                card_header("Tabla de Contingencia por Par"),
                div(class = "d-flex gap-2 mb-3", selectInput("cont_pair_1", "Lista A", choices = NULL), selectInput("cont_pair_2", "Lista B", choices = NULL)),
                uiOutput("contingency_html_output")
              ),
              card(
                card_header("Matriz de Enriquecimiento Lógico"), 
                DTOutput("enrich_matrix_dt")
              )
            )
  ),
  
  # ==============================================================================
  # PESTAÑA 3
  # TEST DE EQUIVALENCIA
  # ==============================================================================
  nav_panel("Test de Equivalencia", icon = icon("check-double"),
            layout_columns(
              col_widths = c(4, 8),
              card(
                card_header("Seleccionar Par a Evaluar"),
                div(class = "d-flex gap-2 mb-3", selectInput("test_pair_1", "Lista A", choices = NULL), selectInput("test_pair_2", "Lista B", choices = NULL))
              ),
              card(
                card_header("Resultados del Test"), 
                uiOutput("equiv_results_html_interactive") |> withSpinner()
              )
            )
  ),
  
  # ==============================================================================
  # PESTAÑA 4
  # DISIMILARIDAD (MDS)
  # ==============================================================================
  nav_panel("Disimilaridad (MDS)", icon = icon("project-diagram"),
            navset_pill(
              nav_panel("1. Matriz de Irrelevancia y Dendrograma", icon = icon("table"),
                        layout_columns(
                          col_widths = c(12, 12),
                          card(
                            full_screen = TRUE,
                            card_header("Matriz de Disimilaridades"),
                            DTOutput("dissimilarity_matrix_dt") |> withSpinner()
                          ),
                          card(
                            full_screen = TRUE,
                            card_header("Dendrograma de Agrupamiento Jerárquico"),
                            plotOutput("dendro_plot", height = "550px") |> withSpinner()
                          )
                        )
              ),
              nav_panel("2. Gráfico MDS y Términos GO", icon = icon("chart-pie"),
                        layout_columns(
                          col_widths = c(12, 12),
                          card(
                            full_screen = TRUE,
                            card_header("Gráfico MDS Interactivo"),
                            plotlyOutput("mds_plot", height = "550px") |> withSpinner()
                          ),
                          card(
                            full_screen = TRUE,
                            card_header("Términos GO Discriminantes"),
                            # SELECTOR DE DIMENSIÓN
                            div(style="max-width: 300px; margin-bottom: 15px;",
                                selectInput("mds_dim_target", "Seleccione Dimensión para Análisis:", 
                                            choices = c("Dimensión 1" = 1, "Dimensión 2" = 2))),
                            DTOutput("go_diff_table") |> withSpinner()
                          )
                        )
              )
            )
  )
)


