#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p .build
clang -I Sources/CSensors/include -o .build/process_record_race Tests/Fixtures/process_record_race.c -framework IOKit -framework CoreFoundation
.build/process_record_race
python3 Tests/Fixtures/signing_selection.py
exec "${0:A:h}/check.sh" test
