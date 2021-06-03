AUTOMAKE_OPTIONS = foreign

ACLOCAL_AMFLAGS = -I m4

edit = sed \
	-e 's|@PACKAGE\@|$(PACKAGE)|g' \
	-e 's|@PACKAGE_BUGREPORT\@|$(PACKAGE_BUGREPORT)|g' \
	-e 's|@PACKAGE_NAME\@|$(PACKAGE_NAME)|g' \
	-e 's|@PACKAGE_URL\@|$(PACKAGE_URL)|g' \
	-e 's|@PACKAGE_VERSION\@|$(PACKAGE_VERSION)|g' \
	-e 's|@datadir\@|$(pkgdatadir)|g' \
	-e 's|@libexecdir\@|$(libexecdir)|g' \
	-e 's|@prefix\@|$(prefix)|g'

composed_bin_scripts = scripts/start-qemu.sh

bin_SCRIPTS = $(composed_bin_scripts)

composed_nobase_bin_scripts = tdd-lib/util.sh

nobase_bin_SCRIPTS = $(composed_nobase_bin_scripts)

$(composed_bin_scripts): % : Makefile $(srcdir)/%.in
	rm -f '$(@)' '$(@).tmp'
	mkdir -p '$(@D)'
	$(edit) '$(srcdir)/$(@).in' > '$(@).tmp'
	chmod +x '$(@).tmp'
	mv '$(@).tmp' '$(@)'

$(composed_nobase_bin_scripts): % : Makefile $(srcdir)/scripts/%
	rm -f '$(@)' '$(@).tmp'
	mkdir -p '$(@D)'
	$(edit) '$(srcdir)/scripts/$(@)' > '$(@).tmp'
	chmod +x '$(@).tmp'
	mv '$(@).tmp' '$(@)'

# 	mkdir -p '$(@D)'
# 	cp -av '$(srcdir)/scripts/$(@)' '$(@)'

EXTRA_DIST = bootstrap configure.ac COPYING m4 mit-plus-license.txt README.md \
	tests/* version.sh $(addsuffix .in, $(composed_bin_scripts)) \
	$(nobase_bin_SCRIPTS)

CLEANFILES = $(bin_SCRIPTS)

MAINTAINERCLEANFILES = aclocal.m4 compile config.h* configure depcomp \
 install-sh Makefile.in missing $(PACKAGE)-*.gz

maintainer-clean-local:
	rm -rf m4 .deps

.PHONY: help

help:
	@echo "Targets:"
	@echo "  make install"
	@echo "  make dist"
	@echo "  make distcheck"
	@echo "  make distclean"
	@echo "  make maintainer-clean"
