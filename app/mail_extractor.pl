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

validate_config(\%config);

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
        if ($string =~ /\G(\S+)[ \t]*=[ \t]*\((.*?)\)\n/cgs) {
            my ($key, $value) = ($1, $2);
            unless ($value =~ /^[ \t]*\n(?:[ \t]*(?:['"].*?['"]|\S+)[ \t]*\n)*[ \t]*$/) {
                die "$0: configuration key: $key (not multi-line)\n";
            }
            my @values = map { s/^[ \t]+//; s/[ \t]+$//; $extract_value->($key, $_) } grep /[^ \t]/, split /\n/, $value;
            $config{$key} = [ @values ];
        } # single
        elsif ($string =~ /\G(\S+)[ \t]*=[ \t]*([^()]*?)\n/cg) {
            my ($key, $value) = ($1, $2);
            if ($value =~ $re_quoted_value) {
                die "$0: configuration key: $key (unbalanced quotes)\n" if $1 ne $3;
                $config{$key} = $2;
            }
            else {
                die "$0: configuration key: $key (bad value)\n";
            }
        } # comment
        elsif ($string =~ /\G[ \t]*\#.*?\n/cg) {
            next;
        } # blank
        elsif ($string =~ /\G[ \t]*\n/cg) {
            next;
        } # invalid
        else {
            die "$0: configuration line: '$1' (cannot be parsed)\n" if $string =~ /\G(.+)\n/g;
        }
    }

    return %config;
}

sub validate_config
{
    my ($config) = @_;

    my @keys = qw(source_path output_path log_file excludes);

    my %types = (
        source_path => '',
        output_path => '',
        log_file    => '',
        excludes    => 'ARRAY',
    );
    foreach my $key (@keys) {
        die "$0: configuration key: $key (key not exists)\n"
          unless exists $config->{$key};

        die "$0: configuration key: $key (wrong value type)\n"
          unless ref $config->{$key} eq $types{$key};

        next if $types{$key} ne '';
        die "$0: configuration key: $key (is empty string)\n"
          unless length $config->{$key};
    }

    foreach my $key (qw(source_path output_path)) {
        die "$0: configuration key: $key (not a directory)\n"
          unless -e $config->{$key} && -d $config->{$key};
    }
    my $key = 'log_file';
    if (-e $config->{$key}) {
        die "$0: configuration key: $key (not a file)\n"
          unless -f $config->{$key};
    }
}
