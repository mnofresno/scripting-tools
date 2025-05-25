#!/bin/bash

# Define la ruta de instalación
INSTALL_PATH="/usr/local/bin/author-fixer"

# Función de autoinstalación
self_install() {
    # Verifica si el script ya está en la ruta objetivo
    if [ "$(realpath "$0")" != "$INSTALL_PATH" ]; then
        echo "Instalando el script en $INSTALL_PATH..."
        sudo cp "$0" "$INSTALL_PATH"
        sudo chmod +x "$INSTALL_PATH"
        echo "Script instalado exitosamente. Por favor ejecuta 'author-fixer' para usar el script."
        install_autocompletion
        exit 0
    fi
}

# Función para mostrar mensaje de ayuda
show_help() {
    echo "Uso: author-fixer [OPTIONS]"
    echo ""
    echo "Opciones:"
    echo "  -f, --force              Fuerza la sobrescritura de la copia de seguridad existente."
    echo "  -h, --help               Muestra este mensaje de ayuda y sale."
    echo ""
    echo "Descripción:"
    echo "  Este script corrige la información del autor en todos los commits de Git"
    echo "  reemplazando el email antiguo por el nuevo."
    echo ""
    echo "Ejemplos:"
    echo "  author-fixer             Ejecuta la corrección de autores en el repositorio actual."
    echo "  author-fixer -f          Fuerza la sobrescritura de la copia de seguridad existente."
}

# Función para instalar autocompletado
install_autocompletion() {
    local autocomplete_script="/etc/bash_completion.d/author-fixer_autocomplete.sh"
    
    if [ ! -f "$autocomplete_script" ]; then
        echo "Instalando autocompletado para author-fixer..."
        cat <<EOF | sudo tee "$autocomplete_script" > /dev/null
#!/bin/bash

_author_fixer_autocomplete() {
    local cur opts
    COMPREPLY=()
    cur="\${COMP_WORDS[COMP_CWORD]}"
    opts="-f -h --force --help"

    if [[ "\${cur}" == -* ]]; then
        COMPREPLY=( \$(compgen -W "\${opts}" -- "\${cur}") )
    fi

    return 0
}

complete -F _author_fixer_autocomplete author-fixer
EOF
        echo "Autocompletado instalado. Recarga tu shell o ejecuta 'source ~/.bashrc' para habilitarlo."
    fi
}

# Instala el script si aún no está instalado
self_install

# Variables por defecto
FORCE=false

# Procesa argumentos
while getopts ":fh-:" opt; do
  case ${opt} in
    f )
      FORCE=true
      ;;
    h )
      show_help
      exit 0
      ;;
    - )
      case "${OPTARG}" in
          force)
            FORCE=true
            ;;
          help)
            show_help
            exit 0
            ;;
          *)
            echo "Opción inválida: --${OPTARG}" 1>&2
            exit 1
            ;;
      esac
      ;;
    \? )
      echo "Opción inválida: -$OPTARG" 1>&2
      exit 1
      ;;
  esac
done

# Verifica si estamos en un repositorio Git
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: No estás dentro de un repositorio Git."
    exit 1
fi

# Prepara el comando git filter-branch
FILTER_CMD="git filter-branch --env-filter '

OLD_EMAIL=\"mnofresno@gmail.com\"
CORRECT_NAME=\"Mariano Fresno\"
CORRECT_EMAIL=\"mnofresno+github@gmail.com\"

if [ \"\$GIT_COMMITTER_EMAIL\" = \"\$OLD_EMAIL\" ]; then
    export GIT_COMMITTER_NAME=\"\$CORRECT_NAME\"
    export GIT_COMMITTER_EMAIL=\"\$CORRECT_EMAIL\"
fi

if [ \"\$GIT_AUTHOR_EMAIL\" = \"\$OLD_EMAIL\" ]; then
    export GIT_AUTHOR_NAME=\"\$CORRECT_NAME\"
    export GIT_AUTHOR_EMAIL=\"\$CORRECT_EMAIL\"
fi

' --tag-name-filter cat -- --branches --tags"

# Agrega la opción -f si se especificó
if [ "$FORCE" = true ]; then
    FILTER_CMD="$FILTER_CMD -f"
fi

# Ejecuta el comando
eval "$FILTER_CMD"
