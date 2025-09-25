#! /bin/bash

BASE_DIR=$(pwd)
PROJECT_DIR=$(pwd)
GCC_VERSION=15.2.0
BINUTILS_VERSION=2.45
JBOS=1
TARGET=aarch64-linux-android
HOST=aarch64-linux-android

#### handle commands
while [[ $# > 0 ]]; do
	case $1 in
		--base-dir=*)
			BASE_DIR=${1/--base-dir=/}
		;;
		--jobs=*)
			[[ ${1/--jobs=/} == 0 ]] && {
				echo "jobs value must be greater than 0. termiate" && exit 1
			}
			JOBS=${1/--jobs=/}
		;;
		--gcc-version=*)
			GCC_VERSION=${1/--gcc-version=/}
		;;
		--binutils-version=*)
			BINUTILS_VERSION=${1/--binutils-version=/}
		;;
		--target=*)
			TARGET=${1/--target=/}
		;;
		--host=*)
			HOST=${1/--host=/}
		;;
		*)
			echo "bad command line \"$1\". termiate" && exit 1
		;;
	esac
	shift
done


rm -rf $BASE_DIR/src/
mkdir -p $BASE_DIR/src/


## download gcc
rm -rf /tmp/*.tar.*
wget https://gcc.gnu.org/pub/gcc/releases/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz -q -P /tmp/
tar xf /tmp/gcc-$GCC_VERSION.tar.xz -C $BASE_DIR/src
echo "unpack gcc."
[ -d $BASE_DIR/src/gcc-$GCC_VERSION/ ] || exit 1

## download binutils
wget https://ftpmirror.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz -q -P /tmp/
tar xf /tmp/binutils-$BINUTILS_VERSION.tar.xz -C $BASE_DIR/src
echo "unpack binutils."
[ -d $BASE_DIR/src/binutils-$BINUTILS_VERSION/ ] || exit 1


for i in `find $PROJECT_DIR/patches/gcc/ -name *.patch -type f`; do
	patch -d $BASE_DIR/src/gcc-$GCC_VERSION -p1 < $i || exit 1
done

for i in `find $PROJECT_DIR/patches/binutils/ -name *.patch -type f`; do
	patch -d $BASE_DIR/src/binutils-$BINUTILS_VERSION -p1 < $i || exit 1
done

cd $BASE_DIR/src/gcc-$GCC_VERSION; contrib/download_prerequisites || exit 1
for dir in bfd binutils elfcpp gas ld libctf libsframe opcodes; do
	ln -srf $BASE_DIR/src/binutils-$BINUTILS_VERSION/$dir $BASE_DIR/src/gcc-$GCC_VERSION/$dir
done



## prebuild
export AR_FOR_TARGET=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
export LD_FOR_TARGET=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/ld.lld

mkdir -p $BASE_DIR/prebuild; cd $BASE_DIR/prebuild
../src/gcc-$GCC_VERSION/configure --host=x86_64-linux-gnu --target=$TARGET --build=x86_64-linux-gnu --enable-default-pie --enable-host-pie --enable-languages=c,c++ --with-system-zlib --with-system-zstd --with-target-system-zlib --enable-multilib --enable-multiarch \
	--disable-tls --disable-shared --with-pic --enable-checking=release --disable-rpath --enable-new-dtags --enable-ld=default --enable-gold --disable-libssp --disable-libitm --enable-gnu-indirect-function --disable-relro --disable-werror --enable-libphobos-checking=release \
	--enable-version-specific-runtime-libs --with-build-config=bootstrap-lto-lean --enable-link-serialization=2 --disable-vtable-verify --enable-plugin --prefix=/opt/gcc-preinstall --with-build-sysroot=/opt/android-build/sysroot --with-sysroot=/opt/android-build/sysroot \
	--disable-bootstrap
make -j $JOBS || exit 1
make install || exit 1


## build
export PATH=/opt/preinstall/bin/:$PATH
export LD=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/ld.lld
export LD_FOR_TARGET=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/ld.lld
rm -rf $BASE_DIR/prebuild/
mkdir -p $BASE_DIR/build; cd $BASE_DIR/build
../src/gcc-$GCC_VERSION/configure --host=$HOST --target=$TARGET --build=x86_64-linux-gnu --enable-default-pie --enable-host-pie --enable-languages=c,c++,fortran --with-system-zlib --with-system-zstd --with-target-system-zlib --enable-multilib --enable-multiarch \
	--disable-tls --disable-shared --with-pic --enable-checking=release --disable-rpath --enable-new-dtags --enable-ld=default --enable-gold --disable-libssp --disable-libitm --enable-gnu-indirect-function --disable-relro --disable-werror --enable-libphobos-checking=release \
	--enable-version-specific-runtime-libs --with-build-config=bootstrap-lto-lean --enable-link-serialization=2 --disable-vtable-verify --enable-plugin --prefix=/opt/gcc-install --with-build-sysroot=/opt/android-build/sysroot --with-sysroot=/opt/android-build/sysroot \
	--disable-bootstrap
make -j $JOBS || exit 1
make install || exit 1

find /opt/gcc-install/ -type f

