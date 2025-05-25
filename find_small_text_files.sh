#!/bin/bash

function show_help {
  echo "Usage: $0 SOURCE_FOLDER [-move DESTINATION]"
  echo "  SOURCE_FOLDER        The folder to search for .txt and .TXT files."
  echo "  -move DESTINATION    Move found files to the DESTINATION folder."
  exit 1
}

if [ -z "$1" ]; then
  echo "Error: No source folder provided."
  show_help
fi

SOURCE_FOLDER="$1"

if [ ! -d "$SOURCE_FOLDER" ]; then
  echo "Error: Source folder does not exist."
  exit 1
fi

MOVE=false

# Check for move option
if [ "$2" == "-move" ]; then
  if [ -z "$3" ]; then
    echo "Error: No destination folder provided."
    show_help
  fi
  MOVE=true
  DESTINATION="$3"
  mkdir -p "$DESTINATION"
fi

echo "Searching for .txt and .TXT files in $SOURCE_FOLDER..."

# Find .txt and .TXT files recursively and show them as they are found
find "$SOURCE_FOLDER" -type f \( -iname "*.txt" \) | while read -r file; do
  echo "Found: $file"
  
  if [ "$MOVE" == true ]; then
    echo "Moving $file to $DESTINATION"
    mv "$file" "$DESTINATION"
  fi
done

echo "Search completed."

