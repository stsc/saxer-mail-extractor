#!/usr/bin/perl
#===================================
# Extrahiere Mail-Inhalt von Quellen
#===================================
# Benutzung:
# °°°°°°°°°°
# Das Script muss über die Konsole via installiertem
# Perl-Interpreter aufgerufen werden. Mögliche Aufrufoptionen
# sind über die Hilfe Ausgabe (perl ./mail_extractor.pl --help)
# oder Dokumentation einsehbar.
# -------------------------------------------------------------
# Version: v0.00 - 2023-06-21 / sts
# ---------------------------------

use strict;
use warnings;
use constant true  => 1;
use constant false => 0;
use constant THRESHOLD_FLUSH => 500;

use CAM::PDF;
use CAM::PDF::PageText;
use Email::Address;
use Encode;
use File::Find;
use File::Spec;
use File::Temp qw(tempdir);
use File::Type;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use JSON;
use Net::IDN::Encode qw(email_to_unicode);
use POSIX qw(strftime);
use Time::Local qw(timelocal_posix);

my $VERSION = '0.00';

# Defines the filename template for temporary CSV output files;
# the underscore and single character will be inserted before
# the dot separator.  See also $csv_file_char().
my $CSV_file = 'addresses.csv';

my $read_file = sub
{
    my ($file) = @_;

    open(my $fh, '<', $file) or die "$0: file `$file' cannot be opened: $!\n";
    my $string = do { local $/; <$fh> };
    close($fh);

    return $string;
};

my $remove_quotes = sub
{
    local $_ = ${$_[0]};

    s/^['"]//;
    s/['"]$//;

    ${$_[0]} = $_;
};

my %opts;
GetOptions(\%opts, qw(c|config=s h|help parse-pdf V|version)) or usage(1);
usage(0) if $opts{h};

print "$0 v$VERSION\n" and exit 0 if $opts{V};

die "$0: -c/--config not specified or invalid. Invoke `$0 --help'.\n" unless defined $opts{c} && $opts{c} =~ /\S+/;

my $Config_file = $opts{c};

die "$0: configuration file `$Config_file' does not exist\n"  unless -e $Config_file;
die "$0: configuration file `$Config_file' is not readable\n" unless -r $Config_file;

my %config = parse_config($Config_file);

validate_config(\%config);

my $tmpdir = tempdir('mail-extractor.XXXXXXXXXX', TMPDIR => true, CLEANUP => true);

my $csv_file_char = sub
{
    my ($file, $char) = @_;
    (my $csv_file = $file) =~ s/(?=\.)/_$char/;
    return File::Spec->catfile($tmpdir, $csv_file);
};

my $get_last_timestamp = sub
{
    my ($time_stamp, $fmt) = @_;

    my @sort;
    foreach my $csv_file (glob(File::Spec->catfile($config{output_path}, 'addresses_full-*.csv'))) {
        (undef, undef, my $file) = File::Spec->splitpath($csv_file);
        $file =~ /^addresses_full-(.+?)\.(.+?)\.(.+?)-(.+?)\.(.+?)\.csv$/ or next;
        push @sort, [ 0, $5, $4, $1, $2 - 1, $3 - 1900 ];
    }
    my @sorted = map strftime($fmt, localtime $_), sort { $b <=> $a } map timelocal_posix(@$_), @sort;

    $$time_stamp = $sorted[0] // '';

    return defined $$time_stamp && length $$time_stamp ? true : false;
};

open(my $log_fh, '>', $config{log_file}) or die "$0: logging file `$config{log_file}' cannot be opened: $!\n";

# auto-flush file handle
my $old_fh = select($log_fh);
$| = true;
select($old_fh);

log_print("Start of %s. [v%s]", $0, $VERSION);

my $last_time_stamp = undef;
my $Incremental = $get_last_timestamp->(\$last_time_stamp, '%d.%m.%Y');

my $current_time_stamp = strftime('%d.%m.%Y-%H.%M', localtime);

my $csv_file_full = File::Spec->catfile($config{output_path}, "addresses_full-$current_time_stamp.csv");
my $csv_file_diff = File::Spec->catfile($config{output_path}, "addresses_diff-$last_time_stamp-$current_time_stamp.csv");

if ($Incremental) {
    my $time_stamp;
    $get_last_timestamp->(\$time_stamp, '%d.%m.%Y-%H.%M');

    my $csv_file_last = File::Spec->catfile($config{output_path}, "addresses_full-$time_stamp.csv");

    my @entries;
    read_csv($csv_file_last, \@entries);
    my %seen = map { $_->[1] => true } @entries;

    my @addresses;
    gather_files($config{source_path}, \@addresses);

    save_csv($csv_file_diff, \@addresses) if @addresses;
    @addresses = ();

    read_csv($csv_file_diff, \@addresses);

    filter_sort(\@addresses, $config{filter});

    write_csv($csv_file_full, \@addresses);
    unlink $csv_file_last if $csv_file_last ne $csv_file_full;

    @addresses = grep !$seen{$_->[1]}, @addresses;

    write_csv($csv_file_diff, \@addresses);
}
else {
    my %addresses;
    gather_files($config{source_path}, \%addresses);

    foreach my $char (keys %addresses) {
        my $csv_file = $csv_file_char->($CSV_file, $char);

        save_csv($csv_file, $addresses{$char}) if @{$addresses{$char}};
        @{$addresses{$char}} = ();

        my @addresses;
        read_csv($csv_file, \@addresses);

        filter_sort(\@addresses, $config{filter});

        write_csv($csv_file, \@addresses);
    }

    opendir(my $dh, $tmpdir) or die "$0: temporary directory `$tmpdir' cannot be opened: $!\n";
    my @csv_files = map File::Spec->catfile($tmpdir, $_), sort grep !/^\.\.?$/, readdir($dh);
    closedir($dh);

    open(my $fh, '>', $csv_file_full) or die "$0: CSV file `$csv_file_full' cannot be opened: $!\n";
    print {$fh} $read_file->($_) foreach @csv_files;
    close($fh);
}

log_print("End of %s.", $0);

close($log_fh);

sub usage
{
    my ($exit_code) = @_;

    print <<"USAGE";
Usage: $0 [switches]
    -c, --config=<path>    path to config file (mandatory)
    -h, --help             this help screen
        --parse-pdf        parse PDF (experimental)
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

sub log_print
{
    my ($fmt, @args) = @_;

    print {$log_fh} "[${\strftime('%b %d %H:%M:%S', localtime)}] ";
    print {$log_fh} sprintf($fmt, @args), "\n";
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
                elsif ($dir_matches->($File::Find::dir, qr/OneDrive/) && $opts{'parse-pdf'}) {
                    parse_pdf($File::Find::name, $addresses) if /(?!^)\.(.+)$/ && lc $1 eq 'pdf';
                }
            }
        },
    }, $source_path);
}

sub parse_plain
{
    my ($file, $addresses) = @_;

    open(my $fh, '<', $file) or do {
        log_print("Plain: %s: cannot be opened: $!", File::Spec->abs2rel($file, $config{source_path}));
        return;
    };
    my $content = do { local $/; <$fh> };
    close($fh);

    if ($content =~ /^(.+?)\n{2}/s) {
        my $header = $1;
        foreach my $field (qw(From To Cc Bcc Reply-To)) {
            if ($header =~ /^$field:\s+(.+?)(?=\n^\S)/ims) {
                foreach my $addr (Email::Address->parse($1)) {
                    my $address = $addr->address;
                    my $phrase  = $addr->phrase // '';

                    $address = email_to_unicode($address);

                    $phrase = decode('MIME-Header', $phrase);
                    $remove_quotes->(\$phrase);

                    save_address([ $phrase, $address ], $addresses);
                }
            }
        }
    }
}

sub parse_json
{
    my ($file, $addresses) = @_;

    open(my $fh, '<', $file) or do {
        log_print("JSON: %s: cannot be opened: $!", File::Spec->abs2rel($file, $config{source_path}));
        return;
    };
    my $content = do { local $/; <$fh> };
    close($fh);

    my $json;
    unless (eval { $json = decode_json($content) }) {
        log_print("JSON: %s: decode_json() failed", File::Spec->abs2rel($file, $config{source_path}));
        return;
    }
    unless (exists $json->{client_metadata}) {
        log_print("JSON: %s: client_metadata does not exist", File::Spec->abs2rel($file, $config{source_path}));
        return;
    }
    my $metadata = $json->{client_metadata};
    unless (exists $metadata->{displayName} && exists $metadata->{emailAddresses}) {
        log_print("JSON: %s: displayName and emailAddresses does not exist", File::Spec->abs2rel($file, $config{source_path}));
        return;
    }

    my $phrase = $metadata->{displayName};

    foreach my $email (@{$metadata->{emailAddresses}}) {
        foreach my $addr (Email::Address->parse($email->{address})) {
            my $address = email_to_unicode($addr->address);
            save_address([ $phrase, $address ], $addresses);
        }
    }
}

sub parse_pdf
{
    my ($file, $addresses) = @_;

    my $pdf;
    unless (eval { $pdf = CAM::PDF->new($file) }) {
        log_print("PDF: %s: new() failed", File::Spec->abs2rel($file, $config{source_path}));
        return;
    }
    my $pages;
    unless (eval { $pages = $pdf->numPages() }) {
        log_print("PDF: %s: numPages() failed", File::Spec->abs2rel($file, $config{source_path}));
        return;
    }
    for (my $i = 1; $i <= $pages; $i++) {
        my $tree = $pdf->getPageContentTree($i);
        my $string;
        unless (eval { $string = CAM::PDF::PageText->render($tree) }) {
            log_print("PDF: %s: render() failed", File::Spec->abs2rel($file, $config{source_path}));
            return;
        }
        foreach my $addr (Email::Address->parse($string)) {
            save_address([ '', $addr->address ], $addresses);
        }
    }
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

sub save_address
{
    my ($address, $addresses) = @_;

    $remove_quotes->(\$address->[1]);

    my ($csv_file, $stack);

    if ($Incremental) {
        $stack = $addresses;
        push @$stack, $address;
        $csv_file = $csv_file_diff;
    }
    else {
        my $char = lc substr($address->[1], 0, 1) // '?';
        $addresses->{$char} ||= [];
        $stack = $addresses->{$char};
        push @$stack, $address;
        $csv_file = $csv_file_char->($CSV_file, $char);
    }

    if (@$stack >= THRESHOLD_FLUSH) {
        save_csv($csv_file, $stack);
        @$stack = ();
    }
}

sub save_csv
{
    my ($csv_file, $addresses) = @_;

    open(my $fh, '>>:encoding(UTF-8)', $csv_file) or die "$0: CSV file `$csv_file' cannot be opened: $!\n";

    foreach my $address (@$addresses) {
        my $entry = join q{, }, @$address;
        print {$fh} $entry, "\n";
    }

    close($fh);
}

sub read_csv
{
    my ($csv_file, $addresses) = @_;

    open(my $fh, '<:encoding(UTF-8)', $csv_file) or die "$0: CSV file `$csv_file' cannot be opened: $!\n";
    @$addresses = map { chomp; /^(.*), (.+)$/; [ $1, $2 ] } <$fh>;
    close($fh);
}

sub write_csv
{
    my ($csv_file, $addresses) = @_;

    open(my $fh, '>:encoding(UTF-8)', $csv_file) or die "$0: CSV file `$csv_file' cannot be opened: $!\n";

    foreach my $address (@$addresses) {
        my $entry = join q{, }, @$address;
        print {$fh} $entry, "\n";
    }

    close($fh);
}
