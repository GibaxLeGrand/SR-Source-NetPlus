#!/usr/bin/env bash
# =============================================================================
# Sonic Riders: Source (SR-Source) - checks folders whose names aren't plain
# ASCII, after tools/build_tools.sh --chassis.
#
# GitHub issue #5: on Windows, a user folder with an accent (a user named Pao
# with a tilde on the a) broke the extraction and the game's start, because
# the paths reached SDL and the game in the wrong text encoding.
# ModernGekko's moderngekko_text_paths_test checks it in a folder named with
# letters from several languages, and starts the real runner there as the
# launcher does. The release workflow runs this on Linux and Windows after the
# build: a change that brings the bug back stops the release before anyone
# gets it.
#
#   tools/check_unicode_paths.sh             # after tools/build_tools.sh --chassis
#   BUILD_DIR=/path/to/chassis tools/check_unicode_paths.sh
#
# It ends with "text paths: ok", or says which check FAILED.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build/chassis}"

die() { echo "error: $*" >&2; exit 1; }

EXE=""
NATIVE=(echo)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    EXE=".exe"
    NATIVE=(cygpath -m)
    ;;
esac

[[ -d "$BUILD" ]] || die "no build in $BUILD: run tools/build_tools.sh --chassis first"

# Not part of a normal build: made here, from the same configuration.
cmake --build "$BUILD" --target moderngekko_text_paths_test

TEST="$(find "$BUILD" -type f -name "moderngekko_text_paths_test$EXE" -print -quit)"
RUNNER="$(find "$BUILD" -type f -name "moderngekko-run$EXE" -print -quit)"
[[ -n "$TEST" ]] || die "moderngekko_text_paths_test$EXE is missing in $BUILD"
[[ -n "$RUNNER" ]] || die "moderngekko-run$EXE is missing in $BUILD"

# The test makes its folder with the unusual name inside this one.
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/sr-source-text-paths"

"$TEST" --work "$("${NATIVE[@]}" "$WORK")" --runner "$("${NATIVE[@]}" "$RUNNER")"
