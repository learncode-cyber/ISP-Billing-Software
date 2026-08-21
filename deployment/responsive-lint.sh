#!/usr/bin/env bash
# Asserts the responsive contract is present in source. Browser QA proves
# rendering; this catches regressions cheaply on every commit.
set -euo pipefail
cd "$(dirname "$0")/../frontend"
fail=0
chk(){ if eval "$2"; then echo "  ok  $1"; else echo "  FAIL $1"; fail=1; fi; }

chk "media queries present"          "[ \$(grep -c '@media' src/theme.css) -ge 6 ]"
chk "page overflow-x hidden"         "grep -q 'overflow-x: hidden' src/theme.css"
chk "table scroll container"         "grep -q 'table-scroll' src/theme.css"
chk "card transformation <=640px"    "grep -q 'responsive-cards' src/theme.css"
chk "touch target token 44px"        "grep -q 'touch: 44px' src/theme.css"
chk "coarse-pointer sizing"          "grep -q 'pointer: coarse' src/theme.css"
chk "iOS zoom prevention"            "grep -q 'font-size: 16px !important' src/theme.css"
chk "no fixed sidebar grid"          "! grep -q 'gridTemplateColumns: \"244px 1fr\"' src/layouts/AppShell.jsx"
chk "drawer breakpoint present"      "grep -q 'min-width: 1024px' src/layouts/AppShell.jsx"
chk "no repeat(4, 1fr) grids"        "! grep -rq 'repeat(4, 1fr)' src/"

[ $fail -eq 0 ] && echo "responsive contract PASS" || { echo "responsive contract FAILED"; exit 1; }
