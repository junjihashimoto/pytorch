#!/bin/bash -xe
##############################################################################
# Example command to build the WASM target.
##############################################################################
#
# This script shows how one can build a Caffe2 binary for the WASM platform
# using wam-cmake. 

CAFFE2_ROOT="$( cd "$(dirname "$0")"/.. ; pwd -P)"

CMAKE_ARGS=()

if [ -z "${BUILD_CAFFE2_MOBILE:-}" ]; then
  # Build PyTorch mobile
  CMAKE_ARGS+=("-DUSE_STATIC_DISPATCH=ON")
  CMAKE_ARGS+=("-DCMAKE_PREFIX_PATH=$(python -c 'from distutils.sysconfig import get_python_lib; print(get_python_lib())')")
  CMAKE_ARGS+=("-DPYTHON_EXECUTABLE=$(python -c 'import sys; print(sys.executable)')")
  CMAKE_ARGS+=("-DBUILD_CUSTOM_PROTOBUF=OFF")
  # custom build with selected ops
  if [ -n "${SELECTED_OP_LIST}" ]; then
    SELECTED_OP_LIST="$(cd $(dirname $SELECTED_OP_LIST); pwd -P)/$(basename $SELECTED_OP_LIST)"
    echo "Choose SELECTED_OP_LIST file: $SELECTED_OP_LIST"
    if [ ! -r ${SELECTED_OP_LIST} ]; then
      echo "Error: SELECTED_OP_LIST file ${SELECTED_OP_LIST} not found."
      exit 1
    fi
    CMAKE_ARGS+=("-DSELECTED_OP_LIST=${SELECTED_OP_LIST}")
  fi
  CMAKE_ARGS+=("-DCMAKE_C_FLAGS=-DFP_FAST_FMA=1")
  CMAKE_ARGS+=("-DCMAKE_CXX_FLAGS=-DFP_FAST_FMA=1")

  echo "Building protoc"
  $CAFFE2_ROOT/scripts/build_host_protoc.sh
  # Use locally built protoc because we'll build libprotobuf for the
  # target architecture and need an exact version match.
  CMAKE_ARGS+=("-DCAFFE2_CUSTOM_PROTOC_EXECUTABLE=$CAFFE2_ROOT/build_host_protoc/bin/protoc")

fi

# Use wasm-cmake to build WASM project from CMake.
# This projects sets CMAKE_C_COMPILER to /usr/bin/gcc and
# CMAKE_CXX_COMPILER to /usr/bin/g++. In order to use ccache (if it is available) we
# must override these variables via CMake arguments.
CMAKE_ARGS+=("-DCMAKE_TOOLCHAIN_FILE=$CAFFE2_ROOT/cmake/WASM.cmake")
if [ -n "${CCACHE_WRAPPER_PATH:-}"]; then
  CCACHE_WRAPPER_PATH=/usr/local/opt/ccache/libexec
fi
if [ -d "$CCACHE_WRAPPER_PATH" ]; then
  CMAKE_ARGS+=("-DCMAKE_C_COMPILER=$CCACHE_WRAPPER_PATH/gcc")
  CMAKE_ARGS+=("-DCMAKE_CXX_COMPILER=$CCACHE_WRAPPER_PATH/g++")
fi

# WASM_PLATFORM controls type of WASM platform (see wasm-cmake)
if [ -n "${WASM_PLATFORM:-}" ]; then
  CMAKE_ARGS+=("-DWASM_PLATFORM=${WASM_PLATFORM}")    
  if [ "${WASM_PLATFORM}" == "WATCHOS" ]; then
      # enable bitcode by default for watchos
      CMAKE_ARGS+=("-DCMAKE_C_FLAGS=-fembed-bitcode")
      CMAKE_ARGS+=("-DCMAKE_CXX_FLAGS=-fembed-bitcode")
      # disable the QNNPACK
      CMAKE_ARGS+=("-DUSE_PYTORCH_QNNPACK=OFF")
  fi
else
  # WASM_PLATFORM is not set, default to OS, which builds WASM.
  CMAKE_ARGS+=("-DWASM_PLATFORM=OS")
fi

if [ -n "${WASM_ARCH:-}" ]; then
  CMAKE_ARGS+=("-DWASM_ARCH=${WASM_ARCH}")
fi

# Don't build binaries or tests (only the library)
CMAKE_ARGS+=("-DBUILD_TEST=OFF")
CMAKE_ARGS+=("-DBUILD_BINARY=OFF")
CMAKE_ARGS+=("-DBUILD_PYTHON=OFF")

# Disable unused dependencies
CMAKE_ARGS+=("-DUSE_CUDA=OFF")
CMAKE_ARGS+=("-DUSE_GFLAGS=OFF")
CMAKE_ARGS+=("-DUSE_OPENCV=OFF")
CMAKE_ARGS+=("-DUSE_LMDB=OFF")
CMAKE_ARGS+=("-DUSE_LEVELDB=OFF")
CMAKE_ARGS+=("-DUSE_MPI=OFF")
CMAKE_ARGS+=("-DUSE_NUMPY=OFF")
CMAKE_ARGS+=("-DUSE_NNPACK=OFF")

# pthreads
CMAKE_ARGS+=("-DCMAKE_THREAD_LIBS_INIT=-lpthread")
CMAKE_ARGS+=("-DCMAKE_HAVE_THREADS_LIBRARY=1")
CMAKE_ARGS+=("-DCMAKE_USE_PTHREADS_INIT=1")

# Only toggle if VERBOSE=1
if [ "${VERBOSE:-}" == '1' ]; then
  CMAKE_ARGS+=("-DCMAKE_VERBOSE_MAKEFILE=1")
fi

# Now, actually build the WASM target.
BUILD_ROOT=${BUILD_ROOT:-"$CAFFE2_ROOT/build"}
INSTALL_PREFIX=${BUILD_ROOT}/install
mkdir -p $BUILD_ROOT
cd $BUILD_ROOT
emcmake cmake "$CAFFE2_ROOT" \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DBUILD_SHARED_LIBS=OFF \
    ${CMAKE_ARGS[@]} \
    $@

#emmake cmake --build . -- "-j$(sysctl -n hw.ncpu)"
emmake cmake --build . -- "-j6"

# copy headers and libs to install directory
echo "Will install headers and libs to $INSTALL_PREFIX for further Xcode project usage."
make install
echo "Installation completed, now you can copy the headers/libs from $INSTALL_PREFIX to your Xcode project directory."
