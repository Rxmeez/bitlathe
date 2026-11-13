# Locate the bl executable: $BL_PATH workflow variable, then common install dirs.
find_bl() {
  if [ -n "${BL_PATH:-}" ] && [ -x "$BL_PATH" ]; then echo "$BL_PATH"; return 0; fi
  for p in /usr/local/bin/bl /opt/homebrew/bin/bl "$HOME/.local/bin/bl"; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}
