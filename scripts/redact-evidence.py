#!/usr/bin/env python3
"""Redact the current home prefix from streamed diagnostic evidence."""
import pathlib
import sys
for line in sys.stdin:
    sys.stdout.write(line.replace(str(pathlib.Path.home()), "~"))
    sys.stdout.flush()
