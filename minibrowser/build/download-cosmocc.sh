#!/bin/sh
# Downloads the cosmocc toolchain into OUTPUT_DIR, mirroring the script
# cosmopolitan itself uses (build/download-cosmocc.sh upstream).
#
#   usage: build/download-cosmocc.sh OUTPUT_DIR VERSION
#
# cosmocc produces Actually Portable Executables: one file that runs on
# Linux, macOS, Windows and the BSDs. https://github.com/jart/cosmopolitan

OUTPUT_DIR=${1:?OUTPUT_DIR}
COSMOCC_VERSION=${2:?COSMOCC_VERSION}
URL1="https://github.com/jart/cosmopolitan/releases/download/${COSMOCC_VERSION}/cosmocc-${COSMOCC_VERSION}.zip"
URL2="https://cosmo.zip/pub/cosmocc/cosmocc-${COSMOCC_VERSION}.zip"

abort() {
  printf '%s\n' "download terminated." >&2
  exit 1
}

OUTPUT_DIR=${OUTPUT_DIR%/}
if [ -d "${OUTPUT_DIR}" ]; then
  exit 0
fi

if ! UNZIP=$(command -v unzip 2>/dev/null); then
  printf '%s\n' "$0: fatal error: you need the unzip command" >&2
  abort
fi
if WGET=$(command -v wget 2>/dev/null); then
  DOWNLOAD=$WGET
  DOWNLOAD_ARGS=-O
elif CURL=$(command -v curl 2>/dev/null); then
  DOWNLOAD=$CURL
  DOWNLOAD_ARGS=-fLo
else
  printf '%s\n' "$0: fatal error: you need either wget or curl" >&2
  abort
fi

OLDPWD=$PWD
OUTPUT_TMP="${OUTPUT_DIR}.tmp.$$/"
mkdir -p "${OUTPUT_TMP}" || abort
cd "${OUTPUT_TMP}" || abort
die() {
  cd "${OLDPWD}"
  rm -rf "${OUTPUT_TMP}"
  abort
}

# two urls: github releases and cosmo.zip, for outages and firewalls
if ! "${DOWNLOAD}" ${DOWNLOAD_ARGS} cosmocc.zip "${URL1}"; then
  rm -f cosmocc.zip
  "${DOWNLOAD}" ${DOWNLOAD_ARGS} cosmocc.zip "${URL2}" || die
fi
"${UNZIP}" -q cosmocc.zip || die
rm -f cosmocc.zip

cd "${OLDPWD}" || die
mv "${OUTPUT_TMP}" "${OUTPUT_DIR}" || die
BASE=$(basename "${OUTPUT_DIR}")
DIR=$(dirname "${OUTPUT_DIR}")
ln -sfn "$BASE" "$DIR/current"
