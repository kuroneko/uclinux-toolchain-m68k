FROM ubuntu:24.04 AS build

RUN apt-get -yy update && apt-get -yy install build-essential zlib1g-dev wget \
	texinfo texi2html bison flex

WORKDIR /root/

COPY build-uclinux-tools.sh \
	binutils-2.25.1.tar.bz2 \
	uClibc-0.9.33.2.tar.xz uClibc-0.9.33.2-m68k.config \
	gcc-5.4.0.tar.bz2 gcc-5.4.0-fix-libgcc-build.patch gcc-5.4.0-fix-build-cxx-issues.patch \
	elf2flt-20160818.tar.gz elf2flt-20160818-fix-build.patch \
	linux-4.4.tar.gz \
	genromfs-0.5.1.tar.gz \
	.

RUN chmod a+x ./build-uclinux-tools.sh

ENV PATH=/opt/m68k-uclinux-tools/bin:/usr/local/bin:/usr/bin:/bin

RUN ./build-uclinux-tools.sh build

# finally, copy out the binaries only to shrink the final image size
FROM ubuntu:24.04

RUN apt-get -yy update && apt-get -yy install build-essential zlib1g-dev

COPY --from=build /opt/m68k-uclinux-tools /opt/m68k-uclinux-tools/

ENV PATH=/opt/m68k-uclinux-tools/bin:/usr/local/bin:/usr/bin:/bin
