#!/bin/bash

# Define la ruta de instalación
INSTALL_PATH="/usr/local/bin/author-fixer"

# Función para instalar dependencias
install_dependencies() {
    echo "Verificando e instalando dependencias..."

    # Verificar e instalar git
    if ! command -v git &> /dev/null; then
        echo "Instalando git..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y git
        elif command -v yum &> /dev/null; then
            sudo yum install -y git
        elif command -v brew &> /dev/null; then
            brew install git
        else
            echo "Error: No se pudo instalar git. Por favor instálalo manualmente."
            exit 1
        fi
    fi

    # Verificar e instalar git-filter-repo
    if ! command -v git-filter-repo &> /dev/null; then
        echo "Instalando git-filter-repo..."
        if command -v pip3 &> /dev/null; then
            sudo pip3 install git-filter-repo
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y git-filter-repo
        elif command -v yum &> /dev/null; then
            sudo yum install -y git-filter-repo
        elif command -v brew &> /dev/null; then
            brew install git-filter-repo
        else
            echo "Error: No se pudo instalar git-filter-repo. Por favor instálalo manualmente usando uno de estos métodos:"
            echo "  - pip3 install git-filter-repo"
            echo "  - apt-get install git-filter-repo (en sistemas basados en Debian/Ubuntu)"
            echo "  - yum install git-filter-repo (en sistemas basados en RHEL/CentOS)"
            echo "  - brew install git-filter-repo (en macOS con Homebrew)"
            exit 1
        fi
    fi

    echo "Todas las dependencias están instaladas."
}

# Función de autoinstalación
self_install() {
    # Verifica si el script ya está en la ruta objetivo
    if [ "$(realpath "$0")" != "$INSTALL_PATH" ]; then
        echo "Instalando el script en $INSTALL_PATH..."
        
        # Instalar dependencias antes de continuar
        install_dependencies
        
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
    echo "  estableciendo el nombre y email del autor en todos los commits."
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

# Prepara el comando git filter-repo
FILTER_CMD="git filter-repo --commit-callback '
    commit.author_email = b\"mnofresno+github@gmail.com\"
    commit.author_name = b\"Mariano Fresno\"
    return commit
' --force"

# Ejecuta el comando
echo "Iniciando corrección de autores..."
eval "$FILTER_CMD"
echo "¡Corrección de autores completada!"
