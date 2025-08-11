#!/bin/bash

# Paths
BRANDING_XML=~/jellyfin/config/config/branding.xml
CSS_FILES=("${@:2}")  # Collects all CSS files passed as arguments

# Usage function
usage() {
  echo "Usage: $0 [--append|--overwrite|--clear] <css_file_1> [<css_file_2> ...]"
  echo "  --append     Append CSS to existing <CustomCss> content"
  echo "  --overwrite  Overwrite <CustomCss> content (default)"
  echo "  --clear      Clear <CustomCss> content (empty it)"
  exit 1
}

# Default mode
MODE="overwrite"

# Parse flag
case "$1" in
  --append) MODE="append" ;;
  --overwrite) MODE="overwrite" ;;
  --clear) MODE="clear" ;;
  "") MODE="overwrite" ;;  # no arg defaults to overwrite
  *) usage ;;
esac

# Check if clear mode was selected and if CSS files are passed for other modes
if [[ "$MODE" != "clear" && ${#CSS_FILES[@]} -eq 0 ]]; then
  usage
fi

# Backup branding.xml before changes
cp "$BRANDING_XML" "${BRANDING_XML}.bak.$(date +%F-%T)"

# Clear the CustomCss if requested
if [[ "$MODE" == "clear" ]]; then
  if command -v xmlstarlet >/dev/null 2>&1; then
    xmlstarlet ed -L -u "//CustomCss" -v "" "$BRANDING_XML"
  else
    sed -i.bak -E "s|<CustomCss>.*</CustomCss>|<CustomCss></CustomCss>|" "$BRANDING_XML"
  fi
else
  # Loop through CSS files and append/overwrite
  for CSS_FILE in "${CSS_FILES[@]}"; do
    if [[ ! -f "$CSS_FILE" ]]; then
      echo "CSS file not found: $CSS_FILE"
      continue
    fi

    # Read and escape CSS content for XML
    CSS_CONTENT=$(sed 's/&/&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$CSS_FILE")

    if command -v xmlstarlet >/dev/null 2>&1; then
      if [[ "$MODE" == "overwrite" ]]; then
        xmlstarlet ed -L -u "//CustomCss" -v "$CSS_CONTENT" "$BRANDING_XML"
      elif [[ "$MODE" == "append" ]]; then
        # Append mode: get current content, append, set back
        current=$(xmlstarlet sel -t -v "//CustomCss" "$BRANDING_XML")
        new_content="${current}${CSS_CONTENT}"
        xmlstarlet ed -L -u "//CustomCss" -v "$new_content" "$BRANDING_XML"
      fi
    else
      # Escape CSS for sed insertion, flatten to single line
      escaped_css=$(sed -e 's/[&|]/\\&/g' -e 's|/|\\/|g' "$CSS_FILE" | tr '\n' ' ')

      if [[ "$MODE" == "overwrite" ]]; then
        sed -i.bak -E "s|<CustomCss>.*</CustomCss>|<CustomCss>${escaped_css}</CustomCss>|" "$BRANDING_XML"
      elif [[ "$MODE" == "append" ]]; then
        # Append before </CustomCss>
        sed -i.bak -E "s|(</CustomCss>)| ${escaped_css} \1|" "$BRANDING_XML"
      fi
    fi
  done
fi

# Fix permissions
chmod 644 "$BRANDING_XML"

echo "branding.xml updated in <CustomCss> ($MODE mode)"
echo "Backup saved as ${BRANDING_XML}.bak.*"

# Check for the --clear argument
if [[ "$1" == "--clear" ]]; then
  echo "Skipping Jellyfin container restart due to --clear argument."
  exit 0  # Exit the script without restarting
fi

if docker restart jellyfin; then
  echo "Jellyfin container restarted successfully."
else
  echo "Failed to restart Jellyfin container." >&2
  exit 1
fi
