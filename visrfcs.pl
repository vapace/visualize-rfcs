#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use Pod::Usage;

=head1 NAME

  rfc-index.pl - fetch rfc-index and parse it into json

=head1 SYNOPSIS

  rfc-index.pl [-h|--help]
  rfc-index.pl [--fetch] [--cache] [--json|--dot]

=cut

main();

exit 0;

my %opts = ();

sub main {
    if (!parse_cmdline()) {
        show_usage();
    }
    do_actions();
}

sub show_usage {
    pod2usage();
}

sub parse_cmdline {
    return GetOptions(\%opts,
                "help",
                "fetch",
                "cache",
                "json",
                "dot",
           );
}

sub do_actions {
    if ($opts{help}) {
        pod2usage(-output => \*STDOUT, -exit => 0);
    }

    fetch_and_parse_rfc_index();
    if ($opts{dot}) {
        print_dot();
    } else {
        print_json();
    }
}

use constant RFC_INDEX_HOST => "www.rfc-editor.org";
use constant RFC_INDEX_PATH => "rfc-index.txt";

sub fetch_rfc_index {
    # from perldoc perlipc: A Webget Client
    use IO::Socket;
    my $host = RFC_INDEX_HOST;
    my $document = RFC_INDEX_PATH;

    my $EOL = "\r\n";
    my $BLANK = $EOL x 2;

    my $remote = IO::Socket::INET->new( Proto  => "tcp",
                        PeerAddr  => $host,
                        PeerPort  => "http(80)",
    ) or die "cannot connect to HTTP on $host";

    $remote->autoflush(1);

    # send GET request
    print $remote "GET /$document HTTP/1.0${EOL}Host: $host$BLANK";

    my @rfcindex = ();
    while (<$remote>) {
        push @rfcindex, $_;
    }
    close $remote;

    if ($opts{cache}) {
        # TODO: save to local
    }
    @rfcindex;
}

sub fetch_local_rfc_index {
    open my $f, "<", RFC_INDEX_PATH
        or die "cannot open \".RFC_INDEX_PATH.\": $!\n";
    my @rfcindex = <$f>;
    @rfcindex;
}

sub fetch_rfc_index_oneliners {
    my $seen_0001 = 0;
    my $full_line = "";
    my @rfc_index_oneliners;

    for ($opts{fetch} ? fetch_rfc_index : fetch_local_rfc_index) {
        chomp;
        my $this_line = $_;
        if (!$seen_0001) {
            if (m/^0001\s+/) {
                $seen_0001 = 1;
            }
            next if !$seen_0001;
        }
        if ($this_line) {
            # remove leading whitespace
            $this_line =~ s/^\s+//;
            $full_line .= " ".$this_line;
        } elsif ($full_line) {
            # remove leading whitespace
            $full_line =~ s/^\s+//;
            push @rfc_index_oneliners, $full_line;
            $full_line = "";
        }
    }
    @rfc_index_oneliners
}

my %rfc = ();
my @rfc;

sub fetch_and_parse_rfc_index {
    my @MONTH_NAMES = qw(January February March April May June July August September October November December);
    my $MONTH_NAME_REGEX_STR = join("|", @MONTH_NAMES);
    my $MONTH_NAME_REGEX = qr($MONTH_NAME_REGEX_STR);
    my %MONTH_NUM;
    {
    my $m = 0;
    %MONTH_NUM = map { $_ => ++$m } @MONTH_NAMES;
    }
    for (fetch_rfc_index_oneliners) {
        if (my ($id, $not_issued) = m/^(\d+) (Not Issued)\.\s*$/) {
            my $rfcid = "RFC$id";
            my %this_rfc = (
                id => $rfcid,
                status => $not_issued,
            );
            $rfc{$rfcid} = { %this_rfc };
            push @rfc, $rfc{$rfcid};
            next;
        }
        if (my ($id, $title, $authors, $date, $format, $rest, $status, $doi) = m/^(\d+) ((?:[^.]|\.(?! ))+)\. (.+)\. ((?:\d+ )?$MONTH_NAME_REGEX \d+)\. \(Format: ([^)]+)\)(.*)\(Status: ([^)]+)\) \(DOI: ([^)]+)\)/) {
            my $rfcid = "RFC$id";
            $title =~ s/"/\\"/g;
            my %this_rfc = ();
            $this_rfc{id} = $rfcid;
            $this_rfc{title} = $title;
            $this_rfc{authors_txt} = $authors;
            $this_rfc{authors} = [ $authors =~ m/([^,]+(?:, (?:Ed\.|II))?)(?:, |\.?$)/g ];
            $this_rfc{date_txt} = $date;
            my ($d, $M, $y) = $date =~ m/(\d+ )?($MONTH_NAME_REGEX) (\d+)/;
            $this_rfc{date_y} = int($y);
            $this_rfc{date_m} = $MONTH_NUM{$M};
            $this_rfc{date_M} = $M;
            $this_rfc{date_d} = $d if defined $d;
            $this_rfc{date_ymd} = int($y)*1_00_00 + $MONTH_NUM{$M}*1_00 + (defined($d) ? int($d) : 0);
            $this_rfc{format_txt} = $format;
            $this_rfc{format} = { $format =~ m/([A-Z]+)=(\d+)/g };
            while (my ($k, $v) = each %{$this_rfc{format}}) {
                $this_rfc{format}{$k} = int($v);
            }
            $this_rfc{status} = $status;
            $this_rfc{doi} = $doi;
            my ($obsoletes) = $rest =~ m/\(Obsoletes ([^)]+)\)/;
            my ($obsoleted_by) = $rest =~ m/\(Obsoleted by ([^)]+)\)/;
            my ($updates) = $rest =~ m/\(Updates ([^)]+)\)/;
            my ($updated_by) = $rest =~ m/\(Updated by ([^)]+)\)/;
            my ($also) = [ $rest =~ m/\(Also ([^)]+)\)/g ];
            if (defined($obsoletes)) {
                push @{$this_rfc{obsoletes}}, split(", ", $obsoletes);
            }
            if (defined($obsoleted_by)) {
                push @{$this_rfc{obsoleted_by}}, split(", ", $obsoleted_by);
            }
            if (defined($updates)) {
                push @{$this_rfc{updates}}, split(", ", $updates);
            }
            if (defined($updated_by)) {
                push @{$this_rfc{updated_by}}, split(", ", $updated_by);
            }
            if (@$also) {
                $this_rfc{also} = $also;
            }
            $rfc{$rfcid} = { %this_rfc };
            push @rfc, $rfc{$rfcid};
        } else {
            print STDERR "No match: $_\n";
        }
    }
}

sub dd {
    use Data::Dumper;
    $Data::Dumper::Sortkeys = 1;
    print Dumper(@_);
}

sub print_dot {
    print "digraph RFCs {\n";
    print "  graph [rankdir=BT];\n";
    print "  node [shape=circle, style=filled, fillcolor=lightyellow];\n\n";

    # my %date = ();
    for my $rfcid (reverse keys %rfc) {
        # if (not exists($date{$rfc{$rfcid}{date}})) {
        #     print "  \"$rfc{$rfcid}{date}\" [style=\"invis\"];\n";
        #     $date{$rfc{$rfcid}{date}} = 1;
        # }
        print "  $rfcid [href=\"http://tools.ietf.org/html/".(lc $rfcid)."\" tooltip=\"$rfcid: $rfc{$rfcid}{title}\"];\n";
        # print "    $rfcid -> \"$rfc{$rfcid}{date}\" [style=\"invis\"]\n";
        if (exists($rfc{$rfcid}{obsoletes})) {
            for my $obsrfcid (@{$rfc{$rfcid}{obsoletes}}) {
                print "    $obsrfcid -> $rfcid;\n";
            }
        }
        if (exists($rfc{$rfcid}{updates})) {
            for my $updrfcid (@{$rfc{$rfcid}{updates}}) {
                print "    $updrfcid -> $rfcid [style=dashed];\n";
            }
        }
    }

    print "}\n";
}

sub print_json {
    use JSON::PP;

    my $json = JSON::PP->new->ascii->pretty->canonical;

    print $json->pretty->encode(\@rfc);
}
