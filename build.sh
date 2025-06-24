#!/bin/bash

echo
echo "--------------------------------------"
echo "          AOSP 16.0 Buildbot          "
echo "                  by                  "
echo "                ponces                "
echo "--------------------------------------"
echo

set -e

export BUILD_NUMBER="$(date +%y%m%d)"

[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="$PWD/output"
[ -z "$BUILD_ROOT" ] && BUILD_ROOT="$PWD/treble_aosp"

initRepos() {
    echo "--> Initializing workspace"
    repo init -u https://android.googlesource.com/platform/manifest -b android-16.0.0_r2 --git-lfs
    echo

    echo "--> Preparing local manifest"
    mkdir -p .repo/local_manifests
    cp $BUILD_ROOT/build/default.xml .repo/local_manifests/default.xml
    cp $BUILD_ROOT/build/remove.xml .repo/local_manifests/remove.xml
    echo
}

syncRepos() {
    echo "--> Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --ignore=2) || repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --ignore=2)
    echo
}

applyPatches() {
    echo "--> Applying TrebleDroid patches"
    bash $BUILD_ROOT/patch.sh $BUILD_ROOT trebledroid
    echo

    echo "--> Applying personal patches"
    bash $BUILD_ROOT/patch.sh $BUILD_ROOT personal
    echo

    echo "--> Generating makefiles"
    cd device/phh/treble
    cp $BUILD_ROOT/build/aosp.mk .
    bash generate.sh aosp
    cd ../../..
    echo
}

setupEnv() {
    echo "--> Setting up build environment"
    mkdir -p $OUTPUT_DIR
    source build/envsetup.sh
    source build/core/build_id.mk
    echo
}

buildTrebleApp() {
    echo "--> Building treble_app"
    cd treble_app
    bash build.sh release
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
    echo
}

buildVariant() {
    echo "--> Building $1"
    lunch "$1"-bp2a-userdebug
    make -j$(nproc --ignore=2) installclean
    make -j$(nproc --ignore=2) systemimage
    make -j$(nproc --ignore=2) target-files-package otatools
    bash $BUILD_ROOT/sign.sh "vendor/ponces-priv/keys" $OUT/signed-target_files.zip
    unzip -joq $OUT/signed-target_files.zip IMAGES/system.img -d $OUT
    mv $OUT/system.img $OUTPUT_DIR/system-"$1".img
    echo
}

buildVariants() {
    buildVariant treble_arm64_bvN
    buildVariant treble_arm64_bgN
}

generatePackages() {
    echo "--> Generating packages"
    buildDate="$(date +%Y%m%d)"
    find $OUTPUT_DIR/ -name "system-treble_*.img" | while read file; do
        filename="$(basename $file)"
        [[ "$filename" == *"_bvN"* ]] && variant="vanilla" || variant="gapps"
        name="aosp-arm64-ab-${variant}-16.0-$buildDate"
        xz -cv "$file" -T0 > $OUTPUT_DIR/"$name".img.xz
    done
    rm -rf $OUTPUT_DIR/system-*.img
    echo
}

generateOta() {
    echo "--> Generating OTA file"
    version="$(date +v%Y.%m.%d)"
    buildDate="$(date +%Y%m%d)"
    timestamp="$START"
    json="{\"version\": \"$version\",\"date\": \"$timestamp\",\"variants\": ["
    find $OUTPUT_DIR/ -name "aosp-*-16.0-$buildDate.img.xz" | sort | {
        while read file; do
            filename="$(basename $file)"
            [[ "$filename" == *"-vanilla"* ]] && variant="v" || variant="g"
            name="treble_arm64_b${variant}N"
            size=$(wc -c $file | awk '{print $1}')
            url="https://github.com/ponces/treble_aosp/releases/download/$version/$filename"
            json="${json} {\"name\": \"$name\",\"size\": \"$size\",\"url\": \"$url\"},"
        done
        json="${json%?}]}"
        echo "$json" | jq . > $BUILD_ROOT/config/ota.json
    }
    echo
}

START=$(date +%s)

initRepos
syncRepos
applyPatches
setupEnv
buildTrebleApp
[ ! -z "$BUILD_VARIANT" ] && buildVariant "$BUILD_VARIANT" || buildVariants
generatePackages
generateOta

END=$(date +%s)
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))

echo "--> Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo
