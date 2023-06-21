#!/usr/bin/perl
#===================================
# Extrahiere Mail-Inhalt von Quellen
#===================================
# Benutzung:
# °°°°°°°°°°
# Das Script muss über die Konsole via installiertem
# Perl-Interpreter aufgerufen werden. Mögliche Aufrufoptionen
# sind über die Hilfe Ausgabe (perl .\mail_extractor.pl --help)
# oder Dokumentation einsehbar.
# -------------------------------------------------------------
# Version: v0.00 - 2023-06-21 / sts
# ---------------------------------

use strict;
use warnings;

use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);

my $VERSION = '0.00';

my %opts;
GetOptions(\%opts, qw(h|help V|version)) or usage(1);
usage(0) if $opts{h};

print "$0 v$VERSION\n" and exit 0 if $opts{V};

sub usage
{
    my ($exit_code) = @_;

    print <<"USAGE";
Usage: $0 [switches]
    -h, --help       this help screen
    -V, --version    print version
USAGE
    exit $exit_code;
}
