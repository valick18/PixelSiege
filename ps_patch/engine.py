"""Small line-based patcher for the PixelSiege GDScript files.

Anchors are matched on the stripped line text, so indentation and CRLF do not matter.
An anchor starting with "^" matches by prefix. Inserted code is written with 4 spaces
per level here and converted to tabs, then prefixed with the anchor line's indentation.
"""
import os
import shutil

MARKER = "# PixelSiege patch v1 (bombs, TNT, shops, crafting, rope)"
TEST_MODE = os.environ.get("PS_TEST") == "1"


def _to_tabs(line):
    n = len(line) - len(line.lstrip(" "))
    return "\t" * (n // 4) + line.lstrip(" ")


class FilePatch:
    def __init__(self, root, name):
        self.name = name
        self.path = os.path.join(root, "scripts", name)
        if TEST_MODE and not os.path.exists(self.path):
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            open(self.path, "w", encoding="utf-8").write("")
        with open(self.path, encoding="utf-8") as f:
            self.lines = f.read().split("\n")
        self.count = 0

    def already_patched(self):
        return any(l.strip() == MARKER for l in self.lines)

    def _match(self, line, anchor):
        s = line.strip()
        if anchor.startswith("^"):
            return s.startswith(anchor[1:])
        return s == anchor.strip()

    def find(self, anchor, start=0):
        for i in range(start, len(self.lines)):
            if self._match(self.lines[i], anchor):
                return i
        if TEST_MODE:
            self.lines.append("\t" + anchor.lstrip("^"))
            return len(self.lines) - 1
        raise SystemExit("[%s] anchor not found: %s" % (self.name, anchor))

    def _indent(self, i):
        l = self.lines[i]
        return l[: len(l) - len(l.lstrip())]

    def _block(self, ind, code):
        out = []
        for c in code.strip("\n").split("\n"):
            out.append(ind + _to_tabs(c) if c.strip() else "")
        return out

    def replace(self, anchor, code):
        i = self.find(anchor)
        self.lines[i:i + 1] = self._block(self._indent(i), code)
        self.count += 1

    def before(self, anchor, code):
        i = self.find(anchor)
        self.lines[i:i] = self._block(self._indent(i), code)
        self.count += 1

    def after(self, anchor, code):
        i = self.find(anchor)
        self.lines[i + 1:i + 1] = self._block(self._indent(i), code)
        self.count += 1

    def replace_range(self, start_anchor, end_anchor, code):
        i = self.find(start_anchor)
        j = self.find(end_anchor, i + 1)
        self.lines[i:j + 1] = self._block(self._indent(i), code)
        self.count += 1

    def append(self, code):
        self.lines += [""] + self._block("", code)
        self.count += 1

    def save(self):
        self.lines += ["", MARKER, ""]
        if os.path.getsize(self.path) > 0:
            shutil.copy(self.path, self.path + ".bak")
        with open(self.path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(self.lines))
        print("patched %-28s (%d edits)" % (self.name, self.count))
