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

PROGRAM		= bin/tag
MANPAGE		= Tag/tag.1

all: tag

help:
	@echo "Available targets:"
	@echo "  make                  Build the default Universal 2 binary (same as all)"
	@echo "  make all              Build the default Universal 2 binary"
	@echo "  make tag              Build bin/tag"
	@echo "  make native           Build a single-architecture binary for this Mac"
	@echo "  make check-universal  Verify bin/tag contains arm64 and x86_64 slices"
	@echo "  make test             Run the canonical local/CI test suite"
	@echo "  make test-lint        Run SwiftLint through the test alias"
	@echo "  make lint-swift       Run SwiftLint when installed"
	@echo "  make test-cli         Run subprocess CLI integration tests"
	@echo "  make test-universal   Verify the Universal 2 artifact"
	@echo "  make test-install     Verify staged install output"
	@echo "  make test-xcode       Build and verify Xcode Debug/Release outputs"
	@echo "  make test-man         Lint the man page when mandoc is installed"
	@echo "  make bin              Create the build output directory"
	@echo "  make clean            Remove build artifacts"
	@echo "  make distclean        Remove distribution/build artifacts"
	@echo "  make install          Install tag and its man page"
	@echo "  make installdirs      Create installation directories"
	@echo "  make uninstall        Remove installed tag and man page"

tag: ${PROGRAM}

${PROGRAM}: bin ${SRCS} Makefile
	@if [ "$(words ${ARCHS})" = "1" ]; then \
		for arch in ${ARCHS}; do \
			${SWIFTC} ${SWIFTFLAGS} -target "$$arch-apple-macos${MACOSX_DEPLOYMENT_TARGET}" ${SRCS} -o "${PROGRAM}"; \
		done; \
	else \
		tmpdir=$$(mktemp -d "$${TMPDIR:-/tmp}/tag-build.XXXXXX"); \
		outputs=""; \
		for arch in ${ARCHS}; do \
			mkdir -p "$$tmpdir/$$arch"; \
			${SWIFTC} ${SWIFTFLAGS} -target "$$arch-apple-macos${MACOSX_DEPLOYMENT_TARGET}" ${SRCS} -o "$$tmpdir/$$arch/tag" || { rm -rf "$$tmpdir"; exit 1; }; \
			outputs="$$outputs $$tmpdir/$$arch/tag"; \
		done; \
		lipo -create $$outputs -output "${PROGRAM}"; \
		rc=$$?; \
		rm -rf "$$tmpdir"; \
		exit $$rc; \
	fi

native:
	${MAKE} ARCHS="${NATIVE_ARCH}" clean tag

check-universal: tag
	@for arch in ${UNIVERSAL_ARCHS}; do \
		lipo ${PROGRAM} -verify_arch $$arch; \
	done
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
	for arch in ${UNIVERSAL_ARCHS}; do \
		lipo "$$dest${bindir}/tag" -verify_arch $$arch; \
	done; \
	rm -rf "$$dest"

test-xcode:
	xcodebuild -project Tag.xcodeproj -target Tag -configuration Debug build
	@for arch in ${UNIVERSAL_ARCHS}; do \
		lipo build/Debug/tag -verify_arch $$arch; \
	done
	xcodebuild -project Tag.xcodeproj -target Tag -configuration Release build
	@for arch in ${UNIVERSAL_ARCHS}; do \
		lipo build/Release/tag -verify_arch $$arch; \
	done

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

.PHONY: all help tag native check-universal test test-lint lint-swift test-cli test-universal test-install test-xcode test-man clean distclean install installdirs uninstall
