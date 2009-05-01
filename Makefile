# $Header: /cvsroot/autodoc/autodoc/Makefile,v 1.6 2009/05/01 02:14:29 rbt Exp $

# install configuration
DESTDIR =
PREFIX = /usr/local
BINDIR = ${PREFIX}/bin
DATADIR = ${PREFIX}/share/postgresql_autodoc

# build configuration
TEMPLATES = dia.tmpl dot.tmpl html.tmpl neato.tmpl xml.tmpl zigzag.dia.tmpl
BINARY = postgresql_autodoc
SOURCE = ${BINARY}.pl
RELEASE_FILES =	${SOURCE} ${TEMPLATES}

# system tools
INSTALL_SCRIPT = $$(which install) -c
PERL = $$(which perl)
SED = $$(which sed)


all: ${BINARY}

${BINARY}: ${SOURCE}
	${SED} -e "s,/usr/bin/env perl,${PERL}," \
			-e "s,@@TEMPLATE-DIR@@,${DATADIR}," \
		 ${SOURCE} > ${BINARY}
	-chmod +x ${BINARY}

install: all
	${INSTALL_SCRIPT} -d ${DESTDIR}${BINDIR}
	${INSTALL_SCRIPT} -d ${DESTDIR}${DATADIR}
	${INSTALL_SCRIPT} -m 755 ${BINARY} ${DESTDIR}${BINDIR}
	for entry in ${TEMPLATES} ; \
		do ${INSTALL_SCRIPT} -m 644 $${entry} ${DESTDIR}${DATADIR} ; \
	done

uninstall:
	-rm ${DESTDIR}${BINDIR}/${BINARY}
	-for entry in ${TEMPLATES} ; \
		do rm ${DESTDIR}${DATADIR}/$${entry} ; \
	done
	-rmdir ${DESTDIR}${DATADIR}
	-rmdir ${DESTDIR}${BINDIR}

clean:
	rm -f ${BINARY}

release: clean ${RELEASE_FILES}
	@if [ -z ${VERSION} ] ; then \
		echo "-------------------------------------------"; \
		echo "VERSION needs to be specified for a release"; \
		echo "-------------------------------------------"; \
		false; \
	fi
	cvs2cl
	-cvs commit
	dir=`pwd` && cd .. && tar -czvf postgresql_autodoc-${VERSION}.tar.gz \
		-C $${dir} ${RELEASE_FILES}

.PHONY: install uninstall clean release
