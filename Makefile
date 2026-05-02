prefix		= /usr/local

DSTMODE		= 0755
MANMODE		= 0644

INSTALL		= /usr/bin/install
MACOSX_DEPLOYMENT_TARGET ?= 15.0
SDKROOT		?= $(shell xcrun --sdk macosx --show-sdk-path)
CC		= xcrun clang
CFLAGS		+= -fobjc-arc -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}

bindir 		= ${prefix}/bin
man1dir		= ${prefix}/share/man/man1

SRCS		= Tag/main.m Tag/Tag.m Tag/TagName.m
LIBS		= -framework Foundation \
			  -framework CoreServices

PROGRAM		= bin/tag
MANPAGE		= Tag/tag.1

all: tag

tag: ${PROGRAM}

${PROGRAM}: bin ${SRCS} Makefile
	${CC} ${CFLAGS} ${SRCS} ${LIBS} -o ${PROGRAM}

bin:
	mkdir -p bin

clean:
	rm -Rf bin
	
distclean: clean

install: tag installdirs
	${INSTALL} -m ${DSTMODE} ${PROGRAM} ${DESTDIR}${bindir}
	${INSTALL} -m ${MANMODE} ${MANPAGE} ${DESTDIR}${man1dir}

installdirs:
	mkdir -p ${DESTDIR}${bindir}
	mkdir -p ${DESTDIR}${man1dir}

uninstall:
	rm -f ${DESTDIR}${bindir}/$(notdir ${PROGRAM})
	rm -f ${DESTDIR}${man1dir}/$(notdir ${MANPAGE})

.PHONY: all tag clean distclean install installdirs uninstall
