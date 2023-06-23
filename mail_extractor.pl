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
GetOptions(\%opts, qw(c|config=s h|help V|version)) or usage(1);
usage(0) if $opts{h};

print "$0 v$VERSION\n" and exit 0 if $opts{V};

die "$0: -c/--config not specified or invalid\n" unless defined $opts{c} && $opts{c} =~ /\S+/;

my $Config_file = $opts{c};

die "$0: configuration file `$Config_file' does not exist\n"  unless -e $Config_file;
die "$0: configuration file `$Config_file' is not readable\n" unless -r $Config_file;

my %config = parse_config($Config_file);

sub usage
{
    my ($exit_code) = @_;

    print <<"USAGE";
Usage: $0 [switches]
    -c, --config=<path>    path to config file
    -h, --help             this help screen
    -V, --version          print version
USAGE
    exit $exit_code;
}

sub parse_config
{
    my ($config_file) = @_;

    open(my $fh, '<', $config_file) or die "$0: configuration file `$config_file' cannot be opened: $!\n";
    my $string = do { local $/; <$fh> };
    close($fh);

    my %config;

    my $re_quoted_value = qr/^(['"])(.*?)(['"])$/;

    my $extract_value = sub
    {
        my ($key, $value) = @_;

        if ($value =~ $re_quoted_value) {
            die "$0: configuration key: $key (unbalanced quotes)\n" if $1 ne $3;
            return $2;
        }
        else {
            die "$0: configuration key: $key (bad value)\n";
        }
    };

    while ($string !~ /\G\Z/cg) {
        # multiple
        if ($string =~ /\G(\S+)\s*=\s*\((.*?)\)\n/cgs) {
            my ($key, $value) = ($1, $2);
            unless ($value =~ /^\s*\n(?:\s*(?:['"].*?['"]|\S+)\s*\n)*\s*$/) {
                die "$0: configuration key: $key (not multi-line)\n";
            }
            my @values = map { s/^\s+//; s/\s+$//; $extract_value->($key, $_) } grep /\S/, split /\n/, $value;
            $config{$key} = [ @values ];
        } # single
        elsif ($string =~ /\G(\S+)\s*=\s*(.*?)\n/cg) {
            my ($key, $value) = ($1, $2);
            if ($value =~ $re_quoted_value) {
                die "$0: configuration key: $key (unbalanced quotes)\n" if $1 ne $3;
                $config{$key} = $2;
            }
            else {
                die "$0: configuration key: $key (bad value)\n";
            }
        } # comment
        elsif ($string =~ /\G\s*\#.*?\n/cg) {
            next;
        } # blank
        elsif ($string =~ /\G\s*\n/cg) {
            next;
        } # invalid
        else {
            die "$0: configuration line: '$1' (cannot be parsed)\n" if $string =~ /\G(.+)\n/g;
        }
    }

    return %config;
}
