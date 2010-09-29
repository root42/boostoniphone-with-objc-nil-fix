#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
#===============================================================================
#
# Builds a Boost framework for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_LIBS:        which libraries to build
#    BOOST_VERSION:     version number of the boost library (e.g. 1_41_0)
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 3.0)
#
# Then go get the source tar.bz of the boost you want to build, shove it in the
# same directory as this script, and run "./boost.sh". Grab a cuppa. And voila.
#===============================================================================

: ${BOOST_VERSION:=1_44_0}
: ${BOOST_LIBS:="thread signals filesystem regex program_options system"}
: ${IPHONE_SDKVERSION:=4.2}

: ${TARBALLDIR:=`pwd`}
: ${SRCDIR:=`pwd`/src}
: ${BUILDDIR:=`pwd`/build}
: ${PREFIXDIR:=`pwd`/prefix}
: ${FRAMEWORKDIR:=`pwd`/framework}

BOOST_TARBALL=$TARBALLDIR/boost_$BOOST_VERSION.tar.bz2
    BOOST_SRC=$SRCDIR/boost_${BOOST_VERSION}

#===============================================================================

ARM_DEV_DIR=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/
SIM_DEV_DIR=/Developer/Platforms/iPhoneSimulator.platform/Developer/usr/bin/

ARM_COMBINED_LIB=$BUILDDIR/lib_boost_arm.a
SIM_COMBINED_LIB=$BUILDDIR/lib_boost_x86.a

#===============================================================================

echo "BOOST_VERSION:     $BOOST_VERSION"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_TARBALL:     $BOOST_TARBALL"
echo "BOOST_SRC:         $BOOST_SRC"
echo "BUILDDIR:          $BUILDDIR"
echo "PREFIXDIR:         $PREFIXDIR"
echo "FRAMEWORKDIR:      $FRAMEWORKDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo

#===============================================================================
# Functions
#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

doneSection()
{
    echo
    echo "    ================================================================="
    echo "    Done"
    echo
}

#===============================================================================

unpackBoost()
{
    echo Unpacking boost into $SRCDIR...
    [ -d $SRCDIR ]    || mkdir -p $SRCDIR
    [ -d $BOOST_SRC ] || ( cd $SRCDIR; tar xfj $BOOST_TARBALL )
    [ -d $BOOST_SRC ] && echo "    ...unpacked as $BOOST_SRC"
    doneSection
}

#===============================================================================

writeBjamUserConfig()
{
    # You need to do this to point bjam at the right compiler
    # ONLY SEEMS TO WORK IN HOME DIR GRR
    echo Writing usr-config
    #mkdir -p $BUILDDIR
    #cat >> $BOOST_SRC/tools/build/v2/user-config.jam <<EOF
    cat > ~/user-config.jam <<EOF
using darwin : 4.2.1~iphone
   : /Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/gcc-4.2 -arch armv7 -mthumb -fvisibility=hidden -fvisibility-inlines-hidden
   : <striper>
   : <architecture>arm <target-os>iphone
   ;
using darwin : 4.2.1~iphonesim
   : /Developer/Platforms/iPhoneSimulator.platform/Developer/usr/bin/gcc-4.2 -arch i386 -fvisibility=hidden -fvisibility-inlines-hidden
   : <striper>
   : <architecture>x86 <target-os>iphone
   ;
EOF
    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers
    cp /Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $BOOST_SRC
}

#===============================================================================

bootstrapBoost()
{
    cd $BOOST_SRC
    BOOST_LIBS_COMMA=$(echo $BOOST_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA
    doneSection
}

#===============================================================================

buildBoostForiPhoneOS_1_44_0()
{
    cd $BOOST_SRC
    
    ./bjam --prefix="$PREFIXDIR" toolset=darwin architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static install
    doneSection

    ./bjam toolset=darwin architecture=x86 target-os=iphone macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static stage
    doneSection
}

#===============================================================================

# $1: Name of a boost library to lipoficate (technical term)
lipoficate()
{
    : ${1:?}
    NAME=$1
    echo liboficate: $1
    ARMV6=$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphone/release/architecture-arm/link-static/macosx-version-iphone-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a
    I386=$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphonesim/release/architecture-x86/link-static/macosx-version-iphonesim-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a

    mkdir -p $PREFIXDIR/lib
    lipo \
        -create \
        "$ARMV6" \
        "$I386" \
        -o          "$PREFIXDIR/lib/libboost_$NAME.a" \
    || abort "Lipo $1 failed"
}

# This creates universal versions of each individual boost library
lipoAllBoostLibraries()
{
    for i in $BOOST_LIBS; do lipoficate $i; done;

    doneSection
}

linkAllLibsTogetherInOneLibPerPlatform()
{
    ALL_LIBS_ARM=""
    ALL_LIBS_SIM=""
    for NAME in $BOOST_LIBS; do
        ALL_LIBS_ARM="$ALL_LIBS_ARM $BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphone/release/architecture-arm/link-static/macosx-version-iphone-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a";
        ALL_LIBS_SIM="$ALL_LIBS_SIM $BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphonesim/release/architecture-x86/link-static/macosx-version-iphonesim-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a";
    done;

#echo $ARM_DEV_DIR/g++ -c -o $ARM_COMBINED_LIB $ALL_LIBS_ARM
#echo $SIM_DEV_DIR/g++ -c -o $SIM_COMBINED_LIB $ALL_LIBS_SIM
    $ARM_DEV_DIR/ar cru $ARM_COMBINED_LIB $ALL_LIBS_ARM
    $SIM_DEV_DIR/ar cru $SIM_COMBINED_LIB $ALL_LIBS_SIM
}

#===============================================================================

                    VERSION_TYPE=Alpha
                  FRAMEWORK_NAME=boost
               FRAMEWORK_VERSION=A

       FRAMEWORK_CURRENT_VERSION=$BOOST_VERSION
 FRAMEWORK_COMPATIBILITY_VERSION=$BOOST_VERSION

buildFramework()
{
    FRAMEWORK_BUNDLE=$FRAMEWORKDIR/$FRAMEWORK_NAME.framework

    rm -rf $FRAMEWORK_BUNDLE

    echo "Framework: Setting up directories..."
    mkdir -p $FRAMEWORK_BUNDLE
    mkdir -p $FRAMEWORK_BUNDLE/Versions
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation

    echo "Framework: Creating symlinks..."
    ln -s $FRAMEWORK_VERSION               $FRAMEWORK_BUNDLE/Versions/Current
    ln -s Versions/Current/Headers         $FRAMEWORK_BUNDLE/Headers
    ln -s Versions/Current/Resources       $FRAMEWORK_BUNDLE/Resources
    ln -s Versions/Current/Documentation   $FRAMEWORK_BUNDLE/Documentation
    ln -s Versions/Current/$FRAMEWORK_NAME $FRAMEWORK_BUNDLE/$FRAMEWORK_NAME

    FRAMEWORK_INSTALL_NAME=$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME

    lipo \
        -create \
        -arch arm "$ARM_COMBINED_LIB" \
        -arch i386 "$SIM_COMBINED_LIB" \
        -o          "$FRAMEWORK_INSTALL_NAME" \
    || abort "Lipo $1 failed"

    echo "Framework: Copying includes..."
    cp -r $PREFIXDIR/include/boost/*  $FRAMEWORK_BUNDLE/Headers/
    echo "Framework: Creating plist..."
    cat > $FRAMEWORK_BUNDLE/Resources/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>${FRAMEWORK_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>org.boost</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF
    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

[ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

mkdir -p $BUILDDIR

case $BOOST_VERSION in
    1_44_0 )
        #unpackBoost
        #inventMissingHeaders
        #writeBjamUserConfig
        #bootstrapBoost
        buildBoostForiPhoneOS_1_44_0
        linkAllLibsTogetherInOneLibPerPlatform
        #lipoAllBoostLibraries
        buildFramework
        ;;
    default )
        echo "This version ($BOOST_VERSION) is not supported"
        ;;
esac

echo "Completed successfully"

#===============================================================================

