# Carpeta `Cuenca/`

Aquí va **tu** shapefile de subcuencas. Esta carpeta llega vacía a propósito:
su contenido está en `.gitignore`, así que los shapefiles no se suben al
repositorio y cada usuario trabaja con su propia cuenca.

## Qué tienes que crear

Una subcarpeta por cuenca, con el shapefile adentro:

```
Cuenca/
└── <cuenca_nombre>/
    ├── <archivo_shp>.shp
    ├── <archivo_shp>.dbf     ← los 4 archivos son obligatorios
    ├── <archivo_shp>.shx
    └── <archivo_shp>.prj
```

Un shapefile no es un archivo suelto: si copias solo el `.shp` sin el `.dbf`,
`.shx` y `.prj`, no se puede leer. Copia siempre el conjunto completo.

## Requisitos del shapefile

- Una columna con el nombre de cada subcuenca (la que declaras en
  `nombre_subcuenca`).
- CRS definido, idealmente en el `.prj`. Si falta, los scripts intentan
  inferirlo: `EPSG:4326` si las coordenadas parecen lon/lat, `EPSG:32719`
  (UTM 19S) como respaldo proyectado.

## Después

Ajusta estos tres parámetros al inicio del script que vayas a correr
(el `.Rmd` de extracción o `scr/mapa_grilla_CR2Met.R`):

```r
cuenca_nombre    <- "<nombre de la subcarpeta>"
archivo_shp      <- "<archivo>.shp"
nombre_subcuenca <- "<columna con el nombre de cada subcuenca>"
```

Instrucciones completas de instalación en
[`readme_install.md`](../readme_install.md).
