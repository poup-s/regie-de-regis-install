#!/usr/bin/env bash
# Installe la dernière version publiée de « La Régie de Regis » sur n'importe quel Mac,
# sans le blocage « Apple ne peut pas vérifier… » (même méthode que bbdump) :
# téléchargement en ligne de commande, quarantaine effacée, copie dans Applications.
#
#   curl -fsSL https://poup-s.github.io/regie-de-regis-install/install.sh | bash
#
# Le dépôt est privé : le script installe au besoin GitHub CLI (gh) et ouvre la connexion
# GitHub ; le compte doit avoir accès au dépôt poup-s/regie-de-regis.
# Zip déjà téléchargé depuis le navigateur (bloqué par macOS) :
#   curl -fsSL https://poup-s.github.io/regie-de-regis-install/install.sh | bash -s -- ~/Downloads/La-Regie-de-Regis-*-darwin-arm64.zip
# Les mises à jour suivantes se font ensuite depuis l'app.
set -euo pipefail
REPO="${REGIE_REPO:-poup-s/regie-de-regis}"
APP_NAME="La Régie de Regis"
LOCAL_ZIP="${1:-}"
ARCH="$(uname -m)"; [[ "$ARCH" == "x86_64" ]] && ARCH="x64"
DEST_DIR="${REGIE_DEST:-/Applications}"; [[ -w "$DEST_DIR" ]] || { DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; }

die() { printf "\n\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }
ok() { printf "\033[32m✓\033[0m %s\n" "$1"; }
step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }

[[ "$(uname -s)" == "Darwin" ]] || die "Cette app ne fonctionne que sur macOS."

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

if [[ -n "$LOCAL_ZIP" ]]; then
  [[ -f "$LOCAL_ZIP" ]] || die "Fichier introuvable : $LOCAL_ZIP"
  ZIP="$LOCAL_ZIP"
  step "Installation depuis $(basename "$ZIP")"
else
  # gh sert à lire les releases du dépôt privé (curl seul n'y a pas accès).
  export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  if ! command -v gh >/dev/null; then
    step "Installation de GitHub CLI (gh)"
    if command -v brew >/dev/null; then
      brew install gh || die "Installation de gh impossible : https://cli.github.com"
    else
      # Sans Homebrew : binaire officiel dans ~/.local/bin (pas besoin de mot de passe administrateur).
      GH_ARCH="$([[ "$ARCH" == "arm64" ]] && echo arm64 || echo amd64)"
      GH_VER="$(curl -fsSI https://github.com/cli/cli/releases/latest | grep -i '^location:' | sed -E 's|.*/tag/v([^[:space:]]+).*|\1|' | tr -d '\r')"
      [[ -n "$GH_VER" ]] || die "Version de gh introuvable : installe-le depuis https://cli.github.com"
      curl -fsSL -o "$TMP/gh.zip" "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_macOS_${GH_ARCH}.zip" \
        || die "Téléchargement de gh impossible : https://cli.github.com"
      ditto -x -k "$TMP/gh.zip" "$TMP/gh"
      mkdir -p "$HOME/.local/bin"
      cp "$TMP"/gh/gh_*/bin/gh "$HOME/.local/bin/gh" && chmod +x "$HOME/.local/bin/gh"
    fi
    ok "gh $(gh --version | head -1 | awk '{print $3}') installé"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    step "Connexion à GitHub"
    gh auth login --web --hostname github.com --git-protocol https </dev/tty || die "Connexion GitHub annulée."
  fi
  TAG="$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null)" \
    || die "Ton compte GitHub n'a pas accès à $REPO : demande une invitation au dépôt."
  step "Téléchargement de $APP_NAME $TAG ($ARCH)"
  gh release download "$TAG" --repo "$REPO" --pattern "*darwin-$ARCH.zip" --pattern "SHA256SUMS.txt" --dir "$TMP" \
    || die "Aucune version pour les Mac $ARCH dans $TAG."
  ZIP="$(ls "$TMP"/*darwin-"$ARCH".zip)"
  (cd "$TMP" && grep "$(basename "$ZIP")" SHA256SUMS.txt | shasum -a 256 -c -) >/dev/null || die "Empreinte SHA-256 invalide."
  ok "archive vérifiée"
fi

# Le zip lui-même peut porter la quarantaine (navigateur) : on la retire avant d'extraire.
xattr -c "$ZIP" 2>/dev/null || true
ditto -x -k "$ZIP" "$TMP/app"
SRC="$TMP/app/$APP_NAME.app"
[[ -d "$SRC" ]] || die "$APP_NAME.app introuvable dans l'archive."
xattr -cr "$SRC" 2>/dev/null || true

osascript -e 'tell application id "fr.regis.regie-de-regis" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST_DIR/$APP_NAME.app"
ditto "$SRC" "$DEST_DIR/$APP_NAME.app"
xattr -cr "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true

# Signature abîmée par la copie (rare) : on re-signe localement pour que macOS accepte de lancer l'app.
if ! codesign --verify --deep --strict "$DEST_DIR/$APP_NAME.app" >/dev/null 2>&1; then
  codesign --force --deep --sign - "$DEST_DIR/$APP_NAME.app" >/dev/null 2>&1 || true
fi

ok "installée dans $DEST_DIR — les prochaines mises à jour se feront depuis l'app."
[[ -n "${REGIE_NO_OPEN:-}" ]] || open "$DEST_DIR/$APP_NAME.app"
