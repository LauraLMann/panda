#!/bin/bash
# Usage ./build.sh  [architectures] [Configure flags...]
# example: ./build.sh i386-softmmu,arm-softmmu
#          ./build.sh small # small = i386-softmmu

# printf wrapper - messages sent to stderr
msg() {
    local fmt=$1
    shift
    printf "%s: $fmt\n" build.sh $* >&2
}

# Default targets to build. Change with argument. small = i386-softmmu
TARGET_LIST="x86_64-softmmu,i386-softmmu,arm-softmmu,ppc-softmmu,mips-softmmu,mipsel-softmmu"
LLVM_CONFIG_BINARY="llvm-config-10"

# If there are arguments, the first arg is target list or 'small'. subsequent args are passed to configure
if [ $# -ge 1 ]; then if [ "$1" = "small" ]; then
        TARGET_LIST="i386-softmmu"
    else
        TARGET_LIST="$1"
    fi
    echo "Building PANDA for target(s): $TARGET_LIST"
    shift
fi

# Prefer greadlink over readlink if present. Important for OSX (incompatible readlink).
if type greadlink >/dev/null 2>&1; then
    READLINK=greadlink
else
    READLINK=readlink
fi

# Set source path variables.
PANDA_DIR_REL="$(dirname $0)"
PANDA_DIR="$("$READLINK" -f "${PANDA_DIR_REL}")"

# Number of concurrent make jobs.
PANDA_NPROC=${PANDA_NPROC:-$(nproc || sysctl -n hw.ncpu)}

# stop on any error
set -e

### Check gcc/g++ versions: 7.1-8.4 are supported. If you want to build with clang, you might need to disable this
gcc --version | awk '/gcc/ && ($3+0)<7.1{print "Fatal error: GCC too old"; exit 1}' || exit 1
g++ --version | awk '/g\+\+/ && ($3+0)<7.1{print "Fatal error: G++ too old"; exit 1}' || exit 1

# Untested GCC - it's probably going to have some warnings - Just disable Werror and hope it works
gcc --version | awk '/gcc/   && ($3+0)>8.4{print "WARNING: Your GCC is too new: disabling -Werror and hoping this builds"; exit 1}' || COMPILER_CONFIG="--extra-cflags=-Wno-error"
g++ --version | awk '/g\+\+/ && ($3+0)>8.4{print "WARNING: Your G++ is too new: disabling -Werror and hoping this builds"; exit 1}' ||  COMPILER_CONFIG="--extra-cxxflags=-Wno-error"

#COMPILER_CONFIG="--cc=gcc-$GCC_TOOLCHAIN_VERSION_MAX --cxx=g++-$GCC_TOOLCHAIN_VERSION_MAX"
#COMPILER_CONFIG="--extra-cflags=-std=gnu11 --extra-cxxflags=-std=gnu++1z --cc=gcc --cxx=g++"

### Check for protobuf v2.
if ! pkg-config --exists protobuf; then
    msg "No pkg-config for protobuf. Continuing anyway..."
elif pkg-config --exists protobuf "protobuf >= 2"; then
    msg "Using protobuf $(pkg-config --modversion protobuf)."
else
    msg "Found incompatible protobuf $(pkg-config --modversion protobuf) -- ABORTING"
    msg "See panda/docs/compile.md for instructions on building protobuf v2."
    exit 1
fi

### Set LLVM_CONFIG to be used with the configure script.
# No LLVM binary: Disable LLVM
if ! command -v $LLVM_CONFIG_BINARY &> /dev/null; then
    echo "LLVM 10 not installed. LLVM SUPPORT IS DISABLED."
    LLVM_CONFIG=""
fi
# OSX: Disable LLVM
if [ $(getconf LONG_BIT) = 32 ]; then
    msg "Running on a 32bit OS -- LLVM SUPPORT IS DISABLED"
    LLVM_CONFIG=""
fi

## Use system LLVM-10
if $LLVM_CONFIG_BINARY --version >/dev/null 2>/dev/null; then
    msg "Found LLVM on $($LLVM_CONFIG_BINARY --prefix) -- LLVM SUPPORT IS ENABLED"
    LLVM_CONFIG="--enable-llvm --with-llvm=$($LLVM_CONFIG_BINARY --prefix)"
else
    msg "No suitable LLVM found -- LLVM SUPPORT IS DISABLED"
    LLVM_CONFIG=""
fi

### Set other configuration flags, depending on environment.
MISC_CONFIG="--disable-vhost-net --enable-capstone"
if pkg-config --exists --atleast-version 4.9 xencontrol; then
    ## Enable xencontrol compat API for libxen-4.9 (Ubuntu 18.04LTS).
    MISC_CONFIG="$MISC_CONFIG --extra-cflags=-DXC_WANT_COMPAT_DEVICEMODEL_API"

    ## Alternatively disable Xen altogether and wait for an upstream fix.
    #MISC_CONFIG="$MISC_CONFIG --disable-xen"
fi

### Enable extra osi plugin functionality and debugging.
#MISC_CONFIG="$MISC_CONFIG --extra-cflags=-DOSI_PROC_EVENTS --extra-cflags=-DOSI_MAX_PROC=256"
#MISC_CONFIG="$MISC_CONFIG --extra-cflags=-DOSI_LINUX_PSDEBUG"

### Force QEMU options definitions to be regenerated.
rm -f "${PANDA_DIR}/qemu-options.def"

### Include any local build configurations options.
BUILD_LOCAL="${PANDA_DIR}/build.inc.sh"
if [ -f "$BUILD_LOCAL" ]; then
    msg "Including local configuration from $BUILD_LOCAL."
    . "$BUILD_LOCAL"
fi

# will install to $(pwd)/install UNLESS $prefix is set when script is run
if [ -z "$prefix" ]; then
    prefix="$(pwd)/install"
    echo "Using default prefix: $prefix"
else
    echo "Using specified prefix: $prefix"
fi

## Configure/compile/test.
msg "Configuring PANDA..."
"${PANDA_DIR_REL}/configure" \
    --target-list=$TARGET_LIST \
    --prefix=$prefix \
    $COMPILER_CONFIG \
    $LLVM_CONFIG \
    $MISC_CONFIG \
    "$@"

msg "Compiling PANDA..."
make -j ${PANDA_NPROC}

# vim: set et ts=4 sts=4 sw=4 ai ft=sh :
