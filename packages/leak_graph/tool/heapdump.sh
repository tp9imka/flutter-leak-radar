#!/usr/bin/env bash
#
# heapdump.sh — STANDALONE raw Dart heap-snapshot dumper for a running
# debug/profile Flutter app on a connected Android device.
#
# No `flutter run`, no DevTools, and no dart — only: bash + adb + python3.
# It discovers the app's VM Service URL from logcat, forwards the port with
# adb, and speaks the VM Service WebSocket protocol directly (an embedded
# stdlib-only python client) to stream the snapshot to a raw `dartheap` file.
#
# The output file is the same format as NativeRuntime.writeHeapSnapshotToFile,
# so it re-loads via leak_graph's `analyze.dart` / `HeapSnapshotGraph.fromChunks`.
set -eo pipefail

usage() {
  cat >&2 <<'EOF'
heapdump.sh — dump a live Dart heap snapshot from a device (adb + python3, no dart).

Usage: heapdump.sh [options]
  -o FILE    output path            (default: ./heap_<timestamp>.data)
  -p PKG     Android package id; if the VM Service URL isn't already in
             logcat, force-stop + relaunch the app to (re)log it
  -u URL     VM Service URL (http://127.0.0.1:PORT/TOKEN=/) — skip discovery
  -s SERIAL  adb device serial (when several devices are attached)
  -h         this help
  --selftest run the embedded protocol self-test (no device needed)
EOF
  exit "${1:-0}"
}

# --selftest can appear anywhere; handle it before touching adb.
for a in "$@"; do [ "$a" = "--selftest" ] && SELFTEST=1; done

OUT=""; PKG=""; URL=""; SERIAL=""
ORIG_PWD="$PWD"

if [ "${SELFTEST:-0}" != "1" ]; then
  while getopts ":o:p:u:s:h" opt; do
    case "$opt" in
      o) OUT="$OPTARG" ;;
      p) PKG="$OPTARG" ;;
      u) URL="$OPTARG" ;;
      s) SERIAL="$OPTARG" ;;
      h) usage 0 ;;
      \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
      :) echo "Option -$OPTARG requires a value" >&2; usage 2 ;;
    esac
  done
fi

command -v python3 >/dev/null || { echo "python3 not found on PATH" >&2; exit 1; }

# The VM Service WebSocket client (pure python stdlib). Read once into a var.
read -r -d '' PYSRC <<'PYCAP' || true
import base64, json, os, socket, struct, sys


def to_ws(uri):
    uri = uri.strip()
    if uri.startswith('http://'):
        uri = 'ws://' + uri[7:]
    elif uri.startswith('https://'):
        uri = 'wss://' + uri[8:]
    if uri.startswith('wss://'):
        scheme, rest = 'wss', uri[6:]
    elif uri.startswith('ws://'):
        scheme, rest = 'ws', uri[5:]
    else:
        raise ValueError('URI must be http(s):// or ws(s)://')
    if '/' in rest:
        hostport, path = rest.split('/', 1)
        path = '/' + path
    else:
        hostport, path = rest, '/'
    if not path.endswith('/ws'):
        path = path + ('' if path.endswith('/') else '/') + 'ws'
    if ':' in hostport:
        host, port = hostport.rsplit(':', 1)
        port = int(port)
    else:
        host, port = hostport, (443 if scheme == 'wss' else 80)
    return scheme, host, port, path


class Buffered:
    def __init__(self, sock, initial=b''):
        self.sock = sock
        self.buf = bytearray(initial)

    def recv_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError('websocket closed by peer')
            self.buf += chunk
        out = bytes(self.buf[:n])
        del self.buf[:n]
        return out

    def sendall(self, data):
        self.sock.sendall(data)


def send_frame(io, payload, opcode):
    header = bytearray([0x80 | opcode])
    n = len(payload)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header += struct.pack('>H', n)
    else:
        header.append(0x80 | 127)
        header += struct.pack('>Q', n)
    mask = os.urandom(4)
    header += mask
    masked = bytes(b ^ mask[i & 3] for i, b in enumerate(payload))
    io.sendall(bytes(header) + masked)


def read_frame(io):
    b0 = io.recv_exact(1)[0]
    fin = b0 & 0x80
    opcode = b0 & 0x0F
    b1 = io.recv_exact(1)[0]
    masked = b1 & 0x80
    n = b1 & 0x7F
    if n == 126:
        n = struct.unpack('>H', io.recv_exact(2))[0]
    elif n == 127:
        n = struct.unpack('>Q', io.recv_exact(8))[0]
    mask = io.recv_exact(4) if masked else b''
    payload = io.recv_exact(n) if n else b''
    if masked:
        payload = bytes(b ^ mask[i & 3] for i, b in enumerate(payload))
    return fin, opcode, payload


def recv_message(io):
    frames = []
    op = None
    while True:
        fin, opcode, payload = read_frame(io)
        if opcode == 0x8:
            raise ConnectionError('websocket closed')
        if opcode == 0x9:
            send_frame(io, payload, 0xA)
            continue
        if opcode == 0xA:
            continue
        if opcode in (0x1, 0x2):
            op = opcode
            frames.append(payload)
        elif opcode == 0x0:
            frames.append(payload)
        if fin:
            return op, b''.join(frames)


def handshake(sock, host, port, path):
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        'GET %s HTTP/1.1\r\n'
        'Host: %s:%d\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Key: %s\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n'
    ) % (path, host, port, key)
    sock.sendall(req.encode())
    resp = bytearray()
    while b'\r\n\r\n' not in resp:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError('no handshake response')
        resp += chunk
    head, leftover = resp.split(b'\r\n\r\n', 1)
    status = head.split(b'\r\n', 1)[0].decode('latin1')
    if '101' not in status:
        raise ConnectionError('handshake rejected: ' + status)
    return bytes(leftover)


def capture(uri, out):
    scheme, host, port, path = to_ws(uri)
    if scheme == 'wss':
        raise ValueError('TLS (wss) not supported; the VM service is ws://')
    sock = socket.create_connection((host, port), timeout=30)
    sock.settimeout(180)
    io = Buffered(sock, handshake(sock, host, port, path))

    def send(obj):
        send_frame(io, json.dumps(obj).encode('utf-8'), 0x1)

    send({'jsonrpc': '2.0', 'id': 1, 'method': 'streamListen',
          'params': {'streamId': 'HeapSnapshot'}})
    send({'jsonrpc': '2.0', 'id': 2, 'method': 'getVM'})

    isolate_id = None
    while isolate_id is None:
        op, msg = recv_message(io)
        if op == 0x1:
            obj = json.loads(msg.decode('utf-8'))
            if obj.get('id') == 2 and 'error' in obj:
                raise RuntimeError('getVM failed: %r' % obj['error'])
            if obj.get('id') == 2 and 'result' in obj:
                isolates = obj['result'].get('isolates') or []
                if not isolates:
                    raise RuntimeError('target VM has no isolates')
                main = next((i for i in isolates if i.get('name') == 'main'),
                            isolates[0])
                isolate_id = main['id']
                sys.stderr.write('Target isolate: %s (%s)\n'
                                 % (main.get('name'), isolate_id))

    send({'jsonrpc': '2.0', 'id': 3, 'method': 'requestHeapSnapshot',
          'params': {'isolateId': isolate_id}})

    total = 0
    with open(out, 'wb') as f:
        while True:
            op, msg = recv_message(io)
            if op == 0x1:
                # A JSON-RPC error to requestHeapSnapshot (id 3) means no binary
                # stream ever arrives — surface it instead of stalling to timeout.
                obj = json.loads(msg.decode('utf-8'))
                if obj.get('id') == 3 and 'error' in obj:
                    raise RuntimeError('requestHeapSnapshot failed: %r' % obj['error'])
                continue
            if op != 0x2:
                continue
            data_offset = struct.unpack_from('<I', msg, 0)[0]
            meta = msg[4:data_offset]
            f.write(msg[data_offset:])
            total += len(msg) - data_offset
            event = json.loads(meta.decode('utf-8')).get('params', {}).get('event', {})
            sys.stderr.write('\r  %.1f MiB' % (total / (1024.0 * 1024.0)))
            sys.stderr.flush()
            if event.get('last'):
                break
    sys.stderr.write('\n')
    try:
        send_frame(io, b'', 0x8)
    except Exception:
        pass
    sock.close()
    return total


class _MemSock:
    def __init__(self, data=b''):
        self.r = bytearray(data)
        self.w = bytearray()

    def recv(self, n):
        out = bytes(self.r[:n])
        del self.r[:n]
        return out

    def sendall(self, data):
        self.w += data


def _selftest():
    meta = json.dumps({'jsonrpc': '2.0', 'method': 'streamNotify',
                       'params': {'streamId': 'HeapSnapshot',
                                  'event': {'kind': 'HeapSnapshot', 'last': True}}}).encode()
    data = b'dartheap\x00\x01\x02payload'
    msg = struct.pack('<I', 4 + len(meta)) + meta + data
    off = struct.unpack_from('<I', msg, 0)[0]
    assert msg[off:] == data
    assert json.loads(msg[4:off].decode())['params']['event']['last'] is True

    for size in (0, 5, 125, 126, 200, 65535, 70000):
        payload = os.urandom(size)
        s = _MemSock()
        send_frame(Buffered(s), payload, 0x2)
        fin, op, got = read_frame(Buffered(_MemSock(bytes(s.w))))
        assert fin and op == 0x2 and got == payload, 'frame roundtrip @%d' % size

    parts = _MemSock()
    send_frame(Buffered(parts), b'PING', 0x9)

    def raw(fin, opcode, pl):
        m = _MemSock()
        send_frame(Buffered(m), pl, opcode)
        rb = bytearray(m.w)
        if not fin:
            rb[0] &= 0x7F
        return bytes(rb)

    stream = raw(False, 0x2, b'hello ') + raw(True, 0x0, b'world')
    op, got = recv_message(Buffered(_MemSock(bytes(parts.w) + stream)))
    assert op == 0x2 and got == b'hello world', repr(got)

    assert to_ws('http://127.0.0.1:41779/UwQAYQQ0uMY=/') == ('ws', '127.0.0.1', 41779, '/UwQAYQQ0uMY=/ws')
    print('selftest OK')


def main(argv):
    if len(argv) == 2 and argv[1] == '--selftest':
        _selftest()
        return 0
    if len(argv) != 3:
        sys.stderr.write('usage: <script> <vm-service-uri> <out.data> | --selftest\n')
        return 2
    n = capture(argv[1], argv[2])
    sys.stderr.write('Wrote %d bytes.\n' % n)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
PYCAP

run_py() {
  local tmp rc=0
  tmp="$(mktemp "${TMPDIR:-/tmp}/heapcap.XXXXXX")"
  printf '%s' "$PYSRC" > "$tmp"
  # `if` condition is exempt from set -e, so we can clean up on failure too.
  if python3 "$tmp" "$@"; then rc=0; else rc=$?; fi
  rm -f "$tmp"
  return "$rc"
}

# --selftest: verify the embedded protocol code, no device required.
if [ "${SELFTEST:-0}" = "1" ]; then
  run_py --selftest
  exit 0
fi

command -v adb >/dev/null || { echo "adb not found on PATH" >&2; exit 1; }

ADB=(adb)
[ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")

# 0. one usable device?
if ! "${ADB[@]}" get-state >/dev/null 2>&1; then
  echo "No single device selected. Attached devices:" >&2
  adb devices >&2
  echo "Pass -s <serial> to pick one." >&2
  exit 1
fi

# Pull the last "http://127.0.0.1:PORT/TOKEN=/" URL out of the logcat buffer.
find_url() {
  "${ADB[@]}" logcat -d 2>/dev/null \
    | grep -aoE 'http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+/' \
    | tail -n1
}

# 1. discover the VM Service URL (unless -u)
[ -z "$URL" ] && URL="$(find_url || true)"

# 1b. not in the buffer? relaunch (if -p) and poll for it
if [ -z "$URL" ] && [ -n "$PKG" ]; then
  echo "VM Service URL not in logcat — relaunching $PKG to log it…" >&2
  "${ADB[@]}" logcat -c || true
  "${ADB[@]}" shell am force-stop "$PKG" || true
  "${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    URL="$(find_url || true)"
    [ -n "$URL" ] && break
    sleep 0.5
  done
fi

if [ -z "$URL" ]; then
  echo "Could not find the Dart VM Service URL." >&2
  echo "Ensure the app is a debug/profile build and running, then re-run with" >&2
  echo "-p <package.id> to relaunch it, or pass -u <url> directly." >&2
  exit 1
fi
echo "VM Service: $URL" >&2

# 2. parse the device port and forward it (same port on the host)
PORT="$(printf '%s' "$URL" | sed -E 's#^http://127\.0\.0\.1:([0-9]+)/.*#\1#')"
case "$PORT" in
  ''|*[!0-9]*) echo "Could not parse a port from: $URL" >&2; exit 1 ;;
esac
echo "Forwarding host tcp:$PORT -> device tcp:$PORT" >&2
"${ADB[@]}" forward "tcp:$PORT" "tcp:$PORT" >/dev/null

# 3. output path (absolute, in the caller's directory)
if [ -z "$OUT" ]; then
  OUT="$ORIG_PWD/heap_$(date +%Y%m%d-%H%M%S).data"
else
  case "$OUT" in /*) : ;; *) OUT="$ORIG_PWD/$OUT" ;; esac
fi

# 4. capture over the forwarded VM Service (embedded python client)
echo "Capturing…" >&2
run_py "$URL" "$OUT"

echo "Done. Snapshot: $OUT" >&2
echo "  unforward: ${ADB[*]} forward --remove tcp:$PORT" >&2
