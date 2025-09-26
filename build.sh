#! /bin/bash

BASE_DIR=$(pwd)
PROJECT_DIR=$(pwd)
GCC_VERSION=15.2.0
BINUTILS_VERSION=2.45
ZSTD_VERSION=1.5.7
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
wget --tries=3 https://gcc.gnu.org/pub/gcc/releases/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz -q -P /tmp/
tar xf /tmp/gcc-$GCC_VERSION.tar.xz -C $BASE_DIR/src
echo "unpack gcc."
[ -d $BASE_DIR/src/gcc-$GCC_VERSION/ ] || exit 1

## download binutils
wget --tries=3 https://ftpmirror.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz -q -P /tmp/
tar xf /tmp/binutils-$BINUTILS_VERSION.tar.xz -C $BASE_DIR/src
echo "unpack binutils."
[ -d $BASE_DIR/src/binutils-$BINUTILS_VERSION/ ] || exit 1

wget --tries=3 https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/zstd-$ZSTD_VERSION.tar.gz -q -P /tmp/
tar xf /tmp/zstd-$ZSTD_VERSION.tar.gz -C $BASE_DIR/src
echo "unpack zstd."
[ -d $BASE_DIR/src/zstd-$ZSTD_VERSION/ ] || exit 1

cd $BASE_DIR/src/gcc-$GCC_VERSION; contrib/download_prerequisites || exit 1

for i in `find $PROJECT_DIR/patches/gcc/ -name *.patch -type f`; do
	patch -d $BASE_DIR/src/gcc-$GCC_VERSION -p1 < $i || exit 1
done

for i in `find $PROJECT_DIR/patches/gettext/ -name *.patch -type f`; do
	patch -d $BASE_DIR/src/gcc-$GCC_VERSION/gettext -p1 < $i || exit 1
done

for i in `find $PROJECT_DIR/patches/binutils/ -name *.patch -type f`; do
	patch -d $BASE_DIR/src/binutils-$BINUTILS_VERSION -p1 < $i || exit 1
done

for dir in bfd binutils elfcpp gas ld libctf libsframe opcodes; do
	ln -srf $BASE_DIR/src/binutils-$BINUTILS_VERSION/$dir $BASE_DIR/src/gcc-$GCC_VERSION/$dir
done


## prebuild
PREINSTALL_DIR=/opt/gcc-preinstall
export AR_FOR_TARGET=llvm-ar
export LD_FOR_TARGET=ld.lld
export LD=ld.lld
export AR=llvm-ar

mkdir -p $BASE_DIR/prebuild; cd $BASE_DIR/prebuild
../src/gcc-$GCC_VERSION/configure --host=x86_64-linux-gnu --target=$TARGET --build=x86_64-linux-gnu --enable-default-pie --enable-host-pie --enable-languages=c,c++,fortran,d --with-system-zlib --with-system-zstd --with-target-system-zlib --enable-multilib --enable-multiarch \
	--disable-tls --disable-shared --with-pic --enable-checking=release --disable-rpath --enable-new-dtags --enable-ld=default --enable-gold --disable-libssp --disable-libitm --enable-gnu-indirect-function --disable-relro --disable-werror --enable-libphobos-checking=release \
	--enable-version-specific-runtime-libs --with-build-config=bootstrap-lto-lean --enable-link-serialization=2 --disable-vtable-verify --enable-plugin --with-build-sysroot=/opt/android-build/sysroot --with-sysroot=/opt/android-build/sysroot \
	--disable-bootstrap  --prefix=$PREINSTALL_DIR
make -j $JOBS || exit 1
make install || exit 1
rm -rf $BASE_DIR/prebuild/

export PATH=$PREINSTALL_DIR/bin:$PATH

# build zstd
CC=$HOST-gcc CFLAGS="-fPIC -O2" make lib -j $JOBS -C $BASE_DIR/src/zstd-$ZSTD_VERSION/ || exit 1
mkdir -p $PREINSTALL_DIR/$HOST/include/ && cp -r $BASE_DIR/src/zstd-$ZSTD_VERSION/lib/*.h $PREINSTALL_DIR/$HOST/include/ || exit 1
mkdir -p $PREINSTALL_DIR/$HOST/lib/ && cp -r $BASE_DIR/src/zstd-$ZSTD_VERSION/lib/libzstd.a $PREINSTALL_DIR/$HOST/lib/ || exit 1

## build
mkdir -p $BASE_DIR/build; cd $BASE_DIR/build
export gcc_cv_objdump=llvm-objdump
../src/gcc-$GCC_VERSION/configure --host=$HOST --target=$TARGET --build=x86_64-linux-gnu --enable-default-pie --enable-host-pie --enable-languages=c,c++,fortran,d --with-system-zlib --with-system-zstd --with-target-system-zlib --enable-multilib --enable-multiarch \
	--disable-tls --disable-shared --with-pic --enable-checking=release --disable-rpath --enable-new-dtags --enable-ld=default --enable-gold --disable-libssp --disable-libitm --enable-gnu-indirect-function --disable-relro --disable-werror --enable-libphobos-checking=release \
	--enable-version-specific-runtime-libs --with-build-config=bootstrap-lto-lean --enable-link-serialization=2 --disable-vtable-verify --enable-plugin --prefix=/usr --with-build-sysroot=/opt/android-build/sysroot --with-sysroot=/usr/sysroot \
	--disable-bootstrap
make -j $JOBS || exit 1
DESTDIR=/opt/gcc-install/ make install || exit 1

cp -r /opt/android-build/sysroot/ /opt/gcc-install/usr/sysroot || exit 1


rm -rf /opt/gcc-install/usr/include/* /opt/gcc-install/usr/lib/lib*.*a /opt/gcc-install/usr/lib/bfd
mkdir -p /opt/gcc-install/usr/$TARGET/include /opt/gcc-install/usr/$TARGET/lib
case $TARGET in
	*64-*-android*) mkdir -p /opt/gcc-install/usr/$TARGET/lib64;;
esac
# strip
cd /opt/gcc-install/usr && find $TARGET bin lib lib64 libexec -type f -not -type l -not -path "*/*include*/*" -print -exec llvm-strip -R .comment --strip-unneeded {} \;
cd /opt/gcc-install/ && tar -cf $TARGET-gcc-$GCC_VERSION.tar ./usr && xz -ze9f $TARGET-gcc-$GCC_VERSION.tar
