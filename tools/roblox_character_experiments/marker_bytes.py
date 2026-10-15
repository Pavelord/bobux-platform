"""Strictly decode only our anchored UTF-8 telemetry, ignoring native noise.

Studio logs may contain non-UTF-8 application messages. Never decode them, and
never replace/repair a malformed byte in an actual own marker payload. Such
payloads are evidence integrity issues and must make the caller BLOCKED.
"""

HEADER = b"[FLog::CreatorOutput]"
ASCII_WHITESPACE = b" \t\r\n\v\f"


def marker_payload(line, marker):
    """Only actual Output payload may match; Command Bar echo starts '> code'."""
    payload = line.strip()
    header = HEADER.decode("ascii")
    if header in payload:
        payload = payload.split(header, 1)[1].lstrip()
    if not payload.startswith(marker):
        return None
    return payload[len(marker):]


def read_marker_bytes(data, markers):
    """Return filtered text and integrity issues with original byte/line offsets.

    Decode the selected payload only. Native prefixes can be arbitrary bytes;
    filtering those prefixes never changes the reconstructed own raw telemetry.
    """
    if not isinstance(data, bytes):
        raise TypeError("native log input must be bytes")
    prefixes = [(marker, marker.encode("ascii")) for marker in markers]
    retained, issues, byte_offset = [], [], 0
    # Split only physical LF/CRLF lines, not arbitrary control bytes in data.
    for line_number, original in enumerate(data.split(b"\n"), 1):
        line = original
        if line_number == 1 and line.startswith(b"\xef\xbb\xbf"):
            line = line[3:]
        payload = line.lstrip(ASCII_WHITESPACE)
        if HEADER in payload:
            payload = payload.split(HEADER, 1)[1].lstrip(ASCII_WHITESPACE)
        for marker, prefix in prefixes:
            if not payload.startswith(prefix):
                continue
            try:
                decoded = payload[len(prefix):].rstrip(b"\r").decode("utf-8", errors="strict")
            except UnicodeDecodeError as exc:
                # Diagnose coordinates without leaking/guessing any source text.
                location = original.find(payload) + len(prefix) + exc.start
                issues.append(f"invalid UTF-8 in own marker {marker.strip()} at native line {line_number}, byte {byte_offset + location}")
            else:
                retained.append(marker + decoded)
            break
        byte_offset += len(original) + 1
    return "\n".join(retained), issues
