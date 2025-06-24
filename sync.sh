#!/bin/bash

echo
echo "--------------------------------------"
echo "          AOSP 16.0 Syncbot           "
echo "                  by                  "
echo "                ponces                "
echo "--------------------------------------"
echo

set -e

export TD_BRANCH="android-16.0"

[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="$PWD/output"
[ -z "$BUILD_ROOT" ] && BUILD_ROOT="$PWD/treble_aosp"

initRepos() {
    echo "--> Getting latest upstream version"
    aosp=$(curl -sL https://github.com/TrebleDroid/treble_manifest/raw/$TD_BRANCH/replace.xml | grep -oP "${TD_BRANCH}.0_r\d+" | head -1)

    echo "--> Initializing workspace"
    repo init -u https://android.googlesource.com/platform/manifest -b "$aosp"
    echo

    echo "--> Preparing local manifest"
    if [ -d .repo/local_manifests ]; then
        (cd .repo/local_manifests; git fetch; git reset --hard; git checkout origin/$TD_BRANCH)
    else
        git clone https://github.com/TrebleDroid/treble_manifest .repo/local_manifests -b $TD_BRANCH
    fi
    echo
}

syncRepos() {
    echo "--> Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --ignore=2) || repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --ignore=2)
    echo
}

generatePatches() {
    echo "--> Generating patches"
    rm -rf patches.zip
    curl -sfL https://github.com/TrebleDroid/treble_experimentations/raw/master/list-patches.sh -o list-patches.sh
    bash list-patches.sh
    mkdir -p $OUTPUT_DIR
    mv patches.zip $OUTPUT_DIR/patches.zip
    echo
}

updatePatches() {
    echo "--> Updating patches"
    unzip $OUTPUT_DIR/patches.zip -d $OUTPUT_DIR/patches
    cp -r $OUTPUT_DIR/patches/patches $BUILD_ROOT/patches/trebledroid
    echo
}

START=$(date +%s)

initRepos
syncRepos
generatePatches
#updatePatches

END=$(date +%s)
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))

echo "--> Syncbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo
