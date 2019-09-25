#!/usr/bin/env perl
#
# Copyright (C) 2011-2016 Christoph Sommer <sommer@ccs-labs.org>
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

#
# opp_vec2csv.pl -- converts OMNeT++ .vec files to csv format
#
# (Refer to POD sections at end of file for documentation)
#
use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case bundling auto_version auto_help);
use Pod::Usage;

$main::VERSION = 3.02;

my $verbose = 0;
my %vectorNames = ();
my %attrNames = ();
my %paramNames = ();
my $mergeBy = "";
my $sampleRate = 1;
my $randomSeed = -1;
GetOptions (
	"filter|F:s" => \%vectorNames,
	"attr|A:s" => \%attrNames,
	"param|P:s" => \%paramNames,
	"merge-by|m:s" => \$mergeBy,
	"sample|s:i" => \$sampleRate,
	"seed|S:i" => \$randomSeed,
	"verbose|v" => \$verbose
) or pod2usage("$0: Bad command line options.\n");
pod2usage("$0: No vector files given.\n") if (@ARGV < 1);


# let's go
if ($randomSeed == -1) {
	$randomSeed = srand() ^ time();
	print STDERR "using dynamic random seed $randomSeed\n" if $verbose and ($sampleRate > 1);
}
else {
	print STDERR "using static random seed $randomSeed\n" if $verbose;
}

# get list of file names from command line
my @fileNames;
while (my $fileName = shift @ARGV) {
	push (@fileNames, $fileName);
}

# print header
print "event";
print "\t"."time";
print "\t"."node";
foreach my $attrName (sort keys %attrNames) {
	my $value = $attrNames{$attrName};
	$value = $attrName unless (defined $value and $value ne "");
	print "\t".$value;
}
foreach my $paramName (sort keys %paramNames) {
	my $value = $paramNames{$paramName};
	$value = $paramName unless (defined $value and $value ne "");
	print "\t".$value;
}
foreach my $vectorName (sort keys %vectorNames) {
	my $value = $vectorNames{$vectorName};
	$value = $vectorName unless (defined $value and $value ne "");
	print "\t".$value;
}
print "\n";



# get functions to determine unique rows (and to sort rows)

sub mergeFunctionL { my ($lineNo, $event, $module, $time) = @_; return $lineNo; }
sub sortFunctionL($$) { $_[0] <=> $_[1]; }

sub mergeFunctionEMT { my ($lineNo, $event, $module, $time) = @_; return $event."|".$module."|".$time; }
sub sortFunctionEMT($$) { $_[0] cmp $_[1]; }

sub mergeFunctionEM { my ($lineNo, $event, $module, $time) = @_; return $event."|".$module; }
sub sortFunctionEM($$) { $_[0] cmp $_[1]; }

sub mergeFunctionET { my ($lineNo, $event, $module, $time) = @_; return $event."|".$time; }
sub sortFunctionET($$) { $_[0] cmp $_[1]; }

sub mergeFunctionMT { my ($lineNo, $event, $module, $time) = @_; return $module."|".$time; }
sub sortFunctionMT($$) { $_[0] cmp $_[1]; }

sub mergeFunctionE { my ($lineNo, $event, $module, $time) = @_; return $event; }
sub sortFunctionE($$) { $_[0] <=> $_[1]; }

sub mergeFunctionM { my ($lineNo, $event, $module, $time) = @_; return $module; }
sub sortFunctionM($$) { $_[0] cmp $_[1]; }

sub mergeFunctionT { my ($lineNo, $event, $module, $time) = @_; return $time; }
sub sortFunctionT($$) { $_[0] <=> $_[1]; }

my $mergeFunction = \&mergeFunctionL;
my $sortFunction = \&sortFunctionL;
if ($mergeBy eq '') {
}
elsif ($mergeBy eq 'emt') {
	$mergeFunction = \&mergeFunctionEMT;
	$sortFunction = \&sortFunctionEMT;
}
elsif ($mergeBy eq 'em') {
	$mergeFunction = \&mergeFunctionEM;
	$sortFunction = \&sortFunctionEM;
}
elsif ($mergeBy eq 'et') {
	$mergeFunction = \&mergeFunctionET;
	$sortFunction = \&sortFunctionET;
}
elsif ($mergeBy eq 'mt') {
	$mergeFunction = \&mergeFunctionMT;
	$sortFunction = \&sortFunctionMT;
}
elsif ($mergeBy eq 'e') {
	$mergeFunction = \&mergeFunctionE;
	$sortFunction = \&sortFunctionE;
}
elsif ($mergeBy eq 'm') {
	$mergeFunction = \&mergeFunctionM;
	$sortFunction = \&sortFunctionM;
}
elsif ($mergeBy eq 't') {
	$mergeFunction = \&mergeFunctionT;
	$sortFunction = \&sortFunctionT;
}
else {
	die("unknown merge type: \"".$mergeBy."\"");
}

# remember if we already warned about overwriting a value
my $warnedOverwriteValue = 0;

# iterate over vector files
foreach my $fileName (@fileNames) {

	# this is where we store all the data
	my %events = ();

	print STDERR "reading \"".$fileName."\"...\n" if $verbose;

	my $FILE;
	open($FILE, $fileName) or die("Error opening file \"".$fileName."\"");

	my $fileSize = -s $fileName;

	print STDERR "reading file...\n" if $verbose;

	# read file
	my %attrValues = ();
	my %paramValues = ();
	my @nodName = (); # vector_id <-> nod_name mappings
	my @vecName = (); # vector_id <-> vec_name mappings
	my @vecType = (); # vector_id <-> type mappings
	while (<$FILE>) {
		my $lineNumber = $.;

		# found vector data
		if (m{
				^
				(?<vecnum>[0-9]+)
				\s+
				(?<event>[0-9]+)
				\s+
				(?<vecdata>.*)
				\r?\n$
			}x) {

			my $event = $+{event};

			# obey sampling
			if ($sampleRate > 1) {
				srand($randomSeed + $event);
				next unless int(rand($sampleRate)) == 0;
			}

			# print progress
			if ($verbose and ($. % 10000 == 0)) {
				print STDERR sprintf("%.1f", tell($FILE)/1024/1024)."M/".sprintf("%.1f", $fileSize/1024/1024)."M (".sprintf("%.1f", tell($FILE)/$fileSize*100)."%)\r";
			}

			# look up definition
			my $nod_name = $nodName[$+{vecnum}];
			my $vec_name = $vecName[$+{vecnum}];
			my $vec_type = $vecType[$+{vecnum}];

			# vec_name must have been given on command line
			next unless exists($vectorNames{$vec_name});

			# extract time and value
			my $time = "";
			my $value = "";
			if ($vec_type eq 'ETV') {
				unless ($+{vecdata} =~ m{
							^
							(?<time>[0-9e.+-]+)  # allow -1.234e+56
							\s+
							(?<value>([0-9e.+-]+)|(nan))  # allow -1.234e+56 and nan
							$
							}x) {
					print STDERR "cannot parse as ETV: \"".$+{vecdata}."\"\n";
					next;
				}
				$time = $+{time};
				$value = $+{value};
			} else {
				print STDERR "unknown vector type: \"".$vec_type."\"\n";
				next;
			}

			my $key = $mergeFunction->($lineNumber, $event, $nod_name, $time);
			if ($verbose and not $warnedOverwriteValue and defined $events{$key}{$vec_name}) {
				print STDERR "WARNING: value on \"".$fileName."\" line ".$lineNumber." overwrites existing value for \"".$key.".".$vec_name."\". Consider using a different value for --merge-by.\n";
				$warnedOverwriteValue = 1;
			}
			$events{$key}{"__TIME"} = $time;
			$events{$key}{"__EVENT"} = $event;
			$events{$key}{"__NODE"} = $nod_name;
			$events{$key}{$vec_name} = $value;

			next;
		}

		# found vector definition
		if (m{
				^vector
				\s+
				(?<vecnum>[0-9.]+)
				\s+
				(("(?<nodname1>[^"]+)")|(?<nodname2>[^\s]+))
				\s+
				(("(?<vecname1>[^"]+)")|(?<vecname2>[^\s]+))
				(\s+(?<vectype>[ETV]+))?
				\r?\n$
				}x) {
			$nodName[$+{vecnum}] = defined($+{nodname1})?$+{nodname1}:"" . defined($+{nodname2})?$+{nodname2}:"";
			$vecName[$+{vecnum}] = defined($+{vecname1})?$+{vecname1}:"" . defined($+{vecname2})?$+{vecname2}:"";
			$vecType[$+{vecnum}] = defined($+{vectype})?$+{vectype}:"";
			next;
		}

		# found attr
		if (m{
				^attr
				\s+
				(?<attr>[^ ]+)
				\s+
				(?<value>.+)
				\r?\n$
				}x) {
			$attrValues{$+{attr}} = $+{value};
			next;
		}

		# found param
		if (m{
				^param
				\s+
				(?<param>[^ ]+)
				\s+
				(?<value>.+)
				\r?\n$
				}x) {
			$paramValues{$+{param}} = $+{value};
			next;
		}
       
        print STDERR "\n\nUnknown line: $_\n\n" if $verbose;


	}

	close($FILE);

	print STDERR "done processing                             \r" if $verbose;

	# print body
	foreach my $key (sort $sortFunction keys %events) {
		my $time = $events{$key}{"__TIME"};
		my $event = $events{$key}{"__EVENT"};
		my $node = $events{$key}{"__NODE"};
		print $event;
		print "\t".$time;
		print "\t".$node;
		foreach my $attrName (sort keys %attrNames) {
			my $value = $attrValues{$attrName};
			print "\t".(defined $value ? $value : "");
		}
		foreach my $paramName (sort keys %paramNames) {
			my $value = $paramValues{$paramName};
			print "\t".(defined $value ? $value : "");
		}
		foreach my $vectorName (sort keys %vectorNames) {
			my $value = $events{$key}{$vectorName};
			print "\t".(defined $value ? $value : "");
		}
		print "\n";
	}

	print STDERR "done                                        \n" if $verbose;
}

__END__

=head1 NAME

opp_vec2csv.pl -- converts OMNeT++ .vec files to csv format

=head1 SYNOPSIS

opp_vec2csv.pl [options] [file ...]

-F --filter <name>[=<alias>]

	add a column for vector <name>, calling it <alias> (if provided)

-A --attr <name>[=<alias>]

	add a column for attribute <name>, calling it <alias> (if provided)

-P --param <name>[=<alias>]

	add a column for parameter <name>, calling it <alias> (if provided)

-m --merge-by <e, m, t, or any combination thereof>

	merge all those entries into one row that fulfill all of the following conditions:
	- e: same event number
	- m: same module name
	- t: same timestamp
	default behavior is to keep each input line on its own output row

-s --sample <rate>

	output only a random sample of one in <rate> observations

-S --seed <seed>

	use a specific random seed for pseudo-random sampling

-v --verbose

	log debug information to stderr

e.g.: opp_vec2csv.pl -A configname -F senderName -F receivedBytes=bytes input.vec >output.csv

=cut

