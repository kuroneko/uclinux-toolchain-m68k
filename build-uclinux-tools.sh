#!/bin/bash
#
# This script builds the m68k-uclinux- or arm-elf- toolchain for use
# with uClinux.  It can be used to build for almost any architecture
# without too much change.
#
# Before running you will need to obtain the following files
# (and have them in this directory)
#
#    binutils-2.25.1.tar.bz2
#    gcc-5.4.0.tar.bz2
#    elf2flt-20160818.tar.bz2
#    genromfs-0.5.1.tar.gz
#    linux-4.4.tar.gz
#    uClibc-0.9.33.2.tar.xz
#
# Unless you modify PREFIX below, you will need to be root to run this
# script correctly. You may want to change some of the setup parameters
# below too.
#
# To build everything run "./build-uclinux-tools.sh build 2>&1 | tee errs"
#
# WARNING: it removes all current tools from $PREFIX, so back them up first :-)
#
# Copyright (C) 2001-2003 David McCullough <davidm@snapgear.com>
#
# Cygwin changes from Heiko Degenhardt <linux@sentec-elektronik.de>
#     I've modified that script to build the toolchain under Cygwin.
#     My changes are based on the information I found at
#     http://fiddes.net/coldfire/ # (thanks to David J. Fiddes) and the
#     very good introduction at
#     http://www.uclinux.org/pub/uClinux/archive/8306.html (thanks to
#     Paul M. Banasik (PaulMBanasik@eaton.com).
#
# Support for GCC 3.x and binutils 2.14.x by Bernardo Innocenti <bernie@codewiz.org>,
#     based on Peter Barada's Coldfire patches for gcc-3.2.3 and binutils-2.13.
#
# Support added for GCC 3.4.0 (arm-elf only) and binutils 2.15.x by Steve
# Miller <steve.miller@st.com>
#
# GDB/Insight integration by Bernardo Innocenti <bernie@codewiz.org>,
#     includes Chris John's BDM patches for GDB.
#
# <gerg@uclinux.org>
#     Major updated to build tool chain based on gcc-4. Support for older
#     gcc versions removed from this script now.
#

BASEDIR="$(pwd)"

#############################################################

#
# EDIT these to suit your system and source locations
#

TARGET=m68k-uclinux
#TARGET=arm-elf

# set your install directory here and add the correct PATH
PREFIX=/opt/m68k-uclinux-tools

BINUTILSVERS="2.25.1"
GCCVERS="5.4.0"
ELF2FLTVERS="20160818"
LINUXVERS="4.4"
UCLIBCVERS="0.9.33.2"

# set $ROOTDIR to the root directory of your uClinux source tree.
# Needed to build uClibc with -mid-shared-library support.
#
ROOTDIR="${BASEDIR}/uclinux"

#
# Override this host's CFLAGS to build the tools for older hosts
#
CFLAGS=-O2
CXXFLAGS=-O2
CPPFLAGS=

MAKE=make
PATCH=patch
ELF2FLT="$BASEDIR/elf2flt-${ELF2FLTVERS}"
BINUTILS="${BASEDIR}/binutils-${BINUTILSVERS}"
GCC="${BASEDIR}/gcc-${GCCVERS}"
KERNEL="${BASEDIR}/linux-${LINUXVERS}"
UCLIBC="${BASEDIR}/uClibc-${UCLIBCVERS}"

#############################################################
#
# Don't edit these
#

sysinclude=include

#############################################################
#
# mark stage done
#
mark()
{
	echo "STAGE $1 - complete"
	touch "$BASEDIR/STAGE$1"
}

#
# check if stage should be built
#
schk()
{
	echo "--------------------------------------------------------"
	[ -f "$BASEDIR/STAGE$1" ] && echo "STAGE $1 - already built" && return 1
	echo "STAGE $1 - needs building"
	return 0
}

#
# extract most archive format files
#
extract()
{
	for i in "$@"; do
		echo "Extracting $i..."
		case "$i" in
		*.tar.gz|*.tgz)   tar xzf "$i" ;;
		*.tar.bz2|*.tbz2) bunzip2 < "$i" | tar xf - ;;
		*.tar.xz|*.txz)   tar xJf "$i" ;;
		*.tar)            tar xf  "$i" ;;
		*)
			echo "Unknown file format $i" >&2
			return 1
			;;
		esac
	done
	return 0
}

#
# Apply a patch
#
apply_patch()
{
	echo "Applying patch $1..."

	[ "x$2" = "x" ] || cd $2 || exit 1
	${PATCH} -p1 -E < "${BASEDIR}/$1" || exit 1
	[ "x$2" = "x" ] || cd ${BASEDIR}
}

#
# work like cp -L -r on systems without it
#
cp_Lr()
{
	cd "$1/."
	[ -d "$2" ] || mkdir -p $2
	find . | cpio -pLvdum "$2/."
}

#############################################################
#
# cleanup
#

clean_sources()
{
	echo "Removing source and build dirs..."
	rm -rf ${BINUTILS}
	rm -rf ${GCC}
	rm -rf ${TARGET}-binutils
	rm -rf ${TARGET}-gcc
	rm -rf ${KERNEL}
	rm -rf ${UCLIBC}
	rm -rf ${ELF2FLT}
	rm -rf ${TARGET}-elf2flt
	rm -rf genromfs-0.5.1
	rm -rf STLport-4.5.3
}

clean_uninstall()
{
	echo "Removing installed binaries..."
	rm -rf ${PREFIX}/${TARGET}
	[ -z "${OLDTARGET}" ] || rm -rf ${PREFIX}/${OLDTARGET}
	rm -rf ${GCCLIB}
	[ -z "${GCCLIBEXEC}" ] || rm -rf ${GCCLIBEXEC}
	rm -rf ${GLIBCXXHEADERS}
	rm -rf ${PREFIX}/bin/${TARGET}*
	[ -z "${OLDTARGET}" ] || rm -rf ${PREFIX}/bin/${OLDTARGET}*
	rm -rf ${PREFIX}/bin/genromfs${EXE}
	rm -rf ${PREFIX}/man/*/${TARGET}-*
}

clean_all()
{
	echo "Removing stage completition flags..."
	rm -f ${BASEDIR}/STAGE*
	clean_sources
}


#############################################################
#
# Setup GCC version-specific paths
#
gcc_version_setup()
{
	if [ -f "${GCC}/gcc/BASE-VER" ]; then
		#
		# Modern versions of gcc keep the versio number in the
		# high level file named gcc/BASE-VER.
		#
		gcc_version=`cat ${GCC}/gcc/BASE-VER`

	elif [ -f "${GCC}/gcc/version.c" ] ; then
		#
		# Don't let us get easily fooled by awkward package naming
		# schemes: extract GCC version from sources the same way
		# top-level configure does
		#
		gcc_version_full=`grep version_string "${GCC}/gcc/version.c" | sed -e 's/.*"\([^"]*\)".*/\1/'`
		gcc_version=`echo ${gcc_version_full} | sed -e 's/\([^ ]*\) .*/\1/'`

	else
		#
		# We have not yet extracted the tarballs: try to guess the
		# installation version from the package version
		#
		gcc_version=${GCCVERS%%-*}
	fi

	#
	# Handle GCC installation directories
	#
	OLDTARGET="$TARGET"

	case "${GCCVERS}" in
	4*|5*)
		case "${TARGET}" in
		m68k-*)
			#
			# Handle the target switch mess
			#
			TARGET="m68k-uclinux"
			OLDTARGET="m68k-elf"
			;;
		esac
		GCCLIB=${PREFIX}/lib/gcc/${TARGET}/${gcc_version}
		GCCLIBEXEC=${PREFIX}/libexec/gcc/${TARGET}/${gcc_version}
		GLIBCXXHEADERS=${PREFIX}/include/c++/${gcc_version}
		;;
	*)
		echo >&2 "Unsupported GCC version ${GCCVERS} (${gcc_version})"
		exit 1
		;;
	esac
}

#############################################################
#
# Clean any previous runs, extract everything and apply all patches
#

stage1()
{
	schk 1 || return 0

	# clean any previous runs
	clean_sources

	#
	# extract everything
	#
	extract binutils-${BINUTILSVERS}.tar*
	extract elf2flt-${ELF2FLTVERS}.tar*
	extract linux-${LINUXVERS}.tar*
	extract uClibc-${UCLIBCVERS}.tar*
	extract gcc-*${GCCVERS}.tar*

	#
	# Apply all patches
	#
	apply_patch elf2flt-20160818-fix-build.patch elf2flt-${ELF2FLTVERS}
	apply_patch gcc-5.4.0-fix-libgcc-build.patch gcc-${GCCVERS}

	# Get GCC version again using the extracted source
	gcc_version_setup

	# We can now safely uninstall previous installations
	clean_uninstall

	mark 1
}

#############################################################
#
# build binutils
#

stage2()
{
	schk 2 || return 0

	rm -rf ${TARGET}-binutils
	mkdir ${TARGET}-binutils
	cd ${TARGET}-binutils
	${BINUTILS}/configure ${HOST_TARGET} --target=${TARGET} ${PREFIXOPT}
	${MAKE}
	${MAKE} install

	cd ${BASEDIR}
	mark 2
}

#############################################################
#
# build elf2flt
#

stage3()
{
	schk 3 || return 0

	rm -rf ${TARGET}-elf2flt
	mkdir ${TARGET}-elf2flt
	cd ${TARGET}-elf2flt
	${ELF2FLT}/configure ${HOST_TARGET} \
		--with-libbfd=${BASEDIR}/${TARGET}-binutils/bfd/libbfd.a \
		--with-libiberty=${BASEDIR}/${TARGET}-binutils/libiberty/libiberty.a \
		--with-bfd-include-dir=${BASEDIR}/${TARGET}-binutils/bfd \
		--with-binutils-include-dir=${BINUTILS}/include \
		--target=${TARGET} ${PREFIXOPT}
	${MAKE}
	${MAKE} install

	cd $BASEDIR
	mark 3
}

#############################################################
#
# configure linux kernel sources. we don't need to build it, we just
# need the configured headers
#

stage4()
{
	schk 4 || return 0

	echo
	echo DOING STAGE 4 NOW
	echo
	pwd
	echo
	echo TARGET=${TARGET}
	echo
	cd ${KERNEL}
	${MAKE} ARCH=${_CPU} CROSS_COMPILE=${TARGET}- defconfig
	${MAKE} ARCH=${_CPU} CROSS_COMPILE=${TARGET}- headers_install
	mkdir -p ${PREFIX}/${TARGET}/include
	cp -a usr/include/* ${PREFIX}/${TARGET}/include/

	cd ${BASEDIR}
	mark 4
}

#############################################################
#
# common uClibc Config substitutions
#
# fix_uclibc_config pic_flag shlib_flag

fix_uclibc_config()
{
	pic=$1
	shlib=$2
	(grep -v KERNEL_HEADERS; echo "KERNEL_HEADERS=\"${KERNEL}/usr/include\"") |
	if [ "${NOMMU}" ]; then
		egrep -v '(ARCH_HAS_MMU|ARCH_HAS_NO_LDSO)' |
			egrep -v '(UCLIBC_HAS_SHADOW|\<MALLOC\>|UNIX98PTY_ONLY|UCLIBC_CTOR_DTOR)' |
			egrep -v '(DOPIC|UCLIBC_DYNAMIC_ATEXIT)' |
			egrep -v '(UCLIBC_HAS_WCHAR|UCLIBC_HAS_LOCALE|UCLIBC_HAS_TM_EXTENSIONS)' |
			egrep -v '(UCLIBC_HAS_THREADS)' |
			egrep -v '(UCLIBC_HAS_RPC|UCLIBC_HAS_LFS)' |
			egrep -v '(UCLIBC_FORMAT_ELF|UCLIBC_FORMAT_FDPIC_ELF|UCLIBC_FORMAT_FLAT|UCLIBC_FORMAT_FLAT_SEP_DATA|UCLIBC_FORMAT_SHARED_FLAT)' |
			egrep -v '(HAVE_NO_SHARED)'

		echo '# ARCH_HAS_MMU is not set'
		if [ x"$pic" = x"true" ] ; then
			echo 'DOPIC=y'
		else
			echo '# DOPIC is not set'
		fi
		if [ x"$shared" = x"true" ] ; then
			echo 'UCLIBC_FORMAT_SHARED_FLAT=y'
			echo '# HAVE_NO_SHARED is not set'
		else
			if [ x"$pic" = x"true" ] ; then
				echo 'UCLIBC_FORMAT_FLAT_SEP_DATA=y'
			else
				echo 'UCLIBC_FORMAT_FLAT=y'
			fi
			echo 'HAVE_NO_SHARED=y'
		fi
		echo 'ARCH_HAS_NO_LDSO=y'
		echo '# UCLIBC_HAS_SHADOW is not set'
		echo '# MALLOC is not set'
		echo 'MALLOC_SIMPLE=y'
		echo '# MALLOC_STANDARD is not set'
		echo '# MALLOC_GLIBC_COMPAT is not set'
		echo '# UNIX98PTY_ONLY is not set'
		echo 'UCLIBC_CTOR_DTOR=y'
		echo 'UCLIBC_DYNAMIC_ATEXIT=y'
		echo '# UCLIBC_HAS_WCHAR is not set'
		echo '# UCLIBC_HAS_LOCALE is not set'
		echo '# UCLIBC_HAS_TM_EXTENSIONS is not set'
		echo 'UCLIBC_HAS_THREADS=y'
		echo '# UCLIBC_HAS_RPC is not set'
		echo '# UCLIBC_HAS_LFS is not set'
		echo 'UCLIBC_SUSV3_LEGACY=y'
		echo 'UCLIBC_SUSV3_LEGACY_MACROS=y'
		echo 'UCLIBC_SUSV4_LEGACY=y'
	else
		cat
	fi
}

#############################################################

multilib_table()
{
	ALL_BUILDS="${ALL_BUILDS} -I${KERNEL}/usr/include"

	# Build uClibc with no flags for top-level directory (needed for GCC build, will be removed later)
	echo ". false false $ALL_BUILDS"

	case "${_CPU}" in
	m68k*)
		case "$GCCVERS" in
		5.*|4.*)
			#     GCC multilib subdir       pic   shlib flags
			echo "msep-data                 true  false $ALL_BUILDS -msep-data"
			echo "mid-shared-library        true  true  $ALL_BUILDS -mid-shared-library"

			echo "m51qe                     false false $ALL_BUILDS -mcpu=51qe"
			echo "m51qe/msep-data           true  false $ALL_BUILDS -mcpu=51qe -msep-data"
			echo "m51qe/mid-shared-library  true  true  $ALL_BUILDS -mcpu=51qe -mid-shared-library"

			echo "m5206                     false false $ALL_BUILDS -mcpu=5206"
			echo "m5206/msep-data           true  false $ALL_BUILDS -mcpu=5206 -msep-data"
			echo "m5206/mid-shared-library  true  true  $ALL_BUILDS -mcpu=5206 -mid-shared-library"

			echo "m5206e                    false false $ALL_BUILDS -mcpu=5206e"
			echo "m5206e/msep-data          true  false $ALL_BUILDS -mcpu=5206e -msep-data"
			echo "m5206e/mid-shared-library true  true  $ALL_BUILDS -mcpu=5206e -mid-shared-library"

			echo "m5208                     false false $ALL_BUILDS -mcpu=5208"
			echo "m5208/msep-data           true  false $ALL_BUILDS -mcpu=5208 -msep-data"
			echo "m5208/mid-shared-library  true  true  $ALL_BUILDS -mcpu=5208 -mid-shared-library"

			echo "m5307                     false false $ALL_BUILDS -mcpu=5307"
			echo "m5307/msep-data           true  false $ALL_BUILDS -mcpu=5307 -msep-data"
			echo "m5307/mid-shared-library  true  true  $ALL_BUILDS -mcpu=5307 -mid-shared-library"

			echo "m5329                     false false $ALL_BUILDS -mcpu=5329"
			echo "m5329/msep-data           true  false $ALL_BUILDS -mcpu=5329 -msep-data"
			echo "m5329/mid-shared-library  true  true  $ALL_BUILDS -mcpu=5329 -mid-shared-library"

			echo "m5407                     false false $ALL_BUILDS -mcpu=5407"
			echo "m5407/msep-data           true  false $ALL_BUILDS -mcpu=5407 -msep-data"
			echo "m5407/mid-shared-library  true  true  $ALL_BUILDS -mcpu=5407 -mid-shared-library"

			echo "m54455                    false false $ALL_BUILDS -mcpu=54455"
			echo "m54455/msep-data          true  false $ALL_BUILDS -mcpu=54455 -msep-data"
			echo "m54455/mid-shared-library true  true  $ALL_BUILDS -mcpu=54455 -mid-shared-library"

			echo "m68000                    false false $ALL_BUILDS -m68000"
			echo "m68000/msep-data          true  false $ALL_BUILDS -m68000 -msep-data"
			echo "m68000/mid-shared-library true  true  $ALL_BUILDS -m68000 -mid-shared-library"

			;;
		*)
			echo >&2 "Unsupported GCC version ${GCCVERS}"
			exit 1
			;;
		esac
		;;
	arm*)
		case "$GCCVERS" in
		4.*)
			#     GCC multilib subdir                        pic   shlib flags
			echo "fpic                                       true  false $ALL_BUILDS -fpic"
			echo "fpic/msingle-pic-base                      true  false $ALL_BUILDS -fpic -msingle-pic-base"
			echo "fpic/msingle-pic-base/soft-float           true  false $ALL_BUILDS -msoft-float -fpic -msingle-pic-base" 
#			echo "mbig-endian/fpic                           true  false $ALL_BUILDS -fpic -mbig-endian"
#			echo "mbig-endian/mfpic/msingle-pic-base         true  false $ALL_BUILDS -fpic -mbig-endian -msingle-pic-base"
			echo "mlittle-endian                             true  false $ALL_BUILDS -mlittle-endian"
		        echo "mlittle-endian/fpic                        true  false $ALL_BUILDS -fpic -mlittle-endian"
			;;
		esac
		;;
	esac
}

#############################################################
#
# install uClibc headers
#

stage5()
{
	schk 5 || return 0
	# set -x

	cd ${UCLIBC}
	${MAKE} distclean

	fix_uclibc_config false false < $UCLIBC_CONFIG > .config

	${MAKE} oldconfig CROSS="${TARGET}-" TARGET_ARCH=${_CPU} </dev/null || exit 1
	${MAKE} install_headers CROSS="${TARGET}-" TARGET_ARCH=${_CPU} </dev/null || exit 1

	cd $BASEDIR
	mark 5
}

#############################################################
#
# Just the C compiler so we can build uClibc
#

stage6()
{
	schk 6 || return 0

	cd ${GCC}/
	chmod +x contrib/download_prerequisites
	contrib/download_prerequisites || exit 1

	rm -rf ${TARGET}-gcc
	mkdir ${TARGET}-gcc
	cd ${TARGET}-gcc

	${GCC}/configure ${HOST_TARGET} \
		--target=${TARGET} \
		--prefix=${PREFIX} \
		--enable-multilib \
		--disable-libssp \
		--disable-shared \
		--disable-threads \
		--disable-libmudflap \
		--disable-libgomp \
		--with-system-zlib \
		--enable-languages=c

	${MAKE}
	${MAKE} install

	cd ${BASEDIR}
	mark 6
}

#############################################################
#
# build uClibc multilibs with first pass compiler
#

stage7()
{
	schk 7 || return 0
	# set -x

	cd ${UCLIBC}
	${MAKE} distclean
	rm -rf include/config
	mkdir include/config
	touch include/config/autoconf.h

	multilib_table | while read mlibdir pic shlib cflags
	do
		fix_uclibc_config $pic $shlib < $UCLIBC_CONFIG > .config

		if [ x"$shlib" = x"true" ] ; then
			# uClibc wants these to build shared version
			CONFIG_BINFMT_SHARED_FLAT=y
			export CONFIG_BINFMT_SHARED_FLAT
			OBJCOPY=${TARGET}-objcopy
			export OBJCOPY
			export ROOTDIR
		fi

		${MAKE} oldconfig CROSS="${TARGET}-" TARGET_ARCH=${_CPU} </dev/null || exit 1
		${MAKE} clean     CROSS="${TARGET}-" TARGET_ARCH=${_CPU} || true
		${MAKE} V=1 all   CROSS="${TARGET}-" TARGET_ARCH=${_CPU} ARCH_CFLAGS="${cflags}" </dev/null || exit 1

		destdir=${PREFIX}/${TARGET}/lib/$mlibdir
		mkdir -p $destdir
		cp lib/* $destdir/ || exit 1
		chmod 644 $destdir/*.[oa] || exit 1

	done || exit 1

	rm -rf include/config
	#cp_Lr ${UCLIBC}/include ${PREFIX}/${TARGET}/${sysinclude}

	cd $BASEDIR
	mark 7
}

#############################################################
#
# Rebuild gcc with everything
#

stage8()
{
	schk 8 || return 0

	rm -rf ${TARGET}-gcc
	mkdir ${TARGET}-gcc
	cd ${TARGET}-gcc

	${GCC}/configure ${HOST_TARGET} \
		--target=${TARGET} \
		${PREFIXOPT} \
		--enable-multilib \
		--disable-shared \
		--with-system-zlib \
		--enable-languages=c,c++

	${MAKE}
	${MAKE} install

	#
	# The _ctors.o file included in libgcc causes all kinds of random pain
	# sometimes it gets included and sometimes it doesn't.  By removing it
	# and using a good linker script (ala elf2flt.ld) all will be happy
	#
	find ${GCCLIB} -name libgcc.a -print | while read t
	do
		${TARGET}-ar dv "$t" _ctors.o
	done

	cd $BASEDIR
	mark 8
}

#############################################################
#
# build genromfs
#

stage9()
{
	schk 9 || return 0
	rm -rf genromfs-0.5.1
	extract genromfs-0.5.1.*
	cd genromfs-0.5.1
	if [ "${CYGWIN}" ]; then
		${PATCH} -p1 < ../genromfs-0.5.1-cygwin-020605.patch
	fi
	${MAKE}
	cp genromfs${EXE} ${PREFIX}/bin/.
	chmod 755 ${PREFIX}/bin/genromfs${EXE}

	cd $BASEDIR
	mark 9
}

#############################################################
#
# Add backward compatibility links
#

stageC()
{
	schk C || return 0

	if [ "$TARGET" != "$OLDTARGET" ] ; then
		cd ${PREFIX}/bin
		for file in \
			${TARGET}-addr2line \
			${TARGET}-ar \
			${TARGET}-as \
			${TARGET}-c++filt \
			${TARGET}-elf2flt \
			${TARGET}-flthdr \
			${TARGET}-ld \
			${TARGET}-ld.real \
			${TARGET}-nm \
			${TARGET}-objcopy \
			${TARGET}-objdump \
			${TARGET}-ranlib \
			${TARGET}-readelf \
			${TARGET}-size \
			${TARGET}-strings \
			${TARGET}-strip \
			${TARGET}-gcc \
			${TARGET}-gcov \
			${TARGET}-c++ \
			${TARGET}-g++ \
			${TARGET}-c++filt
		do
			ln -sf "$file" "`echo $file | sed -e "s/${TARGET}/${OLDTARGET}/"`"
		done
	fi

	cd $BASEDIR
	mark C
}


#############################################################
#
# make a self-extracting executable archive out of a tar-bzip
# that optionally pre-cleans the directory and checks a few things.
#
# build_sfx <BASE_NAME> [<CLEAN_FLAG>]
#
build_sfx()
{
	BASE_NAME="$1"
	CLEAN_FLAG=$2
	SH_ARCHIVE="${BASE_NAME}.sh"

	#
	# Create the shell script
	#
	cat <<!EOF > "${SH_ARCHIVE}"
#!/bin/sh

SCRIPT="\$0"
case "\${SCRIPT}" in
/*)
	;;
*)
	if [ -f "\${SCRIPT}" ]
	then
		SCRIPT="\`pwd\`/\${SCRIPT}"
	else
		SCRIPT="\`which \${SCRIPT}\`"
	fi
	;;
esac

cd /

if [ ! -f "\${SCRIPT}" ]
then
	echo "Cannot find the location of the install script (\$SCRIPT)"
	exit 1
fi

if [ ! -d "${PREFIX}" ]; then
	mkdir -p "${PREFIX}"
fi
if [ ! -w "${PREFIX}" ]
then
	echo "You must be root to install these tools."
	exit 1
fi

!EOF

	#
	# Add code to remove obsolete files if needed
	#
	if [ x"${CLEAN_FLAG}" = x"true" ] ; then
		cat <<!EOF >> "${SH_ARCHIVE}"
rm -rf "${GCCLIB}"
rm -f "${PREFIX}/bin/flthdr"
rm -f "${PREFIX}/bin/elf2flt"
rm -f "${PREFIX}/bin/${TARGET}-*"
rm -rf "${PREFIX}/${TARGET}"
!EOF
		if [ "$PREFIX" != "$GDBPREFIX" ] ; then
			cat <<!EOF >> "${SH_ARCHIVE}"
rm -rf "${GDBPREFIX}"
!EOF
		fi
		if [ "${TARGET}" != "$OLDTARGET" ] ; then
			#
			# Clean the mess made by target tuple switch
			#
			cat <<!EOF >> "${SH_ARCHIVE}"
rm -f "${PREFIX}/bin/${OLDTARGET}-*"
rm -rf "${PREFIX}/${OLDTARGET}"
!EOF
		fi
	fi

	#
	# Complete the script with archive extraction
	#
	cat <<!EOF >> "${SH_ARCHIVE}"
SKIP=\`awk '/^__ARCHIVE_FOLLOWS__/ { print NR + 1; exit 0; }' \${SCRIPT}\`
tail -n +\${SKIP} \${SCRIPT} | bunzip2 | tar xvf -

exit 0
__ARCHIVE_FOLLOWS__
!EOF

	#
	# Append tar archive and make the script executable
	#
	cat "${BASE_NAME}.tar.bz2" >> "${SH_ARCHIVE}"
	chmod 755 "${SH_ARCHIVE}"
}

#############################################################
#
# tar up everthing we have built
#
build_tar_file()
{
	# set -x
	cd /

	RELEASEDATE=`date +%Y%m%d`
	DIST_BASE="${BASEDIR}/${TARGET}-tools-${CYGWIN}${RELEASEDATE}"

	#EXTRAS=
	#if [ "${TARGET}" != "${OLDTARGET}" ] ; then
	#	EXTRAS="${EXTRAS} .${PREFIX}/bin/${OLDTARGET}-*"
	#fi

	#
	# strip the binaries,  make sure we don't strip the
	# libraries -- some platforms allow this :-(
	#
	strip ${PREFIX}/bin/genromfs${EXE} > /dev/null 2>&1 || true
	strip ${PREFIX}/bin/${TARGET}-* > /dev/null 2>&1 || true
	strip ${PREFIX}/${TARGET}/bin/* > /dev/null 2>&1 || true
	strip ${GCCLIB}/*[!ao] > /dev/null 2>&1 || true

	#
	# tar it all up
	#
	tar -cvjf "${DIST_BASE}.tar.bz2" \
		".${GCCLIB}" \
		".${GCCLIBEXEC}" \
		".${PREFIX}/${TARGET}" \
		.${PREFIX}/bin/${TARGET}-* \
		".${PREFIX}/bin/genromfs${EXE}" \
		${EXTRAS}
	build_sfx ${DIST_BASE} true

	cd $BASEDIR
}


#############################################################
#
# main - put everything together in order.
#
# Some setup
#

case ${TARGET} in
m68k*) _CPU=m68k; NOMMU=nommu ;;
arm*)  _CPU=arm;  NOMMU=nommu ;;
esac

#
# if not defined use the GNU tools default of /usr/local
#
if [ -z "${PREFIX}" ]; then
	PREFIX=/usr/local
else
	PREFIXOPT="--prefix=${PREFIX}"
fi

#
# This may fail until we've extracted GCC source.
# Will be redone later in stage1.
#
gcc_version_setup

#
# Choose config file for uClibc, either externally provieded or
# uClibc's default
#
UCLIBC_CONFIG="${BASEDIR}/uClibc-${UCLIBCVERS}-${_CPU}.config"
if [ ! -f "$UCLIBC_CONFIG" ]
then
	UCLIBC_CONFIG="${UCLIBC}/extra/Configs/Config.${_CPU}.default"
fi

#
# setup some Cygwin changes
#
if uname -o 2>/dev/null | grep -i "Cygwin" >/dev/null
then
	CYGWIN=cygwin-
	EXE=".exe"
	HOST_TARGET="--host=i386-pc-cygwin32"
else
	EXE=""
	HOST_TARGET=""
fi

#
# first check some args
#

case "$1" in
build)
	rm -f $BASEDIR/STAGE*
	;;
continue)
	# do nothing here
	;;
dist|tar)
	build_tar_file
	exit 0
	;;
clean)
	clean_all
	exit 0
	;;
uninstall)
	clean_uninstall
	exit 0
	;;
*)
	echo "Usage: $0 (build|continue|dist|clean|uninstall)" >&2
	echo "    build      build everything from scratch."
	echo "    continue   continue building from last error."
	echo "    dist       build binary archive for distribution."
	echo "    clean      clean all temporary files."
	echo "    uninstall  uninstall toolchain."
	exit 1
	;;
esac

#
# You have to be root for this one
#

if [ ! -d "${PREFIX}" ]; then
	mkdir -p "${PREFIX}"
fi

if [ ! -w "${PREFIX}" ]; then
	echo "Bad, PREFIX (${PREFIX}) is not writable! Perhaps you forgot to become root?"
	exit 1
fi

if [ ! -f "${ROOTDIR}/Makefile" -a ${TARGET} = m68k-elf ]; then
	echo "Bad, ROOTDIR (${ROOTDIR}) does not seem to contain an uClinux tree."
	echo "The uClinux tree is required when building uClibc as an id-based shared library."
	exit 1
fi

# set -x	# debug script
set -e		# if anything fails, stop

stage1
stage2
stage3
stage4
stage5
stage6
stage7
stage8
stage9

echo "--------------------------------------------------------"
echo "Build successful !"
echo "--------------------------------------------------------"

#############################################################
