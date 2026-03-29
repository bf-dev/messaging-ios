#!/usr/bin/env python3
"""Repo-local Swift lint checks that do not require Xcode or swiftc.

This intentionally focuses on issues that are easy to miss before pushing:
- duplicate function signatures in the same file
- unused results from becomeFirstResponder()/resignFirstResponder()
- duplicate accessibilityIdentifier values across the scanned files
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable, List, Tuple

ROOT = Path(__file__).resolve().parent.parent
FUNC_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:override\s+)?func\s+(\w+)\s*\(([^)]*)\)")
ACCESSIBILITY_ID_RE = re.compile(r"accessibilityIdentifier\s*=\s*\"([^\"]+)\"")
TYPE_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|internal|private|fileprivate|open)?\s*(?:final\s+)?(?:class|struct|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)")


class Issue(Tuple[str, int, str]):
    pass


def tracked_swift_files() -> List[Path]:
    try:
        result = subprocess.run(
            ["git", "ls-files", "*.swift"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        files = [ROOT / line for line in result.stdout.splitlines() if line.strip()]
        return sorted(files)
    except Exception:
        return sorted(ROOT.rglob("*.swift"))


def iter_swift_files(paths: Iterable[str]) -> List[Path]:
    if not paths:
        return tracked_swift_files()

    files: List[Path] = []
    for raw in paths:
        candidate = (ROOT / raw).resolve() if not Path(raw).is_absolute() else Path(raw)
        if candidate.is_dir():
            files.extend(sorted(candidate.rglob("*.swift")))
        elif candidate.suffix == ".swift" and candidate.exists():
            files.append(candidate)
    return sorted({path for path in files if path.exists()})


def normalize_signature(name: str, params: str) -> str:
    compact = re.sub(r"\s+", "", params)
    return f"{name}({compact})"


def has_unused_responder_result(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False

    call_name = None
    if ".becomeFirstResponder()" in stripped:
        call_name = ".becomeFirstResponder()"
    elif ".resignFirstResponder()" in stripped:
        call_name = ".resignFirstResponder()"
    else:
        return False

    if not stripped.endswith(call_name[1:]):
        return False

    prefix = stripped.split(call_name, 1)[0]
    if "=" in prefix:
        return False
    if prefix.startswith(("return ", "_ = ", "let ", "var ")):
        return False
    if "func " in stripped:
        return False
    return True


def lint_file(path: Path) -> List[Tuple[str, int, str]]:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        text = path.read_text(encoding="utf-8", errors="ignore")

    issues: List[Tuple[str, int, str]] = []
    seen_signatures: dict[tuple[str, str], int] = {}
    type_stack: List[tuple[str, int]] = []
    brace_depth = 0

    for line_number, line in enumerate(text.splitlines(), start=1):
        while type_stack and brace_depth < type_stack[-1][1]:
            type_stack.pop()

        type_match = TYPE_RE.match(line)
        opens = line.count("{")
        closes = line.count("}")
        if type_match and opens > closes:
            type_stack.append((type_match.group(1), brace_depth + opens - closes))

        func_match = FUNC_RE.match(line)
        if func_match:
            signature = normalize_signature(func_match.group(1), func_match.group(2))
            type_name = ".".join(name for name, _ in type_stack) or "__file__"
            key = (type_name, signature)
            previous_line = seen_signatures.get(key)
            if previous_line is not None:
                issues.append((str(path.relative_to(ROOT)), line_number, f"duplicate function signature '{type_name}.{signature}' (first seen on line {previous_line})"))
            else:
                seen_signatures[key] = line_number

        if has_unused_responder_result(line):
            issues.append((str(path.relative_to(ROOT)), line_number, "unused result from becomeFirstResponder()/resignFirstResponder(); assign to '_' explicitly"))

        brace_depth += opens - closes

    return issues


def find_duplicate_accessibility_ids(files: Iterable[Path]) -> List[Tuple[str, int, str]]:
    locations: dict[str, List[Tuple[str, int]]] = defaultdict(list)
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = path.read_text(encoding="utf-8", errors="ignore")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for match in ACCESSIBILITY_ID_RE.finditer(line):
                locations[match.group(1)].append((str(path.relative_to(ROOT)), line_number))

    issues: List[Tuple[str, int, str]] = []
    for identifier, refs in sorted(locations.items()):
        if len(refs) < 2:
            continue
        formatted_refs = ", ".join(f"{file}:{line}" for file, line in refs)
        file, line = refs[0]
        issues.append((file, line, f"duplicate accessibilityIdentifier '{identifier}' also found at {formatted_refs}"))
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description="Run lightweight repo-local Swift lint checks.")
    parser.add_argument("paths", nargs="*", help="Optional files or directories to lint. Defaults to tracked .swift files.")
    args = parser.parse_args()

    files = iter_swift_files(args.paths)
    if not files:
        print("No Swift files found.")
        return 0

    issues: List[Tuple[str, int, str]] = []
    for path in files:
        issues.extend(lint_file(path))
    issues.extend(find_duplicate_accessibility_ids(files))
    issues.sort(key=lambda item: (item[0], item[1], item[2]))

    if issues:
        print(f"Swift local lint found {len(issues)} issue(s):")
        for file, line, message in issues:
            print(f"- {file}:{line}: {message}")
        return 1

    print(f"Swift local lint passed ({len(files)} files scanned).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
