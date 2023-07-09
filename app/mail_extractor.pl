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
use constant true  => 1;
use constant false => 0;

use Email::Address;
use Encode;
use File::Find;
use File::Spec;
use File::Type;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use JSON;
use Net::IDN::Encode qw(email_to_unicode);

my $VERSION = '0.00';

my $CSV_file = 'addresses.csv';

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

my @addresses;
gather_files($config{source_path}, \@addresses);

filter_sort(\@addresses, $config{filter});

save_csv(File::Spec->catfile($config{output_path}, $CSV_file), \@addresses);

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

    my @keys = qw(source_path output_path log_file excludes filter);

    my %types = (
        source_path => '',
        output_path => '',
        log_file    => '',
        excludes    => 'ARRAY',
        filter      => 'ARRAY',
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

sub gather_files
{
    my ($source_path, $addresses) = @_;

    my $ft = File::Type->new;

    my $dir_matches = sub
    {
        my ($path, $regex) = @_;

        my @dirs = File::Spec->splitdir($path);

        return false unless @dirs >= 2;

        for (my $i = 0; $i <= $#dirs - 1; $i++) {
            return true if $dirs[$i]     =~ /^\S+\@\S+$/
                        && $dirs[$i + 1] =~ /^$regex$/;
        }
        return false;
    };

    find({
        wanted => sub {
            # file?
            if (-f $_) { # plain
                if ($dir_matches->($File::Find::dir, qr/(?:Archive-)?Mail/)) {
                    parse_plain($File::Find::name, $addresses) if $ft->mime_type($File::Find::name) eq 'message/rfc822';
                } # json
                elsif ($dir_matches->($File::Find::dir, qr/Contact/)) {
                    parse_json($File::Find::name, $addresses); # all files JSON!
                } # pdf
                elsif ($dir_matches->($File::Find::dir, qr/OneDrive/)) {
                    parse_pdf($File::Find::name, $addresses) if /(?!^)\.(.+)$/ && lc $1 eq 'pdf';
                }
            }
        },
    }, $source_path);
}

sub parse_plain
{
    my ($file, $addresses) = @_;

    open(my $fh, '<', $file) or die "$0: plain file `$file' cannot be opened: $!\n";
    my $content = do { local $/; <$fh> };
    close($fh);

    if ($content =~ /^(.+?)\n{2}/s) {
        my $header = $1;
        foreach my $field (qw(From To Cc Bcc Reply-To)) {
            if ($header =~ /^$field:\s+(.+?)(?=\n^\S)/ims) {
                push @$addresses, extract_addresses($1);
            }
        }
    }
}

sub parse_json
{
    my ($file, $addresses) = @_;

    open(my $fh, '<', $file) or die "$0: JSON file `$file' cannot be opened: $!\n";
    my $content = do { local $/; <$fh> };
    close($fh);

    my $json;
    unless (eval { $json = decode_json($content) }) {
        return;
    }
    unless (exists $json->{client_metadata}) {
        return;
    }
    my $metadata = $json->{client_metadata};
    unless (exists $metadata->{displayName} && exists $metadata->{emailAddresses}) {
        return;
    }

    my $phrase = $metadata->{displayName};

    foreach my $address (@{$metadata->{emailAddresses}}) {
        my $address = email_to_unicode($address->{address});
        push @$addresses, [ $phrase, $address ];
    }
}

sub parse_pdf
{
    my ($file, $addresses) = @_;
}

sub extract_addresses
{
    my ($string) = @_;

    my @addresses;

    foreach my $addr (Email::Address->parse($string)) {
        my $address = $addr->address;
        my $phrase  = $addr->phrase // '';

        $address = email_to_unicode($address);

        $phrase = decode('MIME-Header', $phrase);
        $phrase = do {
            local $_ = $phrase;
            s/^['"]//;
            s/['"]$//;
            $_
        };
        push @addresses, [ $phrase, $address ];
    }

    return @addresses;
}

sub filter_sort
{
    my ($addresses, $filter) = @_;

    my $filter_regex = sub
    {
        my ($address) = @_;
        foreach my $regex (@$filter) {
            return false if $address =~ /$regex/i;
        }
        return true;
    };
    @$addresses = grep $filter_regex->($_->[1]), @$addresses;

    my %seen;
    @$addresses = sort { $a->[1] cmp $b->[1]      }  # sort alphabetically
                  grep { !$seen{$_->[1]}++        }  # filter duplicates
                  map  { $_->[1] = lc $_->[1]; $_ }  # lower-case address
                  @$addresses;
}

sub save_csv
{
    my ($csv_file, $addresses) = @_;

    open(my $fh, '>:encoding(UTF-8)', $csv_file) or die "$0: csv file `$csv_file' cannot be opened: $!\n";

    foreach my $address (@$addresses) {
        my $entry = join q{, }, @$address;
        print {$fh} $entry, "\n";
    }

    close($fh);
}
