import urllib.request
import urllib.parse
import base64
import re
import os
import subprocess
import sys

SOURCES_FILE = "sources.txt"
COUNTRIES_FILE = "filter-countries.txt"
TRANSPORT_FILE = "filter-transport.txt"
OUTPUT_FILE = "output.txt"

def read_config(path):
    """Reads the file, ignoring empty lines and comments (#)"""
    if not os.path.exists(path):
        print(f"[ERROR] File not found: {path}")
        sys.exit(1)

    with open(path, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip() and not line.strip().startswith('#')]

def fetch_subscriptions(urls):
    """Loads and parses subscriptions, supporting both plain text and Base64"""
    results = []
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}

    for url in urls:
        if not url.startswith('https'):
            print(f"[SKIP] Invalid URL: {url}")
            continue

        print(f"[INFO] Fetching: {url}")
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as response:
                raw_data = response.read()

            # Try to decode as UTF-8 text
            try:
                text = raw_data.decode('utf-8')
            except UnicodeDecodeError:
                text = ""

            lines = []
            # If '://' is not in the text, it is highly likely to be Base64
            if '://' not in text and len(text) > 10:
                try:
                    # Add padding for correct Base64 decoding
                    padded = text + "=" * ((4 - len(text) % 4) % 4)
                    decoded = base64.b64decode(padded).decode('utf-8')
                    lines = decoded.splitlines()
                except Exception:
                    lines = text.splitlines()
            else:
                lines = text.splitlines()

            # Fallback: if it's a single line but contains protocols, extract them using regex
            if len(lines) <= 1 and '://' in text:
                matches = re.findall(r'(vless|vmess|trojan|ss)://[^\s\r\n]+', text, re.IGNORECASE)
                lines = [m.strip() for m in matches if m.strip()]

            # Add only valid lines with protocols
            for line in lines:
                line = line.strip()
                if re.match(r'^(vless|vmess|trojan|ss)://', line, re.IGNORECASE):
                    results.append(line)

        except Exception as e:
            print(f"[WARNING] Failed to fetch {url}: {e}")

    return results

def filter_by_countries(lines, countries):
    """Filters by countries, checking the link fragment (# or %23)"""
    if not countries:
        return lines

    escaped = [re.escape(c) for c in countries]
    # Look for the country after # or %23 (URL-encoded #)
    pattern = re.compile(r'(#|%23).*?(' + '|'.join(escaped) + r')', re.IGNORECASE)
    return [line for line in lines if pattern.search(line)]

def filter_by_transport(lines, transports):
    """Filters by type, security, network, mode parameters"""
    if not transports:
        return lines

    escaped = [re.escape(t) for t in transports]
    pattern = re.compile(r'(type|security|network|mode)=(' + '|'.join(escaped) + r')', re.IGNORECASE)
    return [line for line in lines if pattern.search(line)]

def deduplicate_functionally(lines):
    """Removes functional duplicates (same server, different parameters)"""
    seen_cores = set()
    unique_lines = []

    for line in lines:
        try:
            parsed = urllib.parse.urlparse(line)
            netloc = parsed.netloc

            # Split user@host:port
            if '@' in netloc:
                user, host_port = netloc.split('@', 1)
            else:
                user, host_port = "", netloc

            # Correct handling of IPv6 [::1]:port and standard host:port
            if host_port.startswith('['):
                bracket_end = host_port.find(']')
                host = host_port[:bracket_end+1]
                port = host_port[bracket_end+1:].lstrip(':')
            elif ':' in host_port:
                host, port = host_port.rsplit(':', 1)
            else:
                host, port = host_port, ""

            # Deduplication key: protocol + user + host + port
            core_key = (parsed.scheme.lower(), user, host.lower(), port)

            if core_key not in seen_cores:
                seen_cores.add(core_key)
                unique_lines.append(line)
        except Exception:
            # If parsing fails, leave as is (protection against malformed links)
            if line not in seen_cores:
                seen_cores.add(line)
                unique_lines.append(line)

    return unique_lines

def copy_to_clipboard(text):
    """Attempts to copy to clipboard (Windows)"""
    try:
        subprocess.run(['clip'], input=text, encoding='utf-8', check=True)
        return True
    except Exception:
        return False

def main():
    sources = read_config(SOURCES_FILE)
    countries = read_config(COUNTRIES_FILE)
    transports = read_config(TRANSPORT_FILE)

    if not sources:
        print("[ERROR] sources.txt is empty or contains no valid URLs.")
        sys.exit(1)

    raw_lines = fetch_subscriptions(sources)
    print(f"[DEBUG] Fetched raw lines: {len(raw_lines)}")

    if not raw_lines:
        print("[ERROR] Failed to fetch any links from sources.")
        sys.exit(1)

    filtered = filter_by_countries(raw_lines, countries)
    print(f"[DEBUG] After country filter: {len(filtered)}")

    filtered = filter_by_transport(filtered, transports)
    print(f"[DEBUG] After transport filter: {len(filtered)}")

    print("[INFO] Removing functional duplicates...")
    final_lines = deduplicate_functionally(filtered)

    if not final_lines:
        print("[WARNING] No lines left after filtering.")
        sys.exit(0)

    # Output result
    output_text = '\n'.join(final_lines)

    print("\n" + "="*50)
    if copy_to_clipboard(output_text):
        print(f"{len(final_lines)} lines copied to clipboard!")
    else:
        print("Failed to copy to clipboard.")

    # Always save to file as a reliable fallback
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write(output_text + '\n')
    print(f"Result saved to: {os.path.abspath(OUTPUT_FILE)}")
    print("="*50 + "\n")

if __name__ == "__main__":
    main()
