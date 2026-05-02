prefix		= /usr/local

DSTMODE		= 0755
MANMODE		= 0644

INSTALL		= /usr/bin/install
MACOSX_DEPLOYMENT_TARGET ?= 15.0
SDKROOT		?= $(shell xcrun --sdk macosx --show-sdk-path)
SWIFTC		= xcrun swiftc
ARCHS		?= arm64 x86_64
SWIFTFLAGS	+= -sdk ${SDKROOT}
UNIVERSAL_ARCHS	= arm64 x86_64
NATIVE_ARCH	= $(shell uname -m)

bindir 		= ${prefix}/bin
man1dir		= ${prefix}/share/man/man1

SRCS		= Tag/main.swift
ARCH_PROGRAMS	= $(foreach arch,${ARCHS},bin/.build/${arch}/tag)

PROGRAM		= bin/tag
MANPAGE		= Tag/tag.1

all: tag

tag: ${PROGRAM}

${PROGRAM}: bin ${ARCH_PROGRAMS}
	@if [ "$(words ${ARCHS})" = "1" ]; then \
		cp "${ARCH_PROGRAMS}" "${PROGRAM}"; \
	else \
		lipo -create ${ARCH_PROGRAMS} -output "${PROGRAM}"; \
	fi

bin/.build/%/tag: ${SRCS} Makefile
	mkdir -p $(@D)
	${SWIFTC} ${SWIFTFLAGS} -target $*-apple-macos${MACOSX_DEPLOYMENT_TARGET} ${SRCS} -o $@

native:
	${MAKE} ARCHS="${NATIVE_ARCH}" clean tag

check-universal: tag
	lipo ${PROGRAM} -verify_arch ${UNIVERSAL_ARCHS}
	lipo -info ${PROGRAM}
	file ${PROGRAM}

test: test-lint test-cli test-universal test-install test-xcode test-man

test-lint: lint-swift

lint-swift:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --config .swiftlint.yml; \
	else \
		echo "swiftlint not found; skipping SwiftLint (install with 'brew install swiftlint')"; \
	fi

test-cli: tag
	Tests/integration.sh

test-universal: check-universal

test-install: tag
	dest=$$(mktemp -d "$${TMPDIR:-/tmp}/tag-install.XXXXXX"); \
	${MAKE} install DESTDIR="$$dest"; \
	test -x "$$dest${bindir}/tag"; \
	test -f "$$dest${man1dir}/tag.1"; \
	lipo "$$dest${bindir}/tag" -verify_arch ${UNIVERSAL_ARCHS}; \
	rm -rf "$$dest"

test-xcode:
	xcodebuild -project Tag.xcodeproj -target Tag -configuration Debug build
	lipo build/Debug/tag -verify_arch ${UNIVERSAL_ARCHS}
	xcodebuild -project Tag.xcodeproj -target Tag -configuration Release build
	lipo build/Release/tag -verify_arch ${UNIVERSAL_ARCHS}

test-man:
	@if command -v mandoc >/dev/null 2>&1; then \
		mandoc -T lint ${MANPAGE}; \
	else \
		echo "mandoc not found; skipping man page lint"; \
	fi

bin:
	mkdir -p bin

clean:
	rm -Rf bin
	
distclean: clean

install: ARCHS=${UNIVERSAL_ARCHS}
install: tag check-universal installdirs
	${INSTALL} -m ${DSTMODE} ${PROGRAM} ${DESTDIR}${bindir}
	${INSTALL} -m ${MANMODE} ${MANPAGE} ${DESTDIR}${man1dir}

installdirs:
	mkdir -p ${DESTDIR}${bindir}
	mkdir -p ${DESTDIR}${man1dir}

uninstall:
	rm -f ${DESTDIR}${bindir}/$(notdir ${PROGRAM})
	rm -f ${DESTDIR}${man1dir}/$(notdir ${MANPAGE})

.PHONY: all tag native check-universal test test-lint lint-swift test-cli test-universal test-install test-xcode test-man clean distclean install installdirs uninstall
