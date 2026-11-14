"""Scan SavedVariables dumps for private data before they are stored, ingested or shared.

Usage: python3 -I tools/privacy_scan.py FILE [FILE ...]
Exit status 1 when anything is found. It reports the kind of finding and the line
number, never the matching text, so the terminal does not repeat what it flags.
"""
import re
import sys

PATTERNS = {
    "character GUID": re.compile(r"Player-\d+-[0-9A-Fa-f]+"),
    "battletag": re.compile(r"\b[^\W\d_]\w{2,11}#\d{3,5}\b"),
    "email address": re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"),
    "seller/bidder key": re.compile(r'\["(?:owner|owners|ownerName|ownerAccountID|bidder|bidderName|buyer|seller)"\]'),
}


def scan(text):
    """Return a list of (kind, line number) findings."""
    findings = []
    for number, line in enumerate(text.splitlines(), 1):
        for kind, pattern in PATTERNS.items():
            if pattern.search(line):
                findings.append((kind, number))
    return findings


def main(paths):
    status = 0
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as fh:
            findings = scan(fh.read())
        if findings:
            status = 1
            kinds = sorted({k for k, _ in findings})
            first = ", ".join(f"line {n} ({k})" for k, n in findings[:5])
            print(f"PRIVACY: {path}: {len(findings)} finding(s) of {', '.join(kinds)}: {first}")
        else:
            print(f"privacy scan ok: {path}")
    return status


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    sys.exit(main(sys.argv[1:]))
