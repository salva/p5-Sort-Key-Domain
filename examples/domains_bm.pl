#!/usr/bin/perl

# See LinkeIn discussion:
# https://www.linkedin.com/groupItem?view=&gid=106254&type=member&item=5881611740927528962&trk=my_groups-b-title

use strict;
use warnings;
use Benchmark 'cmpthese';
use Sort::Key qw(keysort);
use Sort::Key::Domain qw(domainsort mkkey_domain);
use HTTP::Tiny;
use POSIX;
use Socket;
use Getopt::Std;
use 5.014;


our ($opt_n, $opt_r, $opt_p, $opt_m, $opt_d);
getopts('n:p:m:rd');
$opt_m //= 2048;
$opt_n //= 100_000;
$opt_p //= 2;
$opt_r;

sub generate_weights {
    my $opt_n = shift;
    my $w = 0;
    my @w;
    for (1..$opt_n) {
        $w += (rand(1) ** 3);
        push @w, $w;
    }
    return @w;
}

sub weighted_rand {
    my $w = shift;
    my $r = rand($w->[-1]);
    my $i = 0;
    my $j = $#$w;
    while ($i < $j) {
        my $pivot = (($i + $j) >> 1);
        if ($w->[$pivot] > $r) {
            $j = $pivot;
        }
        else {
            $i = $pivot + 1;
        }
    }
    return $j;
}

sub gen_lowercase_str {
    my @chars = ( "a" .. "z" );
    return join '', @chars[map { int rand @chars } 1 .. ( int rand (15) + 3 )];
}

sub gen_domain {
    my @foo;
    for ( 1 .. ( int rand (9) + 3 )) {
        push @foo, gen_lowercase_str();
    }
    return join '.', @foo;
}

$| = 1;
my @domain;

if ($opt_r) {
    print "generating data...\n";
    @domain = map gen_domain(), 1..$opt_n;
}
else {
    print "retrieving top level domains...\n";

    my $res = HTTP::Tiny->new->get('http://data.iana.org/TLD/tlds-alpha-by-domain.txt');
    $res->{success} or die "unable to retrieve list of top level domains";

    my @top = map lc, grep /^\w+$/, split /\n+/, $res->{content};
    my @top_w = generate_weights scalar @top;

    open my $words, '<', '/usr/share/dict/words' or die "unable to open words file: $!";
    my @words = grep /^[a-z]{3,}$/, <$words>;
    chomp @words;
    my @words_w = generate_weights scalar @words;

    print "generating data...\n";
    for (1..$opt_n) {
        my $top = $top[weighted_rand \@top_w];
        push @domain, join '.', @words[map weighted_rand(\@words_w), 0..1 + rand 3], $top;
    }
}

sub dump_array {
    my ($fn, $array) = @_;
    $fn .= '.dump';
    open my $fh, '>', $fn or die $!;
    say $fh $_ for @$array;
    close $fh or die $!;
}

sub open2 {
    pipe my ($cr, $pw) or die $!;
    pipe my ($pr, $cw) or die $!;
    my $pid = fork;
    unless ($pid) {
        defined $pid or die $!;
        eval {
            close $pr or die $!;
            close $pw or die $!;
            POSIX::dup2(fileno($cr), 0) or die $!;
            POSIX::dup2(fileno($cw), 1) or die $!;
            exec @_ or die $!;
        };
        print STDERR $@;
        POSIX::_exit(1);
    }
    close $cr or die;
    close $cw or die;
    return ($pr, $pw, $pid);
}

my %subs =
    ( grt => sub {
          my @sorted = map { join '.', reverse split /\./ }
              sort
                  map { join '.', reverse split /\./ } @domain;
          $opt_d and dump_array(grt => \@sorted);
      },
      js  => sub {
          my @sorted  = map { (split /:/)[1] }
              sort
                  map { join( '.', reverse split /\./ ) . ":$_" } @domain;
          $opt_d and dump_array(js => \@sorted);
      },
      sk  => sub {
          my @sorted = keysort { join '.', reverse split /\./ } @domain;
          $opt_d and dump_array(sk => \@sorted);
      },
      skd => sub {
          my @sorted = domainsort @domain;
          $opt_d and dump_array(skd => \@sorted);
      } );

for my $cpus (1, 2, 4, 8, 16, 32, 64) {
    last if $cpus > $opt_p;

    $subs{"ext_$cpus"} = sub {
        local $ENV{LANG} = 'C'; # sort in ASCII order
        my ($r, $w, $pid) = open2( 'sort',
                                   "--buffer-size=${opt_m}M",
                                   "--parallel=${cpus}",
                                 ) or die $!;
        say $w join '.', reverse split /\./ for @domain;
        close $w or die $!;
        my @sorted;
        $#sorted = @domain; # preallocate memory
        $#sorted = -1;
        while (<$r>) {
            chomp;
            push @sorted, join '.', reverse split /\./;
        }
        close $r or die $!;
        waitpid $pid, 0;
        $opt_d and dump_array(ext => \@sorted);
    };

    $subs{"ext_skd_$cpus"} = sub {
        local $ENV{LANG} = 'C'; # sort in ASCII order
        my ($r, $w, $pid) = open2( 'sort',
                                   "--buffer-size=${opt_m}M",
                                   "--parallel=${cpus}",
                                 ) or die $!;
        say $w mkkey_domain($_) for @domain;
        close $w or die $!;
        my @sorted;
        $#sorted = @domain; # preallocate memory
        $#sorted = -1;
        while (<$r>) {
            chomp;
            push @sorted, mkkey_domain($_);
        }
        close $r or die $!;
        waitpid $pid, 0;
        $opt_d and dump_array(ext => \@sorted);
    };

    $subs{"as_$cpus"} = sub {
        local $ENV{LANG} = 'C';
        my ($r, $w, $pid) = open2('sort',
                                  "--buffer-size=${opt_m}M",
                                  "--parallel=${cpus}",
                                  '-t', '.',
                                  map { -k => "$_,$_" } reverse 1..16 # -k 16,16 -k 15,15...
                                 ) or die $!;
        say $w '.' x (15 - (tr /.//)), $_ for @domain;
        close $w or die $!;
        my @sorted;
        $#sorted = @domain; # preallocate memory
        $#sorted = -1;
        while (<$r>) {
            chomp;
            s/^\.+//;
            push @sorted, $_;
        }
        close $r or die $!;
        waitpid $pid, 0;
        $opt_d and dump_array(as => \@sorted);
    };
}

print "benchmarking...\n";
cmpthese (10, \%subs);

__END__

=head1 NAME

domains_bm.pl

=head1 SYNOPSIS

domains_bm.pl [-n size] [-p max_workers] [-m max_memory] [-r] [-d]

=over 4

=item -n size

Data set size

=item -p max_workers

Call C<sort> with option C<--parallel=${max_workers}>.

=item -m max_memory

Call C<sort> with option C<--buffer-size=${max_memory}M>.

=item -r

Use Scott Deindorfer code to generate random data.

=item -d

Dump sorted data for testing.

=back

=cut
