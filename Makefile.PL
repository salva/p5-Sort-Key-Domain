use ExtUtils::MakeMaker;

use 5.008;

WriteMakefile( NAME           => 'Sort::Key::Domain',
               VERSION_FROM   => 'lib/Sort/Key/Domain.pm',
               PREREQ_PM      => { 'Sort::Key' => '0' },
               ABSTRACT_FROM  => 'lib/Sort/Key/Domain.pm',
               AUTHOR         => 'Salvador Fandiño <sfandino@yahoo.com>',
               INC            => '-I.',
               META_MERGE => {
                   resources => {
                       repository => 'https://github.com/salva/p5-Sort-Key-Domain',
                   },
               });
