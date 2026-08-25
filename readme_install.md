# Guía de instalación — Extract-CR2MET-to-Shape

Cómo dejar este repositorio funcionando en tu computador desde cero.
Escrita para **Windows**; al final hay notas para macOS y Linux.

Escuela de Ingeniería Civil, Universidad de Valparaíso.

---

## Resumen

| Paso | Qué instalas / haces | Tiempo |
|------|----------------------|--------|
| 1 | Git | ~5 min |
| 2 | Configurar tu nombre y correo en Git | 1 min |
| 3 | Clonar (copiar) el repositorio | 2 min |
| 4 | R + RStudio + paquetes | ~20 min |
| 5 | Preparar tu cuenca (tu shapefile) | depende de ti |
| 6 | Correr los scripts | — |

---

## Paso 1 — Instalar Git

Git es el programa que copia y mantiene actualizado el repositorio. Es
distinto de GitHub: **Git** es el programa en tu computador, **GitHub** es el
sitio web donde está alojado el código.

1. Descarga el instalador desde <https://git-scm.com/downloads/win>
2. Ejecútalo y acepta las opciones por defecto. Son razonables; si tienes
   dudas, simplemente haz clic en *Next* en todas las pantallas.
   - La única que conviene mirar: en *Choosing the default editor*, si no
     conoces Vim, elige **Notepad** o **Visual Studio Code**. Si dejas Vim y
     alguna vez se te abre, sales con `Esc` y luego `:q!` + Enter.
3. Cierra y vuelve a abrir PowerShell (el instalador modifica el `PATH`, y las
   ventanas ya abiertas no se enteran).
4. Verifica:

```powershell
git --version
```

Debería responder algo como `git version 2.47.0.windows.1`. Si dice que
`git` no se reconoce como un comando, revisa la sección
[Problemas frecuentes](#problemas-frecuentes).

---

## Paso 2 — Configurar Git

Solo se hace una vez por computador. Git firma con estos datos cada cambio
que registres:

```powershell
git config --global user.name "Tu Nombre Apellido"
```

```powershell
git config --global user.email "tu.correo@alumnos.uv.cl"
```

Para revisar cómo quedó:

```powershell
git config --global --list
```

---

## Paso 3 — Clonar el repositorio

"Clonar" = descargar una copia completa, con todo su historial, capaz de
actualizarse después con un solo comando.

Primero ubícate donde quieras que quede la carpeta. Por ejemplo:

```powershell
cd "$env:USERPROFILE\Documents"
```

Luego clona:

```powershell
git clone https://github.com/DavidPobleteUV/Extract-CR2MET-to-Shape.git
```

Esto crea la carpeta **`Extract-CR2MET-to-Shape`** con todo adentro. El nombre
viene del repositorio, no de la carpeta que tenía el profesor. Si prefieres
otro nombre, agrégalo al final:

```powershell
git clone https://github.com/DavidPobleteUV/Extract-CR2MET-to-Shape.git CR2Met_extraction
```

El nombre de la carpeta **no afecta a los scripts**: ellos localizan la raíz
del proyecto solos.

Entra a la carpeta y confirma que llegó todo:

```powershell
cd Extract-CR2MET-to-Shape ; Get-ChildItem
```

Deberías ver `README.md`, `readme_install.md`, el archivo `.Rmd`, la carpeta
`scr/` y la carpeta `Cuenca/`.

### Alternativas a la línea de comandos

- **GitHub Desktop** (<https://desktop.github.com/>) — interfaz gráfica. Es
  la opción más simple si no quieres usar la terminal: *File → Clone
  repository → URL* y pegas la dirección del repositorio.
- **Descargar el ZIP** — en la página del repositorio, botón verde *Code →
  Download ZIP*. Funciona, pero **no lo recomiendo**: la carpeta resultante no
  está conectada a Git, así que no vas a poder actualizarla con `git pull`
  cuando se suban correcciones. Tendrías que volver a bajar el ZIP completo
  cada vez y copiar tus archivos a mano.

---

## Paso 4 — Instalar R, RStudio y los paquetes

1. **R** — <https://cran.r-project.org/bin/windows/base/> (instala primero R)
2. **RStudio Desktop** — <https://posit.co/download/rstudio-desktop/>
   (versión gratuita; instálalo después de R)

Abre RStudio y pega esto en la consola para instalar los paquetes. Toma varios
minutos:

```r
# Extracción climática (el .Rmd principal)
install.packages(c("tidyverse", "lubridate", "janitor",
                   "sf", "terra", "rvest", "stringr", "xml2"))

# Mapas de la grilla (scr/mapa_grilla_CR2Met.R)
install.packages(c("ggplot2", "dplyr", "ggrepel"))
```

`sf` y `terra` son los más pesados porque traen las librerías geoespaciales
(GDAL, GEOS, PROJ). Si RStudio pregunta *"Do you want to install from sources
the packages which need compilation?"*, responde **No** — así instala las
versiones ya compiladas y es mucho más rápido.

`terra` debe ser ≥ 1.7. Para verificar tu instalación:

```r
packageVersion("terra")
library(sf); library(terra)   # no debe dar error
```

---

## Paso 5 — Preparar tu cuenca

**Este es el paso que más se olvida.** El repositorio llega **sin** las
carpetas `Cuenca/`, `Results/` y `nc_cache/` con contenido: están en
`.gitignore` porque son datos, no código, y cada uno trabaja con su propia
cuenca.

Tienes que crear tu subcarpeta y dejar ahí tu shapefile de subcuencas:

```
Cuenca/
└── MiCuenca/
    ├── subcuencas.shp
    ├── subcuencas.dbf     ← los 4 son obligatorios
    ├── subcuencas.shx
    └── subcuencas.prj
```

Un shapefile no es un archivo suelto: si copias solo el `.shp`, no se puede
leer. Copia siempre el conjunto completo. Ver
[`Cuenca/LEEME.md`](Cuenca/LEEME.md) para el detalle.

Después, en el script que vayas a correr, ajusta los tres parámetros del
bloque de configuración:

```r
cuenca_nombre    <- "MiCuenca"
archivo_shp      <- "subcuencas.shp"
nombre_subcuenca <- "Subcuenca"   # la columna con el nombre de cada subcuenca
```

---

## Paso 6 — Correr los scripts

**El orden importa.** Primero la extracción, después el mapa:

### 1. Extracción de series climáticas (script principal)

`CR2Met_bestday_extraccion_1959_2025_cr2met2_5_v4_web_DPL.Rmd`

Ábrelo en RStudio y ejecuta los chunks en orden. Es el que descarga los NetCDF
desde `ftp.cr2.cl` y los deja en `nc_cache/`, así que necesitas internet y
paciencia: son varios GB según el rango de años que pidas.

Tiene que correr en RStudio (usa `rstudioapi` para ubicarse); no funciona con
`Rscript`.

### 2. Mapa de la grilla CR2MET sobre tu cuenca

```powershell
Rscript "scr\mapa_grilla_CR2Met.R"
```

O ábrelo en RStudio y presiona **Source**. Toma la geometría de la grilla de
los NetCDF que dejó el paso anterior en `nc_cache/`, por eso va después.

> Qué hace cada script, cómo se configura y qué archivos produce está
> documentado en **[`README.md`](README.md)** (y los scripts auxiliares en
> [`scr/README.md`](scr/README.md)). Esta guía cubre solo la instalación.

---

## Actualizar tu copia cuando haya cambios

Cuando se suban correcciones al repositorio, **no** vuelvas a clonar. Basta con:

```powershell
git pull
```

desde dentro de la carpeta del proyecto. Tus archivos en `Cuenca/`,
`Results/` y `nc_cache/` no se tocan, porque Git los ignora.

Si `git pull` reclama que tienes cambios locales en archivos del repositorio
(por ejemplo, editaste los parámetros del `.Rmd`), tienes dos salidas:

```powershell
git stash ; git pull ; git stash pop
```

guarda tus cambios, actualiza y los vuelve a aplicar. O bien copia tu versión
del archivo a otro lado, haz `git checkout -- <archivo>` y luego `git pull`.

---

## Problemas frecuentes

**`git` no se reconoce como un comando**
No reiniciaste la terminal después de instalar Git. Cierra PowerShell y ábrelo
de nuevo. Si persiste, reinstala marcando la opción *"Git from the command
line and also from 3rd-party software"*.

**El script se detiene con "No se encontro el shapefile"**
Te falta el Paso 5, o los nombres no calzan. El mensaje de error te dice la
ruta exacta donde el script está buscando: compárala con lo que tienes en
disco, revisando mayúsculas y la extensión.

**Error al leer el shapefile, o `Cannot open layer`**
Falta alguno de los archivos acompañantes (`.dbf`, `.shx`, `.prj`).

**La carpeta está en OneDrive y pasan cosas raras**
OneDrive sincroniza mientras R escribe y a veces bloquea archivos. Si ves
errores intermitentes de escritura, clona en una ruta local fuera de OneDrive,
por ejemplo `C:\GitHub\`.

**Rutas con espacios o tildes**
Funcionan, pero siempre entre comillas dobles en PowerShell. Si puedes
elegir, prefiere rutas cortas y sin caracteres especiales.

**`Rscript` no se reconoce como un comando**
R no está en el `PATH`. Usa RStudio (botón *Source*), o llama al ejecutable con
su ruta completa:
`& "C:\Program Files\R\R-4.4.0\bin\Rscript.exe" "scr\mapa_grilla_CR2Met.R"`
(ajusta el número de versión al que tengas instalado).

---

## Tutoriales y referencias de Git

Ordenados de más introductorio a más completo:

- **[Configurar Git — Documentación de GitHub (español)](https://docs.github.com/es/get-started/getting-started-with-git/set-up-git)**
  La guía oficial, corta y al grano. Buen punto de partida.
- **[Learn Git Branching (español)](https://learngitbranching.js.org/?locale=es_ES)**
  Tutorial interactivo en el navegador, con visualización de ramas. La mejor
  forma de entender qué hace realmente cada comando. No necesitas instalar nada.
- **[Git Cheat Sheet (PDF)](https://education.github.com/git-cheat-sheet-education.pdf)**
  Una hoja con los comandos más usados. Útil para tener a mano.
- **[Pro Git — libro completo (español)](https://git-scm.com/book/es/v2)**
  Gratuito y en línea. Es la referencia definitiva; los capítulos 1 y 2
  cubren de sobra lo que necesitas para este curso.
- **[Happy Git and GitHub for the useR](https://happygitwithr.com/)**
  En inglés, pero es *la* referencia para usar Git específicamente desde R y
  RStudio, incluyendo la integración gráfica de RStudio con Git.

---

## macOS y Linux

Los pasos 2 a 6 son idénticos. Solo cambia la instalación de Git:

**macOS** — viene con las Command Line Tools. Al escribir `git --version` en
la Terminal, el sistema ofrece instalarlas. Con Homebrew: `brew install git`

**Linux (Debian/Ubuntu)** — `sudo apt install git`

En ambos, las rutas usan `/` en vez de `\`:
`Rscript "scr/mapa_grilla_CR2Met.R"`

---

## Licencia

GNU General Public License v3.0 — ver el archivo `licence`.
