#!/usr/bin/env bash
# Add the shared iOS section once; the separate parity refresher adds the detailed behavior later.
set -euo pipefail

# The cheatsheet checkout is intentionally an explicit argument so no repository is edited by accident.
CHEATSHEET_ROOT="${1:?usage: update-cheatsheets.sh /path/to/cornucopia-cheatsheets-llm}"
HELP_DIR="$CHEATSHEET_ROOT/help"
# Link directly to the app's implementation anchor for testers who want executable evidence.
IOS_LINK="https://github.com/owaspcornucopia/llm-companion-scenario-ios#ios-implementation"

# Keep the Android-selected applicable set in one readable allow-list.
is_applicable() {
  case "$1" in
    PC2|PC3|PC4|PC5|PC6|PC7|PC8|PC9|PCQ|AA2|AA7|AA8|AA9|AAQ|NS2|NS3|NS4|NS5|NS6|NS7|NS8|NS9|RS2|RS3|RS4|RS5|RS7|RS8|RS9|RSJ|RSQ|RSX|CRM2|CRM3|CRM4|CRM6|CRM7|CRM9|CRMX|CM8|CMX|LLM2|LLM3|LLM4|LLM5|LLM7|LLM8|LLM9|LLMJ|LLMK|LLMQ|LLMX) return 0 ;;
    *) return 1 ;;
  esac
}

for file in "$HELP_DIR"/*.md; do
  # Derive the card code from the filename instead of trusting a hand-maintained table.
  code="$(basename "$file" .md)"
  # Never overwrite existing shared or Android-specific card text.
  grep -q '^## IOS implementation$' "$file" && continue
  if is_applicable "$code"; then
    # Applicable cards get the common threat/mitigation scaffold.
    printf '%s\n' '' '## IOS implementation' '' \
      'This card is applicable to the native iOS AI Anti Fraud 3.0 scenario. The app' \
      'uses a native iOS equivalent of the mobile behavior described above.' \
      'The normal screen shows natural language; SQL and rows remain hidden debug data.' '' \
      '### What can go wrong' '' \
      'An attacker can use the matching iOS entry point, local storage, process state,' \
      'or on-device model flow to expose data or change the fraud investigation. The' \
      'exact path depends on the card and is intentionally reproducible with synthetic' \
      'transactions.' '' \
      '### What to do' '' \
      'Apply the iOS controls in the MASTG, MASVS, and MASWE references above. Test' \
      "the behavior on an iOS Simulator with the [IOS implementation]($IOS_LINK) and" \
      'verify that input validation, authorization, data minimization, integrity, and' \
      'protected storage are enforced at the native boundary.' >> "$file"
  else
    # Non-applicable cards get an explicit scope decision instead of silent omission.
    printf '%s\n' '' '## IOS implementation' '' \
      'This card is not applicable to the native iOS AI Anti Fraud 3.0 scenario. The' \
      'app has no matching workflow for this card, so the scenario does not invent a' \
      'web, Android-only, or unrelated feature just to force coverage.' '' \
      "The [IOS implementation]($IOS_LINK) documents the selected native iOS cards" \
      'and the boundaries of this decision.' >> "$file"
  fi
done