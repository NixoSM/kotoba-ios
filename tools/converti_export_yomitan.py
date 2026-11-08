#!/usr/bin/env python3
"""
Converte l'export del database di Yomitan (yomitan-dictionaries-*.json, anche
di molti GB) in un file .zip per ogni dizionario, nel formato standard di
Yomitan. Gli zip si importano poi uno per uno in Kotoba sull'iPhone.

Uso:
    py converti_export_yomitan.py EXPORT.json                 # tutti i dizionari
    py converti_export_yomitan.py EXPORT.json --elenco        # mostra solo i titoli
    py converti_export_yomitan.py EXPORT.json --solo "JMdict" "大辞林"   # solo alcuni (basta una parte del titolo)

Usa solo la libreria standard di Python e legge il file a pezzi, quindi non
serve RAM pari alla dimensione dell'export.
"""
import argparse
import base64
import codecs
import json
import os
import re
import sys
import time
import zipfile

CHUNK = 16 * 1024 * 1024
BANK_SIZE = 10000
WS = " \t\r\n"


class JsonStream:
    """Reads a huge JSON file piece by piece and decodes values on demand."""

    def __init__(self, path):
        self.f = open(path, "rb")
        self.size = os.path.getsize(path)
        self.decoder = codecs.getincrementaldecoder("utf-8")()
        self.json = json.JSONDecoder()
        self.buf = ""
        self.pos = 0
        self.eof = False
        self.read_bytes = 0

    def _more(self):
        if self.eof:
            return False
        data = self.f.read(CHUNK)
        self.read_bytes += len(data)
        if not data:
            self.eof = True
            self.buf += self.decoder.decode(b"", final=True)
            return False
        if self.pos > len(self.buf) // 2:
            self.buf = self.buf[self.pos:]
            self.pos = 0
        self.buf += self.decoder.decode(data)
        return True

    def find(self, token):
        """Moves just past the next occurrence of token. Returns False at end of file."""
        while True:
            i = self.buf.find(token, self.pos)
            if i >= 0:
                self.pos = i + len(token)
                return True
            # Keep a tail in case the token is split between two chunks.
            self.pos = max(self.pos, len(self.buf) - len(token))
            if not self._more():
                return False

    def peek(self):
        while True:
            while self.pos < len(self.buf) and self.buf[self.pos] in WS:
                self.pos += 1
            if self.pos < len(self.buf):
                return self.buf[self.pos]
            if not self._more():
                return ""

    def skip(self, n=1):
        self.pos += n

    def value(self):
        self.peek()
        while True:
            try:
                value, end = self.json.raw_decode(self.buf, self.pos)
                self.pos = end
                return value
            except json.JSONDecodeError:
                if not self._more():
                    raise


def tables(stream):
    """Yields (table_name, row) for every row in the export."""
    while stream.find('"tableName"'):
        if stream.peek() == ":":
            stream.skip()
        name = stream.value()
        if not stream.find('"rows"'):
            return
        if stream.peek() == ":":
            stream.skip()
        if stream.peek() != "[":
            raise ValueError("Formato inatteso: 'rows' non è una lista")
        stream.skip()
        while True:
            c = stream.peek()
            if c == ",":
                stream.skip()
                continue
            if c == "]":
                stream.skip()
                break
            if c == "":
                return
            row = stream.value()
            if isinstance(row, list) and len(row) == 2:  # outbound table: [key, value]
                row = row[1]
            yield name, row


def safe_filename(title):
    name = re.sub(r'[\\/:*?"<>|]', "_", title).strip().rstrip(".")
    return name or "dizionario"


class DictionaryWriter:
    KINDS = {
        "terms": "term_bank",
        "termMeta": "term_meta_bank",
        "kanji": "kanji_bank",
        "kanjiMeta": "kanji_meta_bank",
        "tagMeta": "tag_bank",
    }

    def __init__(self, folder, summary):
        self.title = summary["title"]
        self.path = os.path.join(folder, safe_filename(self.title) + ".zip")
        self.zip = zipfile.ZipFile(self.path, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
        index = {k: v for k, v in summary.items() if k not in ("id", "prefixWildcardsSupported", "counts", "importDate", "styles", "yomitanVersion", "importSuccess")}
        index["format"] = index.pop("version", index.get("format", 3))
        self.zip.writestr("index.json", json.dumps(index, ensure_ascii=False))
        if summary.get("styles"):
            self.zip.writestr("styles.css", summary["styles"])
        self.pending = {k: [] for k in self.KINDS.values()}
        self.counters = {k: 0 for k in self.KINDS.values()}
        self.rows = 0

    def add(self, table, row):
        kind = self.KINDS[table]
        self.pending[kind].append(to_bank_row(table, row))
        self.rows += 1
        if len(self.pending[kind]) >= BANK_SIZE:
            self.flush(kind)

    def add_media(self, row):
        content = row.get("content")
        if isinstance(content, dict):  # typeson: {"$t": ..., "v": base64}
            content = content.get("v")
        if isinstance(content, str):
            content = base64.b64decode(content)
        if isinstance(content, (bytes, bytearray)) and row.get("path"):
            self.zip.writestr(row["path"], content)

    def flush(self, kind):
        rows = self.pending[kind]
        if not rows:
            return
        self.counters[kind] += 1
        self.zip.writestr(f"{kind}_{self.counters[kind]}.json", json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
        self.pending[kind] = []

    def close(self):
        for kind in self.pending:
            self.flush(kind)
        self.zip.close()


def to_bank_row(table, r):
    if table == "terms":
        return [r.get("expression", ""), r.get("reading", ""), r.get("definitionTags", r.get("tags", "")) or "",
                r.get("rules", ""), r.get("score", 0), r.get("glossary", []), r.get("sequence", 0), r.get("termTags", "") or ""]
    if table in ("termMeta", "kanjiMeta"):
        return [r.get("expression", r.get("character", "")), r.get("mode", ""), r.get("data")]
    if table == "kanji":
        return [r.get("character", ""), r.get("onyomi", ""), r.get("kunyomi", ""), r.get("tags", ""),
                r.get("meanings", []), r.get("stats", {})]
    if table == "tagMeta":
        return [r.get("name", ""), r.get("category", ""), r.get("order", 0), r.get("notes", ""), r.get("score", 0)]
    raise KeyError(table)


def main():
    p = argparse.ArgumentParser(description="Converte l'export dei dizionari di Yomitan in file .zip separati.")
    p.add_argument("export", help="il file yomitan-dictionaries-....json")
    p.add_argument("--uscita", help="cartella dove salvare gli zip (predefinita: accanto all'export)")
    p.add_argument("--elenco", action="store_true", help="mostra solo i dizionari presenti")
    p.add_argument("--solo", nargs="+", metavar="TITOLO", help="converti solo i dizionari il cui titolo contiene questo testo")
    a = p.parse_args()

    out = a.uscita or os.path.join(os.path.dirname(os.path.abspath(a.export)), "kotoba-dizionari")
    stream = JsonStream(a.export)
    writers = {}
    wanted = None
    started = time.time()
    last_report = 0.0
    seen_titles = []

    for table, row in tables(stream):
        if table == "dictionaries":
            title = row.get("title", "?")
            seen_titles.append(title)
            if a.elenco:
                continue
            if a.solo and not any(s.lower() in title.lower() for s in a.solo):
                continue
            os.makedirs(out, exist_ok=True)
            writers[title] = DictionaryWriter(out, row)
            continue
        if a.elenco:
            break  # the dictionaries table comes first: we have every title
        writer = writers.get(row.get("dictionary"))
        if writer is None:
            continue
        if table == "media":
            writer.add_media(row)
        elif table in DictionaryWriter.KINDS:
            writer.add(table, row)

        now = time.time()
        if now - last_report > 2:
            last_report = now
            pct = 100.0 * stream.read_bytes / max(stream.size, 1)
            sys.stdout.write(f"\r  {pct:5.1f}%  tabella {table:<10}  {sum(w.rows for w in writers.values()):>12,} righe")
            sys.stdout.flush()

    if a.elenco:
        print("Dizionari nell'export:")
        for t in seen_titles:
            print("  -", t)
        return

    print()
    for w in writers.values():
        w.close()
        size = os.path.getsize(w.path) / 1024 / 1024
        print(f"  {w.title}: {w.rows:,} righe -> {os.path.basename(w.path)} ({size:,.0f} MB)")
    print(f"Fatto in {(time.time() - started) / 60:.1f} minuti. Gli zip sono in: {out}")


if __name__ == "__main__":
    main()
