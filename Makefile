# $Header: /cvsroot/autodoc/autodoc/Makefile,v 1.9 2009/08/11 18:50:02 rbt Exp $

# install configuration
DESTDIR =
PREFIX = /usr/local
BINDIR = ${PREFIX}/bin
DATADIR = ${PREFIX}/share/postgresql_autodoc
MANDIR = ${PREFIX}/share/man/man1


# build configuration
TEMPLATES = dia.tmpl dot.tmpl html.tmpl neato.tmpl xml.tmpl zigzag.dia.tmpl
BINARY = postgresql_autodoc
SOURCE = ${BINARY}.pl
MANPAGE = ${BINARY}.1
MANPAGE_SOURCE = ${MANPAGE}.in
RELEASE_FILES = Makefile ChangeLog ${SOURCE} ${TEMPLATES} ${MANPAGE}
RELEASE_DIR=postgresql_autodoc

# system tools
INSTALL_SCRIPT = $$(which install) -c
PERL = $$(which perl)
SED = $$(which sed)


all: ${BINARY} ${MANPAGE}

${MANPAGE}: ${MANPAGE_SOURCE}
	${SED} -e "s,@@TEMPLATE-DIR@@,${DATADIR}," \
		${MANPAGE_SOURCE} > ${MANPAGE}


${BINARY}: ${SOURCE}
	${SED} -e "s,/usr/bin/env perl,${PERL}," \
			-e "s,@@TEMPLATE-DIR@@,${DATADIR}," \
		 ${SOURCE} > ${BINARY}
	-chmod +x ${BINARY}

install: all
	${INSTALL_SCRIPT} -d ${DESTDIR}${BINDIR}
	${INSTALL_SCRIPT} -d ${DESTDIR}${DATADIR}
	${INSTALL_SCRIPT} -d ${DESTDIR}${MANDIR}
	${INSTALL_SCRIPT} -m 755 ${BINARY} ${DESTDIR}${BINDIR}
	for entry in ${TEMPLATES} ; \
		do ${INSTALL_SCRIPT} -m 644 $${entry} ${DESTDIR}${DATADIR} ; \
	done
	${INSTALL_SCRIPT} ${MANPAGE} ${DESTDIR}${MANDIR}

uninstall:
	-rm ${DESTDIR}${BINDIR}/${BINARY}
	-for entry in ${TEMPLATES} ; \
		do rm ${DESTDIR}${DATADIR}/$${entry} ; \
	done
	-rm ${DESTDIR}${MANDIR}/${MANPAGE}
	-rmdir ${DESTDIR}${MANDIR}
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
	mkdir ${RELEASE_DIR} && cp ${RELEASE_FILES} ${RELEASE_DIR} && tar -czvf ${RELEASE_DIR}-${VERSION}.tar.gz ${RELEASE_DIR}
	rm -r ${RELEASE_DIR}

.PHONY: install uninstall clean release
