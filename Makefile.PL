use ExtUtils::MakeMaker;
# $Id: Makefile.PL,v 1.5 2004/02/22 14:27:38 tobias Exp $
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	'NAME'			=> 'Net::Streamload',
	'VERSION_FROM'	=> 'lib/Net/Streamload.pm', # finds $VERSION
	'PREREQ_PM'		=> { Digest::MD5 => 2.10 }, # e.g., Module::Name => 1.1
	'dist'			=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	'AUTHOR'		=> 'Tobias Gruetzmacher <streamload-support@portfolio16.de>',
	'EXE_FILES'		=> ['bin/slup', 'bin/StreamMgr']
);

# vim: set ts=4 sw=4:
