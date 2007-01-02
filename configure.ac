AC_PREREQ(2.53)
AC_REVISION($Header: /cvsroot/autodoc/autodoc/Attic/configure.ac,v 1.2 2007/01/02 13:53:19 rbt Exp $)
AC_INIT(postgresql_autodoc.pl)


# Programs
AC_PROG_INSTALL

AC_PATH_PROGS([SED], [sed], ,
             [$PATH:/bin:/usr/bin])

# Check for Perl
AC_ARG_WITH(perl-prefix,
	[  --with-perl-prefix      Location of Perl],
	PERLPATH=$withval,
	PERLPATH="")

if ( test -n "$PERLPATH" -a "`echo $PERLPATH | cut -c-3`" = "../" ); then
	PERLPATH="$PWD/$PERLPATH"
fi

PERL=""
if ( test -n "$PERLPATH" ); then
	AC_CHECK_FILE("$PERLPATH/bin/perl",PERL="$PERLPATH/bin/perl")
else
	AC_PATH_PROGS([PERL], [perl], ,
   	          [$PATH:/usr/bin:/usr/local/bin:/usr/pkg/bin:/usr/local/perl/bin:/opt/sfw/bin])
fi
if ( test -z "$PERL" ); then
	AC_MSG_ERROR("Perl is required")
fi
AC_SUBST(PERL)


# Check that Perl Libraries are available:
#	DBI
#	DBD::Pg
#	Fcntl
#	HTML::Template
#	Term::ReadKey
#
# Output of if test redirected to /dev/null to keep quiet
for module in DBI DBD::Pg Fcntl HTML::Template Term::ReadKey ; do
	AC_MSG_CHECKING(${module})
	if [ ! (${PERL} -e "use ${module}" 2>&1 /dev/null ) ]; then
		AC_MSG_RESULT(no)
		AC_MSG_ERROR(Perl module ${module} is required)
	else
		AC_MSG_RESULT(yes)
	fi
done


AC_OUTPUT([
config.mk
])
