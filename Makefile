# $Header: /cvsroot/autodoc/autodoc/Makefile,v 1.1 2004/05/12 16:00:34 rbt Exp $

TEMPLATES = dia.tmpl dot.tmpl html.tmpl xml.tmpl zigzag.dia.tmpl
BINARY = postgresql_autodoc
CONFIGFILE = config.mk

RELEASE_FILES = Makefile config.mk.in configure \
				configure.ac $(TEMPLATES) install-sh \
				postgresql_autodoc.pl

cur-dir   := $(shell basename ${PWD})
REAL_RELEASE_FILES = $(addprefix $(cur-dir)/,$(RELEASE_FILES))

# Global dependencies
ALWAYS_DEPEND = Makefile configure $(CONFIGFILE)


####
# Test to see if $(CONFIGFILE) has been generated.  If so, include it. Otherwise we assume
# it will be created for us.
has_configmk := $(wildcard $(CONFIGFILE))

ifeq ($(has_configmk),$(CONFIGFILE))
include $(CONFIGFILE)
endif

####
# ALL
.PHONY: all
all: $(ALWAYS_DEPEND) $(BINARY)

####
# Replace the /usr/bin/env perl with the supplied path
# chmod to make testing easier
$(BINARY): postgresql_autodoc.pl $(CONFIGFILE)
	$(SED) -e "s,/usr/bin/env perl,$(PERL)," \
			-e "s,@@TEMPLATE-DIR@@,$(datadir)," \
		 postgresql_autodoc.pl > $(BINARY)
	-chmod +x $(BINARY)

####
# INSTALL Target
.PHONY: install
install: all $(ALWAYS_DEPEND)
	$(INSTALL_SCRIPT) -d $(bindir)
	$(INSTALL_SCRIPT) -d $(datadir)
	$(INSTALL_SCRIPT) -m 755 $(BINARY) $(bindir)
	for entry in $(TEMPLATES) ; \
		do $(INSTALL_SCRIPT) -m 644 $${entry} $(datadir) ; \
	done

####
# CLEAN / DISTRIBUTION-CLEAN / MAINTAINER-CLEAN Targets
.PHONY: clean
clean: $(ALWAYS_DEPEND)
	$(RM) $(BINARY)

.PHONY: distribution-clean distclean
distribution-clean distclean: clean
	$(RM) $(CONFIGFILE) config.log config.status
	$(RM) -r autom4te.cache
	$(RM) $(patsubst %.tmpl,*.%,$(wildcard *.tmpl))

.PHONY: maintainer-clean
maintainer-clean: distribution-clean
	$(RM) configure

####
# Build a release
#
#	Clean
#	Ensure configure is up to date
#	Commit any pending elements
#	Tar up the results
.PHONY: release
release: distribution-clean configure $(RELEASE_FILES)
	@if [ -z ${VERSION} ] ; then \
		echo "-------------------------------------------"; \
		echo "VERSION needs to be specified for a release"; \
		echo "-------------------------------------------"; \
		false; \
	fi
	cvs2cl
	-cvs commit
	cd ../ && tar -czvf postgresql_autodoc-${VERSION}.tar.gz $(REAL_RELEASE_FILES)

####
# Build and Run configure files when configure or a template is updated.
configure: configure.ac
	autoconf

# Fix my makefile, then execute myself
$(CONFIGFILE) : config.mk.in configure
	./configure
	$(MAKE) $(MAKEFLAGS)
