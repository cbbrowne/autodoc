#!/usr/bin/env perl
# -- # -*- Perl -*-w
# $Header: /cvsroot/autodoc/autodoc/postgresql_autodoc.pl,v 1.4 2004/06/29 16:40:40 rbt Exp $
#  Imported 1.22 2002/02/08 17:09:48 into sourceforge

# Postgres Auto-Doc Version 1.23

# License
# -------
# Copyright (c) 2001-2004, Rod Taylor
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1.   Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#
# 2.   Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials provided
#      with the distribution.
#
# 3.   Neither the name of the InQuent Technologies Inc. nor the names
#      of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written
#      permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE FREEBSD
# PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# About Project
# -------------
# Various details about the project and related items can be found at 
# the website
#
# http://www.rbt.ca/autodoc/

use DBI;
use strict;

# Allows file locking
use Fcntl;

## Useful for debugging ##
#use Data::Dumper;

# Allows file templates
use HTML::Template;

# The templates path
# @@TEMPLATE-DIR@@ will be replaced by make in the build phase
my $template_path = '@@TEMPLATE-DIR@@';

# Setup the default connection variables based on the environment
my $dbuser = $ENV{'PGUSER'};
$dbuser ||= $ENV{'USER'};

my $database = $ENV{'PGDATABASE'};
$database ||= $dbuser;

my $dbhost = $ENV{'PGHOST'};
$dbhost ||= "";

my $dbport = $ENV{'PGPORT'};
$dbport ||= "";

my $dbpass = "";
my $output_filename_base = $database;

# Tracking variables
my $dbisset = 0;
my $fileisset = 0;

my $only_schema;

my $wanted_output = undef; # means all types

my $statistics = 0;

# Fetch base and dirnames.  Useful for Usage()
my $basename = $0;
my $dirname = $0;
$basename =~ s|^.*/([^/]+)$|$1|;
$dirname =~ s|^(.*)/[^/]+$|$1|;

# If template_path isn't defined, lets set it ourselves
$template_path = $dirname if (!defined($template_path));

for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
  ARGPARSE: for ( $ARGV[$i] ) {
		# Set the database
		/^-d$/ && do {
			$database = $ARGV[ ++$i ];
			$dbisset  = 1;
			if ( !$fileisset ) {
				$output_filename_base = $database;
			}
			last;
		};

		# Set the user
		/^-[uU]$/ && do {
			$dbuser = $ARGV[ ++$i ];
			if ( !$dbisset ) {
				$database = $dbuser;
				if ( !$fileisset ) {
					$output_filename_base = $database;
				}
			}
			last;
		};

		# Set the hostname
		/^-h$/ && do { $dbhost = $ARGV[ ++$i ]; last; };

		# Set the Port
		/^-p$/ && do { $dbport = $ARGV[ ++$i ]; last; };

		# Set the users password
		/^--password=/ && do {
			$dbpass = $ARGV[$i];
			$dbpass =~ s/^--password=//g;
			last;
		};

		# Set the base of the filename.  The extensions pulled from the templates
		# will be appended to this name
		/^-f$/ && do {
			$output_filename_base = $ARGV[++$i];
			$fileisset	  = 1;
			last;
		};

		# Set the template directory explicitly
		/^(-l|--library)$/ && do {
			$template_path = $ARGV[++$i];
			last;
		};

		# Set the output type
		/^(-t|--type)$/ && do {
			$wanted_output = $ARGV[++$i];
			last;
		};

		# User has requested a single schema dump and provided a pattern
		/^(-s|--schema)$/ && do {
			$only_schema = $ARGV[++$i];
			last;
		};

		# Check to see if Statistics have been requested
		/^--statistics$/ && do {
			$statistics = 1;
			last;
		};

		# Help is wanted, redirect user to usage()
		/^-\?$/	&& do { usage(); last; };
		/^--help$/ && do { usage(); last; };
	}
}

# If no arguments have been provided, connect to the database anyway but
# inform the user of what we're doing.
if ( $#ARGV <= 0 ) {
	print <<Msg
No arguments set.  Use '$basename --help' for help

Connecting to database '$database' as user '$dbuser'
Msg
;
}


# Database Connection
my $dsn = "dbi:Pg:dbname=$database";
$dsn .= ";host=$dbhost" if ( "$dbhost" ne "" );
$dsn .= ";port=$dbport" if ( "$dbport" ne "" );
my $dbh = DBI->connect( $dsn, $dbuser, $dbpass )
	or triggerError("Unable to connect due to: $DBD::Pg::errstr");

# Always disconnect from the database if a database handle is setup
END {
	$dbh->disconnect() if $dbh;
}

# PostgreSQL's version is used to determine what queries are required
# to retrieve a given information set.
my $sql_GetVersion = qq{
  SELECT cast(substr(version(), 12, 1) as integer) * 10000
		 + cast(substr(version(), 14, 1) as integer) * 100
		 as version;
};

my $sth_GetVersion = $dbh->prepare($sql_GetVersion);
$sth_GetVersion->execute();
my $version   = $sth_GetVersion->fetchrow_hashref;
my $pgversion = $version->{'version'};

# Ensure we only get information for the requested schemas.
#
# system_schema	     -> The primary system schema for a database.
#                       Public is used for verions prior to 7.3
#
# system_schema_list -> The list of schemas which we are not supposed
#                       to gather information for.
#                        TODO: Merge with system_schema in array form.
#
# schemapattern      -> The schema the user provided as a command
#                       line option.
my $schemapattern = '^';
my $system_schema;
my $system_schema_list;
if ( $pgversion >= 70300 ) {
	$system_schema = 'pg_catalog';
	$system_schema_list = 'pg_catalog|information_schema';
	if (defined($only_schema)) {
		$schemapattern = '^'. $only_schema .'$';
	}
}
else {
	$system_schema = 'public';
	$system_schema_list = $system_schema;
}

#
# List of queries which are used to gather information from the
# database. The queries differ based on version but should 
# provide similar output. At some point it should be safe to remove
# support for older database versions.
#
my $sql_Columns;
my $sql_Constraint;
my $sql_Database;
my $sql_Foreign_Keys;
my $sql_Foreign_Key_Arg;
my $sql_Function;
my $sql_FunctionArg;
my $sql_Indexes;
my $sql_Primary_Keys;
my $sql_Schema;
my $sql_Tables;
my $sql_Table_Statistics;

# Pull out a list of tables, views and special structures. 
if ( $pgversion >= 70300 ) {
	$sql_Tables = qq{
	SELECT nspname as namespace
		 , relname as tablename
		 , pg_catalog.pg_get_userbyid(relowner) AS tableowner
		 , relhasindex as hasindexes
		 , relhasrules as hasrules
		 , reltriggers as hastriggers
		 , pg_class.oid
		 , pg_catalog.obj_description(pg_class.oid, 'pg_class') as table_description
		 , relacl
		 , CASE
		   WHEN relkind = 'r' THEN
			 'table'
		   WHEN relkind = 's' THEN
			 'special'
		   ELSE
			 'view'
		   END as reltype
		 , CASE
		   WHEN relkind = 'v' THEN
			 pg_get_viewdef(pg_class.oid)
		   ELSE
			 NULL
		   END as view_definition
	  FROM pg_catalog.pg_class
	  JOIN pg_catalog.pg_namespace ON (relnamespace = pg_namespace.oid)
	 WHERE relkind IN ('r', 's', 'v')
	   AND nspname !~ '$system_schema_list'
	   AND nspname ~ '$schemapattern';
	};

	# - uses pg_class.oid
	$sql_Columns = qq{
	SELECT attname as column_name
		 , attlen as column_length
		 , CASE
		   WHEN pg_type.typname = 'int4'
				AND EXISTS (SELECT TRUE
							  FROM pg_catalog.pg_depend
							  JOIN pg_catalog.pg_class ON (pg_class.oid = objid)
							 WHERE refobjsubid = attnum
							   AND refobjid = attrelid
							   AND relkind = 'S') THEN
			 'serial'
		   WHEN pg_type.typname = 'int8'
				AND EXISTS (SELECT TRUE
							  FROM pg_catalog.pg_depend
							  JOIN pg_catalog.pg_class ON (pg_class.oid = objid)
							 WHERE refobjsubid = attnum
							   AND refobjid = attrelid
							   AND relkind = 'S') THEN
			 'bigserial'
		   ELSE
			 pg_catalog.format_type(atttypid, atttypmod)
		   END as column_type
		 , CASE
		   WHEN attnotnull THEN
			 cast('NOT NULL' as text)
		   ELSE
			 cast('' as text)
		   END as column_null
		 , CASE
		   WHEN pg_type.typname IN ('int4', 'int8')
				AND EXISTS (SELECT TRUE
							  FROM pg_catalog.pg_depend
							  JOIN pg_catalog.pg_class ON (pg_class.oid = objid)
							 WHERE refobjsubid = attnum
							   AND refobjid = attrelid
							   AND relkind = 'S') THEN
			 NULL
		   ELSE
			 adsrc
		   END as column_default
		 , pg_catalog.col_description(attrelid, attnum) as column_description
		 , attnum
	  FROM pg_catalog.pg_attribute 
				 JOIN pg_catalog.pg_type ON (pg_type.oid = atttypid) 
	  LEFT OUTER JOIN pg_catalog.pg_attrdef ON (   attrelid = adrelid 
											   AND attnum = adnum)
	 WHERE attnum > 0
	   AND attisdropped IS FALSE
	   AND attrelid = ?;
	};

}
elsif ( $pgversion >= 70200 ) {
	$sql_Tables = qq{
	SELECT 'public' as namespace
		 , relname as tablename
		 , pg_get_userbyid(relowner) AS tableowner
		 , relhasindex as hasindexes
		 , relhasrules as hasrules
		 , reltriggers as hastriggers
		 , pg_class.oid
		 , obj_description(pg_class.oid, 'pg_class') as table_description
		 , relacl
		 , CASE
		   WHEN relkind = 'r' THEN
			 'table'
		   WHEN relkind = 's' THEN
			 'special'
		   ELSE
			 'view'
		   END as reltype
		 , CASE
		   WHEN relkind = 'v' THEN
			 pg_get_viewdef(pg_class.relname)
		   ELSE
			 NULL
		   END as view_definition
	  FROM pg_class
	 WHERE relkind in ('r', 's', 'v')
	   AND relname NOT LIKE 'pg_%';
	};

	# - uses pg_class.oid
	$sql_Columns = qq{
	SELECT attname as column_name
		 , attlen as column_length
		 , CASE
		   WHEN pg_type.typname = 'int4'
				AND adsrc LIKE 'nextval(%' THEN
			 'serial'
		   WHEN pg_type.typname = 'int8'
				AND adsrc LIKE 'nextval(%' THEN
			 'bigserial'
		   ELSE
			 format_type(atttypid, atttypmod)
		   END as column_type
		 , CASE
		   WHEN attnotnull IS TRUE THEN
			 'NOT NULL'::text
		   ELSE
			 ''::text
		   END as column_null
		 , CASE
		   WHEN pg_type.typname in ('int4', 'int8')
				AND adsrc LIKE 'nextval(%' THEN
			 NULL
		   ELSE
			 adsrc
		   END as column_default
		 , col_description(attrelid, attnum) as column_description
		 , attnum
	  FROM pg_attribute 
				 JOIN pg_type ON (pg_type.oid = pg_attribute.atttypid) 
	  LEFT OUTER JOIN pg_attrdef ON (   pg_attribute.attrelid = pg_attrdef.adrelid 
									AND pg_attribute.attnum = pg_attrdef.adnum)
	 WHERE attnum > 0
	   AND attrelid = ?;
	};

}
else {
	# 7.1 or earlier has a different description structure

	$sql_Tables = qq{
	SELECT 'public' as namespace
		 , relname as tablename
		 , pg_get_userbyid(relowner) AS tableowner
		 , relhasindex as hasindexes
		 , relhasrules as hasrules
		 , reltriggers as hastriggers
		 , pg_class.oid
		 , obj_description(pg_class.oid) as table_description
		 , 'table' as reltype
		 , NULL as view_definition
	  FROM pg_class
	 WHERE relkind IN ('r', 's')
	   AND relname NOT LIKE 'pg_%';
	};

	# - uses pg_class.oid
	$sql_Columns = qq{
	SELECT attname as column_name
		 , attlen as column_length
		 , CASE
		   WHEN pg_type.typname = 'int4'
				AND adsrc LIKE 'nextval(%' THEN
			 'serial'
		   WHEN pg_type.typname = 'int8'
				AND adsrc LIKE 'nextval(%' THEN
			 'bigserial'
		   ELSE
			 format_type(atttypid, atttypmod)
		   END as column_type
		 , CASE
		   WHEN attnotnull IS TRUE THEN
			 'NOT NULL'::text
		   ELSE
			 ''::text
		   END as column_null
		 , CASE
		   WHEN pg_type.typname in ('int4', 'int8')
				AND adsrc LIKE 'nextval(%' THEN
			 NULL
		   ELSE
			 adsrc
		   END as column_default
		 , description as column_description
		 , attnum
	  FROM pg_attribute 
				 JOIN pg_type ON (pg_type.oid = pg_attribute.atttypid) 
	  LEFT OUTER JOIN pg_attrdef ON (   pg_attribute.attrelid = pg_attrdef.adrelid 
									AND pg_attribute.attnum = pg_attrdef.adnum)
	  LEFT OUTER JOIN pg_description ON (pg_description.objoid = pg_attribute.oid)
	 WHERE attnum > 0
	   AND attrelid = ?;
	};
}

if ($statistics == 1)
{
	if ($pgversion <= 70300) {
		triggerError("Table statistics supported on PostgreSQL 7.4 and later.\nRemove --statistics flag and try again.");
	}

	$sql_Table_Statistics = qq{
		SELECT table_len
		     , tuple_count
		     , tuple_len
		     , CAST(tuple_percent AS numeric(20,2)) AS tuple_percent
		     , dead_tuple_count
		     , dead_tuple_len
		     , CAST(dead_tuple_percent AS numeric(20,2)) AS dead_tuple_percent
		     , CAST(free_space AS numeric(20,2)) AS free_space
		     , CAST(free_percent AS numeric(20,2)) AS free_percent
		  FROM pgstattuple(CAST(? AS oid));
	};
}

if ($pgversion >= 70300)
{
	$sql_Indexes = qq{
	SELECT schemaname
	     , tablename
	     , indexname
	     , substring(    indexdef
	                FROM position('(' IN indexdef) + 1
                     FOR length(indexdef) - position('(' IN indexdef) - 1
                    ) AS indexdef
      FROM pg_catalog.pg_indexes
	 WHERE substring(indexdef FROM 8 FOR 6) != 'UNIQUE'
	   AND schemaname = ?
	   AND tablename = ?;
	};
} else {
	$sql_Indexes = qq{
	SELECT NULL AS schemaname
	     , NULL AS tablename
	     , NULL AS indexname
	     , NULL AS indexdef
	 WHERE TRUE = FALSE AND ? = ?;
	};
}


# Fetch the list of PRIMARY and UNIQUE keys
if ($pgversion >= 70300)
{
	$sql_Primary_Keys = qq{
	SELECT conname AS constraint_name
		 , pg_catalog.pg_get_indexdef(d.objid) AS constraint_definition
		 , CASE
		   WHEN contype = 'p' THEN
			 'PRIMARY KEY'
		   ELSE
			 'UNIQUE'
		   END as constraint_type
	  FROM pg_catalog.pg_constraint AS c
	  JOIN pg_catalog.pg_depend AS d ON (d.refobjid = c.oid)
	 WHERE contype IN ('p', 'u')
	   AND deptype = 'i'
	   AND conrelid = ?;
	};

} else {
	# - uses pg_class.oid
	$sql_Primary_Keys = qq{
	SELECT i.relname AS constraint_name
		 , pg_get_indexdef(pg_index.indexrelid) AS constraint_definition
		 , CASE
		   WHEN indisprimary THEN
			 'PRIMARY KEY'
		   ELSE
			 'UNIQUE'
		   END as constraint_type
	  FROM pg_index
		 , pg_class as i 
	 WHERE i.oid = pg_index.indexrelid
	   AND pg_index.indisunique
	   AND pg_index.indrelid = ?;
	};
}

# FOREIGN KEY fetch
#
# Don't return the constraint name if it was automatically generated by
# PostgreSQL.  The $N (where N is an integer) is not a descriptive enough
# piece of information to be worth while including in the various outputs.
if ( $pgversion >= 70300 ) {
	$sql_Foreign_Keys = qq{
	SELECT pg_constraint.oid
		 , pg_namespace.nspname AS namespace
		 , CASE WHEN substring(pg_constraint.conname FROM 1 FOR 1) = '\$' THEN ''
		   ELSE pg_constraint.conname
		   END AS constraint_name
		 , conkey AS constraint_key
		 , confkey AS constraint_fkey
		 , confrelid AS foreignrelid
	  FROM pg_catalog.pg_constraint
	  JOIN pg_catalog.pg_class ON (pg_class.oid = conrelid)
	  JOIN pg_catalog.pg_class AS pc ON (pc.oid = confrelid)
	  JOIN pg_catalog.pg_namespace ON (pg_class.relnamespace = pg_namespace.oid)
	  JOIN pg_catalog.pg_namespace AS pn ON (pn.oid = pc.relnamespace)
	 WHERE contype = 'f'
	   AND conrelid = ?
	   AND pg_namespace.nspname ~ '$schemapattern'
	   AND pn.nspname ~ '$schemapattern';
	};

	$sql_Foreign_Key_Arg = qq{
	 SELECT attname AS attribute_name
		  , relname AS relation_name
		  , nspname AS namespace
	   FROM pg_catalog.pg_attribute
	   JOIN pg_catalog.pg_class ON (pg_class.oid = attrelid)
	   JOIN pg_catalog.pg_namespace ON (relnamespace = pg_namespace.oid)
	  WHERE attrelid = ?
		AND attnum = ?;
	};
}
else {
	# - uses pg_class.oid
	$sql_Foreign_Keys = q{
	SELECT oid
		 , 'public' AS namespace
		 , CASE WHEN substring(tgname from 1 for 1) = '$' THEN ''
		   ELSE tgname
		   END AS constraint_name
		 , tgnargs AS number_args
		 , tgargs AS args
	  FROM pg_trigger
	 WHERE tgisconstraint = TRUE
	   AND tgtype = 21
	   AND tgrelid = ?;
	};

	$sql_Foreign_Key_Arg = qq{SELECT TRUE WHERE ? = 0 and ? = 0;};
}

# Fetch CHECK constraints
if ( $pgversion >= 70400 ) {
	$sql_Constraint = qq{
	SELECT pg_get_constraintdef(oid) AS constraint_source
		 , conname AS constraint_name
	  FROM pg_constraint
	 WHERE conrelid = ?
	   AND contype = 'c';
	};
}
elsif ( $pgversion >= 70300 ) {
	$sql_Constraint = qq{
	SELECT 'CHECK ' || pg_catalog.substr(consrc, 2, length(consrc) - 2) AS constraint_source
		 , conname AS constraint_name
	  FROM pg_constraint
	 WHERE conrelid = ?
	   AND contype = 'c';
	};
}
else {
	$sql_Constraint = qq{
	SELECT 'CHECK ' || substr(rcsrc, 2, length(rcsrc) - 2) AS constraint_source
		 , rcname AS constraint_name
	  FROM pg_relcheck
	 WHERE rcrelid = ?;
	};
}

# Query for function information
if ( $pgversion >= 70300 ) {
	$sql_Function = qq{
	  SELECT proname AS function_name
		   , nspname AS namespace
		   , lanname AS language_name
		   , pg_catalog.obj_description(pg_proc.oid, 'pg_proc') AS comment
		   , proargtypes AS function_args
		   , prosrc AS source_code
		   , proretset AS returns_set
		   , prorettype AS return_type
		FROM pg_catalog.pg_proc
		JOIN pg_catalog.pg_language ON (pg_language.oid = prolang)
		JOIN pg_catalog.pg_namespace ON (pronamespace = pg_namespace.oid)
		JOIN pg_catalog.pg_type ON (prorettype = pg_type.oid)
	   WHERE pg_namespace.nspname !~ '$system_schema_list'
		 AND pg_namespace.nspname ~ '$schemapattern'
	     AND proname != 'plpgsql_call_handler';
	};

	$sql_FunctionArg = qq{
	  SELECT nspname AS namespace
		   , pg_catalog.format_type(pg_type.oid, typtypmod) AS type_name
		FROM pg_catalog.pg_type
		JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = typnamespace)
	   WHERE pg_type.oid = ?;
	};
}
else {
	$sql_Function = qq{
	SELECT proname AS function_name
		 , 'public' AS namespace
		 , lanname AS language_name
		 , description AS comment
		 , proargtypes AS function_args
		 , prosrc AS source_code
		 , proretset AS returns_set
		 , prorettype AS return_type
	  FROM pg_proc
	  JOIN pg_language ON (pg_language.oid = prolang)
	  LEFT OUTER JOIN pg_description ON (objoid = pg_proc.oid)
	 WHERE pg_proc.oid > 16000
	   AND proname != 'plpgsql_call_handler';
	 };

	$sql_FunctionArg = qq{
	SELECT 'public' AS namespace
		 , format_type(pg_type.oid, typtypmod) AS type_name
	  FROM pg_type
	 WHERE pg_type.oid = ?;
	};
}

# Fetch schema information.
if ( $pgversion >= 70300 ) {
	$sql_Schema = qq{
	SELECT pg_catalog.obj_description(oid, 'pg_namespace') AS comment
		 , nspname as namespace
	  FROM pg_catalog.pg_namespace;
	};
}
else {
	# In PostgreSQL 7.2 and prior, schemas were not a part of the system.
	# Dummy query returns no rows to prevent added logic later on.
	$sql_Schema = qq{SELECT TRUE WHERE TRUE = FALSE;};
}

# Fetch the description of the database
if ($pgversion >= 70300) {
	$sql_Database = qq{
	SELECT pg_catalog.obj_description(oid, 'pg_database') as comment
	  FROM pg_catalog.pg_database
	 WHERE datname = '$database';
	};
}
elsif ($pgversion == 70200) {
	$sql_Database = qq{
	SELECT obj_description(oid, 'pg_database') as comment
	  FROM pg_database
	 WHERE datname = '$database';
	};
}
else {
	# In PostgreSQL 7.1, the database did not have comment support
	$sql_Database = qq{ SELECT TRUE as comment WHERE TRUE = FALSE;};
}

my $sth_Columns			= $dbh->prepare($sql_Columns);
my $sth_Constraint		= $dbh->prepare($sql_Constraint);
my $sth_Database		= $dbh->prepare($sql_Database);
my $sth_Foreign_Keys	= $dbh->prepare($sql_Foreign_Keys);
my $sth_Foreign_Key_Arg	= $dbh->prepare($sql_Foreign_Key_Arg);
my $sth_Function		= $dbh->prepare($sql_Function);
my $sth_FunctionArg		= $dbh->prepare($sql_FunctionArg);
my $sth_Indexes			= $dbh->prepare($sql_Indexes);
my $sth_Primary_Keys	= $dbh->prepare($sql_Primary_Keys);
my $sth_Schema			= $dbh->prepare($sql_Schema);
my $sth_Tables			= $dbh->prepare($sql_Tables);
my $sth_Table_Statistics = $dbh->prepare($sql_Table_Statistics);

my %structure;
my %struct;

# Fetch Database info
$sth_Database->execute();
my $dbinfo = $sth_Database->fetchrow_hashref;
if ( defined($dbinfo) ) {
	$struct{'DATABASE'}{$database}{'COMMENT'} = $dbinfo->{'comment'};
}

# Fetch tables and all things bound to tables
$sth_Tables->execute();
while ( my $tables = $sth_Tables->fetchrow_hashref ) {
	my $reloid  = $tables->{'oid'};
	my $relname = $tables->{'tablename'};

	my $group = $tables->{'namespace'};

	EXPRESSIONFOUND:

	# Store permissions
	my $acl = $tables->{'relacl'};

	# Empty acl groups cause serious issues.
	$acl ||= '';
	
	# Strip array forming 'junk'.
	$acl =~ s/^{//g;
	$acl =~ s/}$//g;
	$acl =~ s/"//g;

	# Foreach acl
	foreach ( split ( /\,/, $acl ) ) {
		my ( $user, $raw_permissions ) = split ( /=/, $_ );

		if ( defined($raw_permissions) ) {
			if ( $user eq '' ) {
				$user = 'PUBLIC';
			}

			# The section after the / is the user who granted the permissions
			my ( $permissions, $granting_user) = split ( /\//, $raw_permissions );

			# Break down permissions to individual flags
			if ( $permissions =~ /a/ ) {
				$structure{$group}{$relname}{'ACL'}{$user}{'INSERT'} = 1;
			}

			if ( $permissions =~ /r/ ) {
				$structure{$group}{$relname}{'ACL'}{$user}{'SELECT'} = 1;
			}

			if ( $permissions =~ /w/ ) {
				$structure{$group}{$relname}{'ACL'}{$user}{'UPDATE'} = 1;
			}

			if ( $permissions =~ /d/ ) {
				$structure{$group}{$relname}{'ACL'}{$user}{'DELETE'} = 1;
			}

			if ( $permissions =~ /R/ ) {
				$structure{$group}{$relname}{'ACL'}{$user}{'RULE'} = 1;
			}

			if ( $permissions =~ /x/ ) {
				$structure{$group}{$relname}{'ACL'}{$user}{'REFERENCES'} = 1;
			}

			if ( $permissions =~ /t/ ) {
				$structure{$group}{$relname}{'ACL'}{$user}{'TRIGGER'} = 1;
			}
		}
	}

	# Primitive Stats, but only if requested
	if ($statistics == 1)
	{
		$sth_Table_Statistics->execute($reloid);

		my $stats = $sth_Table_Statistics->fetchrow_hashref;

		$structure{$group}{$relname}{'TABLELEN'} = $stats->{'table_len'};
		$structure{$group}{$relname}{'TUPLECOUNT'} = $stats->{'tuple_count'};
		$structure{$group}{$relname}{'TUPLELEN'} = $stats->{'tuple_len'};
		$structure{$group}{$relname}{'DEADTUPLELEN'} = $stats->{'dead_tuple_len'};
		$structure{$group}{$relname}{'FREELEN'} = $stats->{'free_space'};
	}

	# Store the relation type
	$structure{$group}{$relname}{'TYPE'} = $tables->{'reltype'};

	# Store table description
	$structure{$group}{$relname}{'DESCRIPTION'} = $tables->{'table_description'};

	# Store the view definition
	$structure{$group}{$relname}{'VIEW_DEF'} = $tables->{'view_definition'};

	# Store constraints
	$sth_Constraint->execute($reloid);
	while ( my $cols = $sth_Constraint->fetchrow_hashref ) {
		my $constraint_name = $cols->{'constraint_name'};
		$structure{$group}{$relname}{'CONSTRAINT'}{$constraint_name} =
		  $cols->{'constraint_source'};
	}

	$sth_Columns->execute($reloid);
	my $i = 1;
	while ( my $cols = $sth_Columns->fetchrow_hashref ) {
		my $column_name = $cols->{'column_name'};
		$structure{$group}{$relname}{'COLUMN'}{$column_name}{'ORDER'} =
		  $cols->{'attnum'};
		$structure{$group}{$relname}{'COLUMN'}{$column_name}{'PRIMARY KEY'} =
		  0;
		$structure{$group}{$relname}{'COLUMN'}{$column_name}{'FKTABLE'}   = '';
		$structure{$group}{$relname}{'COLUMN'}{$column_name}{'TYPE'} =
		  $cols->{'column_type'};
		$structure{$group}{$relname}{'COLUMN'}{$column_name}{'NULL'} =
		  $cols->{'column_null'};
		$structure{$group}{$relname}{'COLUMN'}{$column_name}{'DESCRIPTION'} =
		  $cols->{'column_description'};
		$structure{$group}{$relname}{'COLUMN'}{$column_name}{'DEFAULT'} =
		  $cols->{'column_default'};
	}

	# Pull out both PRIMARY and UNIQUE keys based on the supplied query
	# and the relation OID.
	#
	# Since there may be multiple UNIQUE indexes on a table, we append a
	# number to the end of the the UNIQUE keyword which shows that they
	# are a part of a related definition.  I.e UNIQUE_1 goes with UNIQUE_1
	#
	$sth_Primary_Keys->execute($reloid);
	my $unqgroup = 0;
	while ( my $pricols = $sth_Primary_Keys->fetchrow_hashref ) {
		my $index_type = $pricols->{'constraint_type'};
		my $con		= $pricols->{'constraint_name'};
		my $indexdef   = $pricols->{'constraint_definition'};

		# Fetch the column list
		my $column_list = $indexdef;
		$column_list =~ s/.*\(([^)]+)\).*/$1/g;

		# Split our column list and deal with all PRIMARY KEY fields
		my @collist = split(',', $column_list);

		# Store the column number in the indextype field.  Anything > 0 indicates
		# the column has this type of constraint applied to it.
		my $column;
		my $currentcol = $#collist + 1;
		my $numcols = $#collist + 1;

		# Bump group number if there are two or more columns
		if ($numcols >= 2 && $index_type eq 'UNIQUE') {
			$unqgroup++;
		}

		# Record the data to the structure.
		while ($column = pop(@collist) ) {
			$column =~ s/\s$//;
			$column =~ s/^\s//;

			$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'TYPE'} = $index_type;

			$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'COLNUM'} = $currentcol--;

			# Record group number only when a multi-column constraint is involved
			if ($numcols >= 2 && $index_type eq 'UNIQUE') {
				$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'KEYGROUP'} = $unqgroup;
			}
		}
	}

	# FOREIGN KEYS like UNIQUE indexes can appear several times in a table in multi-column
	# format. We use the same trick to record a numeric association to the foreign key
	# reference.
	#
	$sth_Foreign_Keys->execute($reloid);
	my $fkgroup = 0;
	while (my $forcols = $sth_Foreign_Keys->fetchrow_hashref)
	{
		my $column_oid	  = $forcols->{'oid'};
		my $con = $forcols->{'constraint_name'};

		# Declare variables for dataload
		my @keylist;
		my @fkeylist;
		my $fgroup;
		my $ftable;

		if ($pgversion >= 70300) {
			my $fkey   = $forcols->{'constraint_fkey'};
			my $keys   = $forcols->{'constraint_key'};
			my $frelid = $forcols->{'foreignrelid'};

			# Since decent array support was not added to 7.4, and we want to support
			# 7.3 as well, we parse the text version of the array by hand rather than
			# combining this and Foreign_Key_Arg query into a single query.
			$fkey =~ s/^{//g;
			$fkey =~ s/}$//g;
			$fkey =~ s/"//g;

			$keys =~ s/^{//g;
			$keys =~ s/}$//g;
			$keys =~ s/"//g;

			my @keyset  = split (/,/, $keys);
			my @fkeyset = split (/,/, $fkey);

			# Convert the list of column numbers into column names for the
			# local side.
			foreach my $k (@keyset)
			{
				$sth_Foreign_Key_Arg->execute($reloid, $k);

				my $row = $sth_Foreign_Key_Arg->fetchrow_hashref;

				push(@keylist, $row->{'attribute_name'});
			}

			# Convert the list of columns numbers into column names for the
			# referenced side. Grab the table and namespace while we're here.
			foreach my $k (@fkeyset)
			{
				$sth_Foreign_Key_Arg->execute($frelid, $k);

				my $row = $sth_Foreign_Key_Arg->fetchrow_hashref;

				push(@fkeylist, $row->{'attribute_name'});
				$fgroup = $row->{'namespace'};
				$ftable = $row->{'relation_name'};
			}

			# Deal with common catalog issues.
			die "FKEY $con Broken -- fix your PostgreSQL installation" if $#keylist != $#fkeylist;
		}
		else {
			my $keyname;		# Throw away
			my $table;			# Throw away
			my $unspecified;	# Throw away
			my @columns;

			my $nargs = $forcols->{'number_args'};
			my $args  = $forcols->{'args'};

			# This database doesn't support namespaces, so use the default
			$fgroup = $system_schema;

			($keyname, $table, $ftable, $unspecified, @columns) = split(/\000/, $args);

			# Account for old versions which don't handle NULL but instead return a string
			# of the escape sequence
			if (!defined($ftable)) {
				($keyname, $table, $ftable, $unspecified, @columns) = split (/\\000/, $args);
			}

			# Push the column list stored into @columns into the key and fkey lists
			while (my $column = pop (@columns)
				and my $fcolumn = pop (@columns))
			{
				push(@keylist, $column);
				push(@fkeylist, $fcolumn);
			}
		}

		#
		# Load up the array based on the information discovered using the information
		# retrieval methods above.
		#
		my $numcols = $#keylist + 1;
		my $currentcol = $#keylist + 1;

		# Bump group number if there are two or more columns involved
		if ($numcols >= 2) {
			$fkgroup++;
		}

		# Record the foreign key to structure
		while (my $column = pop(@keylist)
			and my $fkey = pop(@fkeylist))
		{
			$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'TYPE'} = 'FOREIGN KEY';
	
			$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'COLNUM'} = $currentcol--;

			$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'FKTABLE'} = $ftable;
			$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'FKSCHEMA'} = $fgroup;
			$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'FK-COL NAME'} = $fkey;

			# Record group number only when a multi-column constraint is involved
			if ($numcols >= 2) {
				$structure{$group}{$relname}{'COLUMN'}{$column}{'CON'}{$con}{'KEYGROUP'} = $fkgroup;
			}
		}
	}

	# Pull out index information
	$sth_Indexes->execute($group, $relname);
	while (my $idx = $sth_Indexes->fetchrow_hashref)
	{
		$structure{$group}{$relname}{'INDEX'}{$idx->{'indexname'}} = $idx->{'indexdef'};
	}
}

# Function Handling
$sth_Function->execute();
while ( my $functions = $sth_Function->fetchrow_hashref ) {
	my $functionname = $functions->{'function_name'} . '( ';
	my $group		= $functions->{'namespace'};
	my $comment	  = $functions->{'comment'};
	my $functionargs = $functions->{'function_args'};

	my @types = split ( ' ', $functionargs );
	my $count = 0;

	foreach my $type (@types) {
		$sth_FunctionArg->execute($type);

		my $hash = $sth_FunctionArg->fetchrow_hashref;

		if ( $count > 0 ) {
			$functionname .= ', ';
		}

		if ( $hash->{'namespace'} ne $system_schema ) {
			$functionname .= $hash->{'namespace'} . '.';
		}
		$functionname .= $hash->{'type_name'};
		$count++;
	}
	$functionname .= ' )';

	my $ret_type = $functions->{'returns_set'} ? 'SET OF ' : '';
	$sth_FunctionArg->execute($functions->{'return_type'});
	my $rhash = $sth_FunctionArg->fetchrow_hashref;
	$ret_type .= $rhash->{'type_name'};

	$struct{'FUNCTION'}{$group}{$functionname}{'COMMENT'} = $comment;
	$struct{'FUNCTION'}{$group}{$functionname}{'SOURCE'} = $functions->{'source_code'};
	$struct{'FUNCTION'}{$group}{$functionname}{'LANGUAGE'} = $functions->{'language_name'};
	$struct{'FUNCTION'}{$group}{$functionname}{'RETURNS'} = $ret_type;
}

# Deal with the Schema
$sth_Schema->execute();
while ( my $schema = $sth_Schema->fetchrow_hashref ) {
	my $comment   = $schema->{'comment'};
	my $namespace = $schema->{'namespace'};

	$struct{'SCHEMA'}{$namespace}{'COMMENT'} = $comment;
}

# Write out *ALL* templates
&write_using_templates();


#####
# write_using_templates
#	Generate structure that HTML::Template requires out of the
#	$structure for table related information, and $struct for
#	the schema and function information
#
#	TODO: Finish conversion of $structure format into $struct
sub write_using_templates
{
	my @schemas;
	# Start at 0, increment to 1 prior to use.
	my $object_id = 0;
	my %tableids;
	foreach my $schema ( sort keys %structure ) {
		my @tables;
		foreach my $table ( sort keys %{ $structure{$schema} } ) {
			# Column List
			my @columns;
			foreach my $column (
				sort {
					$structure{$schema}{$table}{'COLUMN'}{$a}{'ORDER'} <=>
					$structure{$schema}{$table}{'COLUMN'}{$b}{'ORDER'}
				} keys %{ $structure{$schema}{$table}{'COLUMN'} }
			  )
			{
				my $inferrednotnull = 0;

				# Have a shorter default for places that require it
				my $shortdefault = $structure{$schema}{$table}{'COLUMN'}{$column}{'DEFAULT'};
				$shortdefault =~ s/^(.{17}).{5,}(.{5})$/$1 ... $2/g;

				# Deal with column constraints
				my @colconstraints;
				foreach my $con
					( sort keys %{ $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'} })
				{
					if ($structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'TYPE'} eq 'UNIQUE') {
						my $unq = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'TYPE'};
						my $unqcol = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'COLNUM'};
						my $unqgroup = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'KEYGROUP'};

						push @colconstraints, {
							column_unique => $unq,
							column_unique_colnum => $unqcol,
							column_unique_keygroup => $unqgroup,
						};
					} elsif ($structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'TYPE'} eq 'PRIMARY KEY') {
						$inferrednotnull = 1;
						push @colconstraints, {
							column_primary_key => 'PRIMARY KEY',
						};
					} elsif ($structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'TYPE'} eq 'FOREIGN KEY') {
						my $fksgmlid = sgml_safe_id(
							join('.'
								, $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FKSCHEMA'}
								, $structure{$schema}{$table}{'TYPE'} 
							   	, $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FKTABLE'}));

						my $fkgroup = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'KEYGROUP'};
						my $fktable = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FKTABLE'};
						my $fkcol = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FK-COL NAME'};
						my $fkschema = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FKSCHEMA'};

						push @colconstraints, {
							column_fk => 'FOREIGN KEY',
							column_fk_colnum => $fkcol,
							column_fk_keygroup => $fkgroup,
							column_fk_schema => $fkschema,
							column_fk_schema_dbk => docbook($fkschema),
							column_fk_schema_dot => graphviz($fkschema),
							column_fk_sgmlid => $fksgmlid,
							column_fk_table => $fktable,
							column_fk_table_dbk => docbook($fktable),
						};

						# only have the count if there is more than 1 schema
						if (scalar(keys %structure) > 1) {
							$colconstraints[-1]{"number_of_schemas"} = scalar(keys %structure);
						}
					}
				}


				# Generate the Column array
				push @columns, {
					column => $column,
					column_dbk => docbook($column),
					column_dot => graphviz($column),
					column_default => $structure{$schema}{$table}{'COLUMN'}{$column}{'DEFAULT'},
					column_default_dbk => docbook($structure{$schema}{$table}{'COLUMN'}{$column}{'DEFAULT'}),
					column_default_short => $shortdefault,
					column_default_short_dbk => docbook($shortdefault),

					column_comment => $structure{$schema}{$table}{'COLUMN'}{$column}{'DESCRIPTION'},
					column_comment_dbk => docbook($structure{$schema}{$table}{'COLUMN'}{$column}{'DESCRIPTION'}),

					column_number => $structure{$schema}{$table}{'COLUMN'}{$column}{'ORDER'},

					column_type => $structure{$schema}{$table}{'COLUMN'}{$column}{'TYPE'},
					column_type_dbk => docbook($structure{$schema}{$table}{'COLUMN'}{$column}{'TYPE'}),

					column_constraints => \@colconstraints,
				};

				if ($inferrednotnull == 0) {
					$columns[-1]{"column_constraint_notnull"} =
						$structure{$schema}{$table}{'COLUMN'}{$column}{'NULL'};
				}
			}

			# Constraint List
			my @constraints;
			foreach my $constraint (sort keys %{$structure{$schema}{$table}{'CONSTRAINT'}}) {
				my $shortcon = $structure{$schema}{$table}{'CONSTRAINT'}{$constraint};
				$shortcon =~ s/^(.{30}).{5,}(.{5})$/$1 ... $2/g;
				push @constraints, {
					constraint => $structure{$schema}{$table}{'CONSTRAINT'}{$constraint},
					constraint_dbk => docbook($structure{$schema}{$table}{'CONSTRAINT'}{$constraint}),
					constraint_name => $constraint,
					constraint_name_dbk => docbook($constraint),
					constraint_short => $shortcon,
					constraint_short_dbk => docbook($shortcon),
					table => $table,
					table_dbk => docbook($table),
					table_dot => graphviz($table),
				};
			}

			# Index List
			my @indexes;
			foreach my $index (sort keys %{$structure{$schema}{$table}{'INDEX'}}) { 
				push @indexes, {
					index_definition => $structure{$schema}{$table}{'INDEX'}{$index},
					index_definition_dbk => docbook($structure{$schema}{$table}{'INDEX'}{$index}),
					index_name => $index,
					index_name_dbk => docbook($index),
					table => $table,
					table_dbk => docbook($table),
					table_dot => graphviz($table),
					schema => $schema,
					schema_dbk => docbook($schema),
					schema_dot => graphviz($schema),
				};
			}

			# Foreign Key Discovery
			#
			# $lastmatch is used to ensure that we only supply a result a single time and not once
			# for each link found.  Since the loops are sorted, we only need to track the last
			# element, and not all supplied elements.
			my @fk_schemas;
			my $lastmatch = '';
			foreach my $fk_schema ( sort keys %structure ) {
				foreach my $fk_table ( sort keys %{ $structure{$fk_schema} } ) {
					foreach my $fk_column (
						sort keys %{ $structure{$fk_schema}{$fk_table}{'COLUMN'} } )
					{
						foreach my $con (
							sort keys %{$structure{$fk_schema}{$fk_table}{'COLUMN'}{$fk_column}{'CON'}}
						) {
							if (
								$structure{$fk_schema}{$fk_table}{'COLUMN'}{$fk_column}{'CON'}{$con}{'TYPE'} eq 'FOREIGN KEY'
								&& $structure{$fk_schema}{$fk_table}{'COLUMN'}{$fk_column}{'CON'}{$con}{'FKTABLE'} eq $table
								&& $structure{$fk_schema}{$fk_table}{'COLUMN'}{$fk_column}{'CON'}{$con}{'FKSCHEMA'} eq $schema
								&& $lastmatch ne "$fk_schema$fk_table"
								)
							{
								my $fksgmlid = sgml_safe_id(
													join('.',$fk_schema
															, $structure{$fk_schema}{$fk_table}{'TYPE'}
															, $fk_table));
								push @fk_schemas, {
									fk_column_number => $structure{$fk_schema}{$fk_table}{'COLUMN'}{$fk_column}{'ORDER'},
									fk_sgmlid => $fksgmlid,
									fk_schema => $fk_schema,
									fk_schema_dbk => docbook($fk_schema),
									fk_schema_dot => graphviz($fk_schema),
									fk_table => $fk_table,
									fk_table_dbk => docbook($fk_table),
									fk_table_dot => graphviz($fk_table),
								};

								# only have the count if there is more than 1 schema
								if (scalar(keys %structure) > 1) {
									$fk_schemas[-1]{"number_of_schemas"} = scalar(keys %structure);
								}

								$lastmatch = "$fk_schema$fk_table";
							}
						}
					}
				}
			}

			# List off permissions
			my @permissions;
			foreach my $user ( sort keys %{ $structure{$schema}{$table}{'ACL'} } ) {
				push @permissions, {
					schema => $schema,
					schema_dbk => docbook($schema),
					schema_dot => graphviz($schema),
					table => $table,
					table_dbk => docbook($table),
					table_dot => graphviz($table),
					user => $user,
					user_dbk => docbook($user),
				};

				# only have the count if there is more than 1 schema
				if (scalar(keys %structure) > 1) {
					$permissions[-1]{"number_of_schemas"} = scalar(keys %structure);
				}

				foreach my $perm ( keys %{ $structure{$schema}{$table}{'ACL'}{$user} } ) {
					if ( $structure{$schema}{$table}{'ACL'}{$user}{$perm} == 1 ) {
						$permissions[-1]{lower($perm)} = 1; 
					}
				}

			}

			# Increment and record the object ID
			$tableids{"$schema$table"} = ++$object_id;
			my $viewdef = sql_prettyprint($structure{$schema}{$table}{'VIEW_DEF'});

			# Truncate comment for Dia
                        my $comment_dia = $structure{$schema}{$table}{'DESCRIPTION'};
			$comment_dia =~ s/^(.{35}).{5,}(.{5})$/$1 ... $2/g;

			push @tables, {
				object_id => $object_id,
				object_id_dbk => docbook($object_id),

				schema => $schema,
				schema_dbk => docbook($schema),
				schema_dot => graphviz($schema),
				schema_sgmlid => sgml_safe_id($schema.".schema"),

				# Statistics
				stats_enabled => $statistics,
				stats_dead_bytes => useUnits($structure{$schema}{$table}{'DEADTUPLELEN'}),
				stats_dead_bytes_dbk => docbook(useUnits($structure{$schema}{$table}{'DEADTUPLELEN'})),
				stats_free_bytes => useUnits($structure{$schema}{$table}{'FREELEN'}),
				stats_free_bytes_dbk => docbook(useUnits($structure{$schema}{$table}{'FREELEN'})),
				stats_table_bytes => useUnits($structure{$schema}{$table}{'TABLELEN'}),
				stats_table_bytes_dbk => docbook(useUnits($structure{$schema}{$table}{'TABLELEN'})),
				stats_tuple_count => $structure{$schema}{$table}{'TUPLECOUNT'},
				stats_tuple_count_dbk => docbook($structure{$schema}{$table}{'TUPLECOUNT'}),
				stats_tuple_bytes => useUnits($structure{$schema}{$table}{'TUPLELEN'}),
				stats_tuple_bytes_dbk => docbook(useUnits($structure{$schema}{$table}{'TUPLELEN'})),

			  	table => $table,
			  	table_dbk => docbook($table),
			  	table_dot => graphviz($table),
				table_sgmlid => sgml_safe_id(join('.', $schema, $structure{$schema}{$table}{'TYPE'}, $table)),
				table_comment => $structure{$schema}{$table}{'DESCRIPTION'},
				table_comment_dbk => docbook($structure{$schema}{$table}{'DESCRIPTION'}),
                                table_comment_dia => $comment_dia,
				view_definition => $viewdef,
				view_definition_dbk => docbook($viewdef),
				columns => \@columns,
				constraints => \@constraints,
				fk_schemas => \@fk_schemas,
				indexes => \@indexes,
				permissions => \@permissions,
			};

			# only have the count if there is more than 1 schema
			if (scalar(keys %structure) > 1) {
				$tables[-1]{"number_of_schemas"} = scalar(keys %structure);
			}
		}

		# Dump out list of functions
		my @functions;
		foreach my $function ( sort keys %{ $struct{'FUNCTION'}{$schema} } ) {
			push @functions, {
				function => $function,
				function_dbk => docbook($function),
				function_sgmlid => sgml_safe_id(join('.', $schema, 'function', $function)),
				function_comment => $struct{'FUNCTION'}{$schema}{$function}{'COMMENT'},
				function_comment_dbk => docbook($struct{'FUNCTION'}{$schema}{$function}{'COMMENT'}),
				function_language => uc($struct{'FUNCTION'}{$schema}{$function}{'LANGUAGE'}),
				function_returns => $struct{'FUNCTION'}{$schema}{$function}{'RETURNS'},
				function_source => $struct{'FUNCTION'}{$schema}{$function}{'SOURCE'},
				schema => $schema,
				schema_dbk => docbook($schema),
				schema_dot => graphviz($schema),
				schema_sgmlid => sgml_safe_id($schema.".schema"),
			};

			# only have the count if there is more than 1 schema
			if (scalar(keys %structure) > 1) {
				$functions[-1]{"number_of_schemas"} = scalar(keys %structure);
			}
		}

		push @schemas, {
			schema => $schema,
			schema_dbk => docbook($schema),
			schema_dot => graphviz($schema),
			schema_sgmlid => sgml_safe_id($schema.".schema"),
			schema_comment => $struct{'SCHEMA'}{$schema}{'COMMENT'},
			schema_comment_dbk => docbook($struct{'SCHEMA'}{$schema}{'COMMENT'}),
			functions => \@functions,
			tables => \@tables,
		};

		# Build the array of schemas
		if (scalar(keys %structure) > 1) {
			$schemas[-1]{"number_of_schemas"} = scalar(keys %structure);
		}
	}

	# Link the various components together via the template.
	my @fk_links;
	my @fkeys;
	foreach my $schema ( sort keys %structure ) {
		foreach my $table ( sort keys %{ $structure{$schema} } ) {
			foreach my $column (
				sort {
					$structure{$schema}{$table}{'COLUMN'}{$a}{'ORDER'} <=>
					$structure{$schema}{$table}{'COLUMN'}{$b}{'ORDER'}
				}
				keys %{ $structure{$schema}{$table}{'COLUMN'} }
			) {
				foreach my $con (
					sort keys %{$structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}}
				) {
					# To prevent a multi-column foreign key from appearing several times, we've opted
					# to simply display the first column of any given key.  Since column numbering
					# always starts at 1 for foreign keys.
					if ( $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'TYPE'}
							eq 'FOREIGN KEY' 
						&& $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'COLNUM'}
							== 1 )
					{
						# Pull out some of the longer keys
						my $ref_table = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FKTABLE'};
						my $ref_schema = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FKSCHEMA'};
						my $ref_column = $structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'FK-COL NAME'};

						# Default values cause these elements to attach to the bottom in Dia
						#
						# If a KEYGROUP is not defined, it's a single column.  Modify the ref_con
						# and key_con variables to attach the to the columns connection point
						# directly.
						my $ref_con = 0;
						my $key_con = 0;
						my $keycon_offset = 0;
						if (!defined($structure{$schema}{$table}{'COLUMN'}{$column}{'CON'}{$con}{'KEYGROUP'})) {
							$ref_con = $structure{$ref_schema}{$ref_table}{'COLUMN'}{$ref_column}{'ORDER'};
							$key_con = $structure{$schema}{$table}{'COLUMN'}{$column}{'ORDER'};
							$keycon_offset = 1;
						}
					
						# Bump object_id
						$object_id++;

						push @fk_links, {
							fk_link_name => $con,
							fk_link_name_dbk => docbook($con),
							fk_link_name_dot => graphviz($con),
							handle0_connection => $key_con,
							handle0_connection_dbk => docbook($key_con),
							handle0_connection_dia => 6 + ($key_con * 2),
							handle0_name => $table,
							handle0_name_dbk => docbook($table),
							handle0_schema => $schema,
							handle0_to => $tableids{"$schema$table"},
							handle0_to_dbk => docbook($tableids{"$schema$table"}),
							handle1_connection => $ref_con,
							handle1_connection_dbk => docbook($ref_con),
							handle1_connection_dia => 6 + ($ref_con * 2) + $keycon_offset,
							handle1_name => $ref_table,
							handle1_name_dbk => docbook($ref_table),
							handle1_schema => $ref_schema,
							handle1_to => $tableids{"$ref_schema$ref_table"},
							handle1_to_dbk => docbook($tableids{"$ref_schema$ref_table"}),
							object_id => $object_id,
							object_id_dbk => docbook($object_id),
						};

						# Build the array of schemas
						if (scalar(keys %structure) > 1) {
							$fk_links[-1]{"number_of_schemas"} = scalar(keys %structure);
						}
					}
				}
			}
		}
	}

### FOR DEBUGGING ###
# print Data::Dumper->Dump(\@schemas);

	# Make database level comment information
	my @timestamp = localtime();
	my $dumped_on = sprintf("%04d-%02d-%02d", $timestamp[5]+1900, $timestamp[4]+1, $timestamp[3]);
	my $database_comment = $struct{'DATABASE'}{$database}{'COMMENT'};

	# Loop through each template found in the supplied path. Output the results of the template
	# as <filename>.<extension> into the current working directory.
	my @template_files = glob($template_path .'/*.tmpl');

	# Ensure we've told the user if we don't find any files.
	triggerError("Templates files not found in $template_path")
		if ($#template_files < 0);

	# Process all found templates.
	foreach my $template_file (@template_files) {
		(my $file_extension = $template_file) =~ s/^(?:.*\/|)([^\/]+)\.tmpl$/$1/;
		next if (defined($wanted_output) && $file_extension ne $wanted_output);
		my $output_filename = "$output_filename_base.$file_extension";
		print "Producing $output_filename from $template_file\n";

		my $template = HTML::Template->new(
			filename => $template_file,
			die_on_bad_params => 0,
			global_vars => 0,
			strict => 1,
			loop_context_vars => 1
		);

		$template->param(
			database => $database,
			database_dbk => docbook($database),
			database_sgmlid => sgml_safe_id($database),
			database_comment => $database_comment,
			database_comment_dbk => docbook($database_comment),
			dumped_on => $dumped_on,
			dumped_on_dbk => docbook($dumped_on),
			fk_links => \@fk_links,
			schemas => \@schemas,
		);

		sysopen( FH, $output_filename, O_WRONLY | O_TRUNC | O_CREAT, 0644 )
		  or die "Can't open $output_filename: $!";
		print FH $template->output();
	}
}


######
# sgml_safe_id
#   Safe SGML ID Character replacement
sub sgml_safe_id($) {
	my $string = shift;

	# Lets use the keyword ARRAY in place of the square brackets
	# to prevent duplicating a non-array equivelent
	$string =~ s/\[\]/ARRAY-/g;

	# Brackets, spaces, commads, underscores are not valid 'id' characters
	# replace with as few -'s as possible.
	$string =~ s/[ "',)(_-]+/-/g;

	# Don't want a - at the end either.  It looks silly.
	$string =~ s/-$//g;

	return ($string);
}

#####
# lower
#	LowerCase the string
sub lower($) {
	my $string = shift;

	$string =~ tr/A-Z/a-z/;

	return ($string);
}

#####
# useUnits
#	Tack on base 2 metric units
sub useUnits($) {
	my $value = shift;

	my @units = ('Bytes', 'KiBytes', 'MiBytes', 'GiBytes', 'TiBytes');
	my $loop = 0;

	while ($value >= 1024)
	{
		$loop++;

		$value = $value / 1024;
	}

	return(sprintf("%.2f %s", $value, $units[$loop]));
}

#####
# docbook
#	Docbook output is special in that we may or may not want to escape
#	the characters inside the string depending on a string prefix.
sub docbook($) {
	my $string = shift;

	if ( defined($string) ) {
		if ( $string =~ /^\@DOCBOOK/ ) {
			$string =~ s/^\@DOCBOOK//;
		}
		else {
			$string =~ s/&(?!(amp|lt|gr|apos|quot);)/&amp;/g;
			$string =~ s/</&lt;/g;
			$string =~ s/>/&gt;/g;
			$string =~ s/'/&apos;/g;
			$string =~ s/"/&quot;/g;
		}
	}
	else {
		# Return an empty string when all else fails
		$string = '';
	}

	return ($string);
}

#####
# graphviz
#	GraphViz output requires that special characters (like " and whitespace) must be preceeded
#	by a \ when a part of a lable.
sub graphviz($) {
	my $string = shift;

	# Ensure we don't return an least a empty string
	$string = '' if (!defined($string));

	$string =~ s/([\s"'])/\\$1/g;

	return ($string);
}


#####
# sql_prettyprint
#	Clean up SQL into something presentable
sub sql_prettyprint($)
{
	my $string = shift;

	# If nothing has been sent in, return an empty string
	if (!defined($string))
	{
		return '';
	}

	# Initialize Result string
	my $result = '';

	# List of tokens to split on 
	my $tok = "SELECT|FROM|WHERE|HAVING|GROUP BY|ORDER BY|OR|AND|LEFT JOIN|RIGHT JOIN".
				"|LEFT OUTER JOIN|LEFT INNER JOIN|INNER JOIN|RIGHT OUTER JOIN|RIGHT INNER JOIN".
				"|JOIN|UNION ALL|UNION|EXCEPT|USING|ON|CAST|[\(\),]";

	my $key = 0;
	my $bracket = 0;
	my $depth = 0;
	my $indent = 6;

	# XXX: Split is wrong -- match would do
	foreach my $elem (split(/(\"[^\"]*\"|'[^']*'|$tok)/, $string))
	{
		my $format;

		# Skip junk tokens
		if ($elem =~ /^[\s]?$/)
		{
			next;
		}

		# NOTE: Should we drop leading spaces?
		#	$elem =~ s/^\s//;

		# Close brackets are special
		# Bring depth in a level
		if ($elem =~ /\)/)
		{
			$depth = $depth - $indent;
			if ($key == 1 or $bracket == 1)
			{
				$format = "%s%s";
			} else
			{
				$format = "%s\n%". $depth ."s";
			}

			$key = 0;
			$bracket = 0;
		}
		# Open brackets are special
		# Bump depth out a level
		elsif ($elem =~ /\(/)
		{
			if ($key == 1)
			{
				$format = "%s %s";
			} else
			{
				$format = "%s\n%". $depth ."s";
			}
			$depth = $depth + $indent;
			$bracket = 1;
			$key = 0;
		}
		# Key element
		# Token from our list -- format on left hand side of the equation
		# when appropriate.
		elsif ($elem =~ /$tok/)
		{
			if ($key == 1)
			{
				$format = "%s%s";
			} else
			{
				$format = "%s\n%". $depth ."s";
			}

			$key = 1;
			$bracket = 0;
		}
		# Value
		# Format for right hand side of the equation
		else {
			$format = "%s%s";		

			$key = 0;
		}

		# Add the new format string to the result
		$result = sprintf($format, $result, $elem);
	}

	return $result;
}

##
# triggerError
#	Print out a supplied error message and exit the script.
sub triggerError($)
{
	my $error = shift;

	# Test error
	if (!defined($error) || $error eq '')
	{
		triggerError("triggerError: Unknown error");
	}
	printf("\n\n%s\n", $error);

	exit 2;
}

#####
# usage
#   Usage
sub usage() {
	print <<USAGE
Usage:
  $basename [options] [dbname [username]]

Options:
  -d <dbname>     Specify database name to connect to (default: $database)
  -f <file>       Specify output file prefix (default: $database)
  -h <host>       Specify database server host (default: localhost)
  -p <port>       Specify database server port (default: 5432)
  -u <username>   Specify database username (default: $dbuser)
  --password=<pw> Specify database password (default: blank)

  -l <path>       Path to the templates (default: @@TEMPLATE-DIR@@)
  -t <output>     Type of output wanted (default: All in template library)

  -s <schema>	  Specify a specific schema to match. Technically this is a regular
                  expression but anything other than a specific name may have unusual
                  results.

  --statistics    In 7.4 and later, with the contrib module pgstattuple installed we
                  can gather statistics on the tables in the database 
                  (average size, free space, disk space used, dead tuple counts, etc.)
                  This is disk intensive on large databases as all pages must be visited.
USAGE
	;
	exit 1;
}
