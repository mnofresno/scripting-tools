# Git Author Corrector

`author-fixer` es un script de Bash diseñado para corregir la información del autor en todos los commits de un repositorio Git. Es especialmente útil cuando necesitas actualizar tu información de autor (nombre y email) en todo el historial de commits.

## Características

- **Corrección Automática**: Actualiza automáticamente el nombre y email del autor en todos los commits del repositorio.
- **Autoinstalación**: Se instala automáticamente en `/usr/local/bin` la primera vez que se ejecuta.
- **Autocompletado**: Incluye soporte para autocompletado de Bash para una mejor experiencia de usuario.
- **Mensaje de Ayuda**: Proporciona una opción `-h` o `--help` para mostrar instrucciones detalladas de uso.
- **Forzar Sobrescritura**: Permite forzar la sobrescritura de copias de seguridad existentes con la opción `-f` o `--force`.

## Instalación

Para instalar el script `author-fixer`, sigue estos pasos. Asegúrate de ejecutar estos comandos con `sudo` para garantizar una instalación adecuada:

### Paso 1: Instalar `author-fixer`

Ejecuta el siguiente comando para descargar e instalar el script directamente desde el repositorio:

```bash
sudo curl -s https://raw.githubusercontent.com/mnofresno/scripting-tools/master/author-corrections/author-fixer.sh -o /usr/local/bin/author-fixer && sudo chmod +x /usr/local/bin/author-fixer
```

Este comando descargará el script y lo colocará en `/usr/local/bin/author-fixer`, haciéndolo disponible en todo el sistema. La primera vez que ejecutes el script, también instalará el autocompletado si aún no está instalado.

## Uso

Después de la instalación, puedes usar el script para corregir la información del autor en tu repositorio Git actual.

### Comando Básico

```bash
author-fixer
```

### Opciones

- `-f`, `--force`: Fuerza la sobrescritura de la copia de seguridad existente.
- `-h`, `--help`: Muestra la información de ayuda, instrucciones de uso y ejemplos.

### Ejemplos

1. **Corregir autores en el repositorio actual:**
   ```bash
   author-fixer
   ```

2. **Forzar la sobrescritura de la copia de seguridad existente:**
   ```bash
   author-fixer -f
   ```

## Autocompletado

El script soporta autocompletado de Bash para opciones como `-f`, `-h`, `--force` y `--help`. Esto facilita su uso al proporcionar sugerencias mientras escribes.

### Recargar Autocompletado Manualmente

Si necesitas recargar manualmente los scripts de autocompletado después de la instalación, usa el siguiente comando:

```bash
source /etc/bash_completion.d/author-fixer_autocomplete.sh
```

## Configuración

El script está configurado para reemplazar la siguiente información:

- Email antiguo: `mnofresno@gmail.com`
- Nombre correcto: `Mariano Fresno`
- Email correcto: `mnofresno+github@gmail.com`

Para modificar estos valores, edita el script y actualiza las variables correspondientes.

## Requisitos

- **Bash Shell**: Asegúrate de tener un shell compatible con Bash.
- **Git**: Git debe estar instalado en tu sistema para que el script funcione.

## Licencia

Este proyecto está licenciado bajo la [Licencia MIT](LICENSE). Eres libre de usar, modificar y distribuir este software.

## Contribuciones

¡Las contribuciones son siempre bienvenidas! Si tienes ideas para mejoras o nuevas características, no dudes en hacer fork del repositorio, crear una rama y enviar un pull request.

## Contacto

Si tienes alguna pregunta o necesitas ayuda adicional, por favor abre un issue en este repositorio. 