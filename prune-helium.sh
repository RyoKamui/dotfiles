#!/usr/bin/env zsh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ■ PRUNE HELIUM BACKUP — keep only extensions, their data, and browser prefs/config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Forgets (removes from the chezmoi source repo ONLY — the live files in
# ~/Library/Application Support/net.imput.helium/ are never touched) every
# managed Helium file that is not on the keep-list below.
#
# Usage:
#   ./prune-helium.sh            dry-run: print the plan, write the full list
#                                to /tmp/helium-forget-list.txt
#   ./prune-helium.sh --apply    actually run `chezmoi forget`
#   ./prune-helium.sh --sync     converge with live state: forget entries whose
#                                live file has disappeared (app rotated/deleted
#                                them), re-add kept files that drifted, and
#                                clean up empty source dirs. Run after quitting
#                                Helium for a stable pass.
#
# Notes:
#   • Forgotten files remain recoverable from git history (no rewrite here).
#   • The Pictogram custom icon (…/Custom Icons/net.imput.helium) only matches
#     by filename; it is skipped and left managed.
#   • Kept files that drifted since the last snapshot still prompt on apply —
#     refresh them with:  chezmoi re-add -- "Library/Application Support/net.imput.helium"

set -euo pipefail

if [[ "${1:-}" == "--sync" ]]; then
    echo "Syncing Helium backup with live state…"
    helium_src=$(chezmoi source-path -- "Library/Application Support/net.imput.helium" 2>/dev/null)
    for pass in 1 2 3; do
        before=$(chezmoi status 2>/dev/null | grep -c 'net\.imput\.helium/' || true)
        # 1. forget managed entries whose live file has disappeared
        chezmoi managed -i files 2>/dev/null | grep 'net\.imput\.helium/' | while IFS= read -r t; do
            [[ -e "$HOME/$t" ]] || printf '%s\0' "$HOME/$t"
        done | xargs -0 chezmoi forget --force -- >/dev/null 2>&1 || true
        # 2. re-add kept files that drifted (still exist, content changed)
        chezmoi status 2>/dev/null | grep 'net\.imput\.helium/' | grep -E '^M' | sed 's|^MM ||;s|^M ||' | while IFS= read -r t; do
            [[ -e "$HOME/$t" ]] && chezmoi re-add -- "$HOME/$t" >/dev/null 2>&1
        done
        # 3. drop source dirs left empty by the forgets
        [[ -n "$helium_src" ]] && find "$helium_src" -type d -empty -delete 2>/dev/null || true
        after=$(chezmoi status 2>/dev/null | grep -c 'net\.imput\.helium/' || true)
        echo "  pass ${pass}: pending Helium entries ${before} → ${after}"
        [[ "$after" == 0 || "$after" == "$before" ]] && break
    done
    echo "Sync complete. Re-run inside this script is idempotent; Helium rewrites"
    echo "files while running, so quit Helium first for a fully stable pass."
    exit 0
fi

# ── KEEP-LIST: essentials (paths relative to the Helium profile root) ─────────
keep_specs=(
  # — extensions —
  'Default/Extensions'                   # installed Webstore extensions
  'External Plugins'                     # manually installed extensions (CRX)
  # — extension state, settings & config —
  'Default/Local Extension Settings'     # extension settings (local)
  'Default/Sync Extension Settings'      # extension settings (synced)
  'Default/Managed Extension Settings'   # extension settings (policy)
  'Default/Extension State'              # extension runtime state
  'Default/Extension Scripts'            # scripts registered by extensions
  'Default/Extension Rules'              # dynamic rules registered by extensions
  # — browser preferences & config —
  'Default/Preferences'                  # main browser preferences
  'Default/Secure Preferences'           # protected browser preferences
  'Local State'                          # browser-wide config
  'Default/BookmarkMergedSurfaceOrdering' # bookmark internals
  'Default/engine_allowlist.bf'          # search engine config
  'Default/ClientCertificates'           # client certificate decisions
  'Default/PreferredApps'                # PWA app associations
  'Default/Web Data'                     # autofill profiles (addresses etc.)
  'Default/Web Data-journal'
  'Default/Account Web Data'             # account-scoped autofill
  'Default/Account Web Data-journal'
  # — sentinels —
  'First Run'                            # skips the first-run wizard on restore
  'Last Version'
  'Default/README'
)

apply=0
[[ "${1:-}" == "--apply" ]] && apply=1

kept=0; forgotten=0; skipped=0
typeset -a forget_targets forget_targets_abs

while IFS= read -r target; do
  rel=${target#*net.imput.helium/}
  if [[ "$rel" == "$target" || -z "$rel" ]]; then
    skipped=$((skipped + 1))             # e.g. the Pictogram custom icon
    continue
  fi
  keep=false
  for spec in "${keep_specs[@]}"; do
    if [[ "$rel" == "$spec" || "$rel" == "$spec"/* ]]; then keep=true; break; fi
  done
  if $keep; then
    kept=$((kept + 1))
  else
    forgotten=$((forgotten + 1))
    forget_targets+="${target}"
    forget_targets_abs+="$HOME/${target}"
  fi
done < <(chezmoi managed --include=files 2>/dev/null | grep 'net\.imput\.helium/')

if (( forgotten == 0 )); then
  echo "Nothing to forget — the keep-list already covers every managed Helium file."
  exit 0
fi

printf '%s\n' "${forget_targets[@]}" > /tmp/helium-forget-list.txt

echo "Summary (mode: $([[ $apply -eq 1 ]] && echo APPLY || echo DRY-RUN))"
echo "  kept in backup:    ${kept}"
echo "  to be forgotten:   ${forgotten}"
echo "  skipped:           ${skipped} (not Helium profile files)"
echo
echo "FORGET breakdown (files per directory):"
sed 's|.*net\.imput\.helium/||' /tmp/helium-forget-list.txt | awk -F/ '
  NF == 1                      { print "  [root] " $0; next }
  $1 == "Default" && NF == 2   { print "  " $0; next }
  { print "  " $1 "/" $2 }' | sort | uniq -c | sort -rn | sed 's/^/  /'
echo
echo "Full forget list: /tmp/helium-forget-list.txt"

if (( apply )); then
  echo "Running: chezmoi forget (${#forget_targets_abs[@]} targets)…"
  # absolute paths: chezmoi resolves relative args against the CWD, which breaks
  # when this script is run from inside the source tree; --force skips the
  # per-file "Remove …?" prompts so the prune runs unattended
  chezmoi forget --force -- "${forget_targets_abs[@]}"
  # drop source dirs left empty by the forgets (else apply re-creates them as
  # empty 700-mode directories in the destination)
  find "$(dirname "$(chezmoi source-path -- "Library/Application Support/net.imput.helium/First Run" 2>/dev/null)")" -type d -empty -delete 2>/dev/null || true
  echo "Done. Live files were not touched. Run 'chezmoi apply --dry-run' to see the new state."
else
  echo "DRY-RUN only — re-run with --apply to execute."
fi
