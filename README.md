# goSorensen ProAnalytics

## Plataforma interactiva para análisis de equivalencia funcional mediante el método goSorensen

---

## Descripción General

goSorensen ProAnalytics es una aplicación desarrollada en R Shiny para facilitar la implementación del método `goSorensen` mediante una interfaz gráfica moderna, interactiva y orientada a usuarios con experiencia limitada en programación en R.

La herramienta permite realizar análisis de equivalencia funcional entre listas génicas utilizando Gene Ontology (GO), integrando procedimientos de homologación automática de identificadores, análisis de disimilaridad funcional y visualización avanzada de resultados.

---

## Objetivo del Proyecto

Desarrollar un visualizador interactivo basado en R Shiny que permita implementar el método goSorensen de forma accesible, escalable y reproducible, reduciendo la complejidad técnica asociada al análisis bioinformático funcional.

---

## Características Principales

- Carga de datasets personalizados.
- Compatibilidad con múltiples formatos:
  - CSV
  - XLSX
  - XLS
  - TXT
- Conversión automática de identificadores génicos.
- Sistema de rescate multi-ID.
- Explorador interactivo de genes.
- Construcción automática de:
  - tablas de contingencia,
  - matrices GO,
  - matrices de disimilaridad.
- Test de equivalencia funcional.
- Bootstrap configurable.
- Visualización MDS interactiva.
- Dendrogramas jerárquicos.
- Identificación de términos GO discriminantes.
- Exportación y trazabilidad de resultados.

---

# Vista General de la Aplicación

## Gestión de Datos

[INSERTAR CAPTURA: Pantalla principal de carga y homologación de datos.]

---

## Tablas y Matriz GO

[INSERTAR CAPTURA: Tabla de contingencia y matriz de enriquecimiento.]

---

## Test de Equivalencia

[INSERTAR CAPTURA: Resultados estadísticos del test.]

---

## Disimilaridad y MDS

[INSERTAR CAPTURA: Visualización MDS y dendrograma.]

---

# Arquitectura del Proyecto

```text
.
├── app.R
├── global.R
├── ui.R
├── server.R
├── README.md
├── LICENSE
├── docs/
│   ├── manual_usuario_gosorensen.pdf
│   ├── manual_usuario_gosorensen.html
│   └── figuras/
├── data/
├── www/
└── renv/
```

---

# Requisitos

## Software

- R >= 4.4
- RStudio

## Paquetes requeridos

```r
install.packages(c(
  "shiny",
  "bslib",
  "DT",
  "plotly",
  "ggplot2",
  "ggrepel",
  "readxl",
  "htmltools",
  "shinyjs",
  "shinycssloaders"
))
```

## Paquetes Bioconductor

```r
if (!require("BiocManager"))
  install.packages("BiocManager")

BiocManager::install(c(
  "goSorensen",
  "AnnotationDbi",
  "GO.db",
  "org.Hs.eg.db",
  "org.Mm.eg.db",
  "org.Rn.eg.db"
))
```

---

# Ejecución de la Aplicación

## Clonar repositorio

```bash
git clone https://github.com/USUARIO/goSorensen-ProAnalytics.git
```

---

## Abrir proyecto en RStudio

```r
setwd("goSorensen-ProAnalytics")
```

---

## Ejecutar aplicación

```r
shiny::runApp()
```

---

# Flujo General de Uso

1. Cargar dataset.
2. Seleccionar formato de datos.
3. Configurar tipo de identificador.
4. Ejecutar homologación automática.
5. Seleccionar listas génicas.
6. Configurar ontología GO.
7. Ejecutar análisis.
8. Interpretar resultados.

---

# Tipos de IDs Compatibles

- SYMBOL
- ENTREZID
- ENSEMBL
- UNIPROT
- REFSEQ
- ALIAS

---

# Organismos Compatibles

- Humano (`org.Hs.eg.db`)
- Ratón (`org.Mm.eg.db`)
- Rata (`org.Rn.eg.db`)

---

# Metodología Implementada

La aplicación implementa procedimientos basados en:

- enriquecimiento funcional GO,
- índice de Sørensen,
- análisis de disimilaridad funcional,
- clustering jerárquico,
- escalamiento multidimensional (MDS),
- pruebas estadísticas de equivalencia.

---

# Tecnologías Utilizadas

| Tecnología | Uso |
|---|---|
| R | Motor estadístico |
| Shiny | Interfaz web |
| goSorensen | Método de equivalencia funcional |
| Plotly | Visualización interactiva |
| ggplot2 | Gráficos |
| DT | Tablas dinámicas |
| Bioconductor | Infraestructura bioinformática |



---

# Referencias

- Gene Ontology Consortium
- Bioconductor Project
- Paquete goSorensen
- Wickham H. Shiny