#!/usr/bin/env bash
# ==============================================================================
# deploy.sh — Deploy the Curie showcase to GitHub Pages in one command.
#
# Usage:
#     ./deploy.sh your@email.com
#
# What it does:
#   1. Swaps REPLACE_WITH_EMAIL in index.html with your email
#   2. Initializes git repo locally
#   3. Creates public GitHub repo 'diffuser' under your account
#   4. Pushes files
#   5. Enables GitHub Pages on main branch
#   6. Prints the live URL (and opens it in your browser on Mac)
#
# Requirements (one-time setup):
#   - git (ships with macOS / comes with Xcode Command Line Tools)
#   - gh  (GitHub CLI — install with: brew install gh)
#   - Authenticated once: gh auth login   (just press enter a few times)
#
# Idempotent-ish: safe to inspect with --dry-run before committing.
# ==============================================================================

set -euo pipefail

# ------- Colors for readability --------------------------------------------
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

say()  { printf "%s» %s%s\n" "$BOLD" "$1" "$RESET"; }
ok()   { printf "%s✓ %s%s\n" "$GREEN" "$1" "$RESET"; }
warn() { printf "%s! %s%s\n" "$YELLOW" "$1" "$RESET"; }
die()  { printf "%s✗ %s%s\n" "$RED" "$1" "$RESET" >&2; exit 1; }

REPO_NAME="diffuser"
DRY_RUN=false

# ------- Parse args --------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
  esac
done

EMAIL="${1:-}"

# ------- Preflight ---------------------------------------------------------
say "Preflight checks"

[ -f "index.html" ]        || die "index.html not found. Run this from the diffuser-showcase folder."
[ -d "images" ]            || die "images/ folder not found."
[ -f "images/hero.jpg" ]   || die "images/hero.jpg missing. Did compression finish?"

command -v git >/dev/null  || die "git is not installed. Install Xcode Command Line Tools: xcode-select --install"
command -v gh  >/dev/null  || die "gh (GitHub CLI) is not installed. Install with: brew install gh"

# Check gh auth status
if ! gh auth status >/dev/null 2>&1; then
  warn "You're not signed in to GitHub CLI yet."
  say  "Running: gh auth login  (follow the prompts — defaults are fine)"
  gh auth login
fi

GH_USER=$(gh api user -q .login)
ok "Authenticated as $GH_USER"

if [ -z "$EMAIL" ]; then
  read -rp "Email address for the footer (or press enter to leave as-is): " EMAIL
fi

# ------- Sanity confirmation ----------------------------------------------
echo
say "Ready to deploy"
echo "  Repo:  ${BOLD}${GH_USER}/${REPO_NAME}${RESET} (public)"
echo "  URL:   ${BOLD}https://${GH_USER}.github.io/${REPO_NAME}/${RESET}"
echo "  Email: ${EMAIL:-<unchanged>}"
echo
if [ "$DRY_RUN" = true ]; then
  warn "Dry-run mode — stopping before any changes."
  exit 0
fi
read -rp "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."

# ------- Swap email --------------------------------------------------------
if [ -n "$EMAIL" ]; then
  say "Setting email in index.html"
  # Use a backup extension for portability (BSD sed on macOS vs GNU sed on Linux)
  sed -i.bak "s|REPLACE_WITH_EMAIL|${EMAIL}|g" index.html
  rm -f index.html.bak
  ok "Email set"
fi

# ------- Git init ----------------------------------------------------------
if [ ! -d ".git" ]; then
  say "Initializing git repo"
  git init -q
  git branch -M main
fi

# .gitignore if not present
if [ ! -f ".gitignore" ]; then
  cat > .gitignore <<'EOF'
.DS_Store
*.bak
Thumbs.db
EOF
fi

say "Staging files"
git add .
if git diff --cached --quiet; then
  warn "No changes staged (everything already committed)."
else
  git commit -q -m "Deploy Curie showcase"
  ok "Committed"
fi

# ------- Create repo (or reuse) --------------------------------------------
if gh repo view "${GH_USER}/${REPO_NAME}" >/dev/null 2>&1; then
  warn "Repo ${GH_USER}/${REPO_NAME} already exists — pushing to existing repo."
  if ! git remote | grep -q "^origin$"; then
    git remote add origin "https://github.com/${GH_USER}/${REPO_NAME}.git"
  fi
  git push -u origin main -q
else
  say "Creating repo ${GH_USER}/${REPO_NAME}"
  gh repo create "${REPO_NAME}" --public --source=. --remote=origin --push
  ok "Repo created and pushed"
fi

# ------- Enable Pages ------------------------------------------------------
say "Enabling GitHub Pages"

# Check if Pages is already enabled — the API returns 200 if so, 404 if not.
if gh api "repos/${GH_USER}/${REPO_NAME}/pages" >/dev/null 2>&1; then
  ok "Pages was already enabled"
else
  # Enable Pages pointing at main branch, root path
  gh api -X POST "repos/${GH_USER}/${REPO_NAME}/pages" \
    -f "source[branch]=main" \
    -f "source[path]=/" \
    >/dev/null
  ok "Pages enabled"
fi

LIVE_URL="https://${GH_USER}.github.io/${REPO_NAME}/"

# ------- Done --------------------------------------------------------------
echo
echo "${GREEN}${BOLD}✓ Done.${RESET}"
echo
echo "Live URL: ${BOLD}${LIVE_URL}${RESET}"
echo
echo "${DIM}First build takes 1–3 minutes. If the URL 404s at first, wait a minute and reload.${RESET}"
echo

# Open in browser on Mac
if command -v open >/dev/null 2>&1; then
  say "Opening repo settings in your browser (you can watch the deployment there)"
  open "https://github.com/${GH_USER}/${REPO_NAME}/actions"
fi
