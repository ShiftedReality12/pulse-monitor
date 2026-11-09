#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/swiftpm/config .build/swiftpm/security
free_percent=$(memory_pressure | tail -1 | tr -cd '0-9')
if [[ -z "$free_percent" || "$free_percent" -lt 10 ]]; then
    print -u2 'Memory guard: below 10% or unreadable. Retry after two minutes; stop after one retry.'
    exit 75
fi
print "Memory guard: $free_percent% free"
case "${1:-}" in
  build) swift build -c release --disable-sandbox -j 4 --cache-path .build/swiftpm/cache --config-path .build/swiftpm/config --security-path .build/swiftpm/security ;;
  test)
    developer=$(xcode-select -p 2>/dev/null || true)
    frameworks=()
    if [[ -n "$developer" && -d "$developer/Library/Developer/Frameworks" ]]; then
        frameworks=(-Xswiftc -F -Xswiftc "$developer/Library/Developer/Frameworks" -Xlinker -rpath -Xlinker "$developer/Library/Developer/Frameworks")
    fi
    swift test --disable-sandbox -j 4 --cache-path .build/swiftpm/cache --config-path .build/swiftpm/config --security-path .build/swiftpm/security --disable-xctest --enable-swift-testing -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays "${frameworks[@]}" ;;
  *) print -u2 'Usage: scripts/check.sh build|test'; exit 2 ;;
esac
