use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'Net::Streamload',
    'VERSION_FROM' => 'Streamload.pm', # finds $VERSION
    'PREREQ_PM'	   => { Digest::MD5 => 2.12 }, # e.g., Module::Name => 1.1
    'dist'         => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    'AUTHOR'       => 'Tobias Gruetzmacher <tobias@portfolio16.de>',
    'EXE_FILES'    => ['slup']
);
