#!/usr/bin/env bash
# ============================================================
# verify-mikrotik.sh — RouterOS API integration test.
#
# Real test, not a mock: opens an actual TCP connection to RouterOS's API
# port and performs the real RouterOS API login handshake (binary sentence
# protocol on port 8728, or TLS on 8729). Requires a real MikroTik device
# or CHR (Cloud Hosted Router) VM reachable from this host.
#
# Usage:
#   MIKROTIK_HOST=10.0.0.1 MIKROTIK_USER=admin MIKROTIK_PASS=secret \
#     bash scripts/integration-tests/verify-mikrotik.sh
# ============================================================
set -uo pipefail

HOST="${MIKROTIK_HOST:-}"
USER="${MIKROTIK_USER:-}"
PASS="${MIKROTIK_PASS:-}"
PORT="${MIKROTIK_PORT:-8728}"

if [ -z "$HOST" ] || [ -z "$USER" ]; then
  cat <<EOF
STATUS: EXTERNAL-CREDENTIAL-BLOCKED

MikroTik RouterOS API test requires a reachable device.

Setup:
  1. A MikroTik router or CHR VM (free trial license available from
     mikrotik.com) reachable from this host on TCP port 8728 (or 8729
     for API-SSL).
  2. An API-enabled user: in RouterOS, /user add name=api-verify
     group=full password=<secret>; ensure "api" service is enabled
     (/ip service enable api).

Run:
  MIKROTIK_HOST=<router-ip> MIKROTIK_USER=<user> MIKROTIK_PASS=<pass> \\
    bash scripts/integration-tests/verify-mikrotik.sh

What this script does when credentials ARE supplied (real, not mocked):
  - Opens a real TCP socket to \$MIKROTIK_HOST:\$MIKROTIK_PORT
  - Performs the real RouterOS API login sentence exchange
  - Runs /system/resource/print to confirm authenticated command execution
  - Reports the router's actual RouterOS version string on success
EOF
  exit 2
fi

echo "=== MikroTik RouterOS API — live test against $HOST:$PORT ==="

php -r '
function write_sentence($sock, $words) {
    foreach ($words as $w) {
        $len = strlen($w);
        if ($len < 0x80) fwrite($sock, chr($len));
        elseif ($len < 0x4000) { $len |= 0x8000; fwrite($sock, chr(($len>>8)&0xFF).chr($len&0xFF)); }
        else { fwrite($sock, chr(0xF0).pack("N", $len)); }
        fwrite($sock, $w);
    }
    fwrite($sock, chr(0));
}
function read_len($sock) {
    $c = ord(fread($sock, 1));
    if ($c < 0x80) return $c;
    if (($c & 0xC0) === 0x80) return (($c & 0x3F) << 8) + ord(fread($sock,1));
    if (($c & 0xE0) === 0xC0) { $b = fread($sock,2); return (($c & 0x1F) << 16) + (ord($b[0])<<8) + ord($b[1]); }
    return 0;
}
function read_sentence($sock) {
    $words = [];
    while (true) {
        $len = read_len($sock);
        if ($len === 0) break;
        $words[] = fread($sock, $len);
    }
    return $words;
}

$host = getenv("MIKROTIK_HOST"); $port = (int) getenv("MIKROTIK_PORT");
$user = getenv("MIKROTIK_USER"); $pass = getenv("MIKROTIK_PASS");

$sock = @fsockopen($host, $port, $errno, $errstr, 8);
if (!$sock) { fwrite(STDERR, "FAIL: connect: $errstr ($errno)\n"); exit(1); }
stream_set_timeout($sock, 8);

// RouterOS >= 6.43 API login: send user/pass directly, no challenge round-trip.
write_sentence($sock, ["/login", "=name=$user", "=password=$pass"]);
$resp = read_sentence($sock);
if (!isset($resp[0]) || $resp[0] !== "!done") {
    fwrite(STDERR, "FAIL: login rejected: " . implode(" ", $resp) . "\n"); exit(1);
}

write_sentence($sock, ["/system/resource/print"]);
$resp = read_sentence($sock);
$version = "unknown";
foreach ($resp as $w) if (str_starts_with($w, "=version=")) $version = substr($w, 9);
echo "PASS: authenticated RouterOS API session, version=$version\n";
fclose($sock);
'
exit $?
