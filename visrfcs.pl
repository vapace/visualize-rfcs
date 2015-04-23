#!/usr/bin/perl -w

use strict;

sub fetch_rfc_index {
    # from perldoc perlipc: A Webget Client
    use IO::Socket;
    my $host = "www.ietf.org";
    my $document = "/rfc/rfc-index";

    my $EOL = "\r\n";
    my $BLANK = $EOL x 2;

    my $remote = IO::Socket::INET->new( Proto     => "tcp",
                        PeerAddr  => $host,
                        PeerPort  => "http(80)",
          )     || die "cannot connect to httpd on $host";

    $remote->autoflush(1);

    # send GET request
    print $remote "GET $document HTTP/1.0${EOL}Host: $host$BLANK";

    my @rfcindex = ();
    while (<$remote>) {
        push @rfcindex, $_;
    }
    close $remote;
    @rfcindex;
}

sub fetch_local_rfc_index {
    open my $f, "<", "rfc-index"
        or die "cannot open \"rfc-index\": $!\n";
    my @rfcindex = <$f>;
    @rfcindex;
}

sub fetch_rfc_index_oneliners {
    my $seen_0001 = 0;
    my $full_line = "";
    my @rfc_index_oneliners;

    for (fetch_rfc_index) {
    # for (fetch_local_rfc_index) {
        chomp;
        my $this_line = $_;
        if (!$seen_0001) {
            if (m/^0001\s+/) {
                $seen_0001 = 1;
            }
            if (m/CREATED/) {
                $full_line = $this_line;
                $this_line = "";
            } else {
                next if !$seen_0001;
            }
        }
        next if $this_line =~ m/Not Issued\.$/;
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

my $MONTH = qr(January|February|March|April|May|June|July|August|September|October|November|December);
my @rfcids = ();
my %rfc = ();
for (fetch_rfc_index_oneliners) {
    if (my ($id, $title, $authors, $date, $format, $rest, $status) = m/^(\d+) ((?:[^.]|\.(?! ))*)\. (.*)\. ($MONTH (?:\d+ )?\d+)\. \(Format: ([^)]*)\)(.*)\(Status: ([^)]*)\)/) {
        if ($date =~ m/^April 1 /) {
            # print "April 1 RFC: $_\n";
            next;
        }

        my $rfcid = "RFC$id";

        push @rfcids, $rfcid;

        $title =~ s/"/\\"/g;
        $rfc{$rfcid}{title} = $title;
        $rfc{$rfcid}{authors} = $authors;
        $rfc{$rfcid}{date} = $date;
        $rfc{$rfcid}{format} = $format;
        $rfc{$rfcid}{status} = $status;
        my ($obsoletes) = $rest =~ m/\(Obsoletes ([^)]*)\)/;
        my ($obsoleted_by) = $rest =~ m/\(Obsoleted by ([^)]*)\)/;
        my ($updates) = $rest =~ m/\(Updates ([^)]*)\)/;
        my ($updated_by) = $rest =~ m/\(Updated by ([^)]*)\)/;
        if (defined($obsoletes)) {
            push @{$rfc{$rfcid}{obsoletes}}, split(", ", $obsoletes);
        }
        if (defined($obsoleted_by)) {
            push @{$rfc{$rfcid}{obsoleted_by}}, split(", ", $obsoleted_by);
        }
        if (defined($updates)) {
            push @{$rfc{$rfcid}{updates}}, split(", ", $updates);
        }
        if (defined($updated_by)) {
            push @{$rfc{$rfcid}{updated_by}}, split(", ", $updated_by);
        }
        # print "$id $date $status\n";
    } else {
        # print "No match: $_\n";
    }
}

# use Data::Dumper;
# $Data::Dumper::Sortkeys = 1;
# print Dumper(\%rfc);

print "digraph RFCs {\n";
print "  graph [rankdir=BT];\n";
print "  node [shape=circle, style=filled, fillcolor=lightyellow];\n\n";

# my %date = ();
for my $rfcid (reverse @rfcids) {
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
