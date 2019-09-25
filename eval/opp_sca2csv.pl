#!/usr/bin/env perl
#
# Copyright (C) 2008-2019 Christoph Sommer <sommer@ccs-labs.org>
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
# opp_sca2csv.pl - Outputs OMNeT++ 4 output scalar files in CSV format, collating values from multiple scalars into one column each
#

use strict;
use warnings;
use Getopt::Long;

my $noHeader = 0;
my $modulesRe = "";
my @fileNames = "";
GetOptions (
	"modules|m:s" => \$modulesRe,
	"files|f:s{,}" => \@fileNames,
	"no-header|H" => \$noHeader,
);

if (@ARGV < 1) {
	print STDERR "usage: opp_sca2csv.pl <sca_name> [<sca_name> ...] [OPTIONS]\n";
	print STDERR "\n";
	print STDERR "  -m --modules:      Regular expression to match module names against. If used\n";
	print STDERR "                     with a named capture group (?<module>...), only this portion\n";
	print STDERR "                     of the module name is considered\n";
	print STDERR "                     [default: all]\n";
	print STDERR "  -f --files:        Name of file to read. Can be given multiple times\n";
	print STDERR "                     [default: read from stdin]\n";
	print STDERR "  -H --no-header:    Do not print header line\n";
	print STDERR "                     [default: print header]\n";
	print STDERR "\n";
	print STDERR "e.g.: opp_sca2csv.pl -m '".'^scenario\.host\[(?<module>[0-9]+)\]'."' totalRcvd totalSent <input.sca >output.csv\n";
	exit;
}

my @sca_names;
my %sca_known;
while (my $sca_name = shift @ARGV) {
	push (@sca_names, $sca_name);
	$sca_known{$sca_name} = 1;
}


# output CSV header

if ($noHeader) {
}
else {
	print "nod_name";
	foreach my $sca_name (@sca_names) {
		print "\t".$sca_name;
	}
	print "\n";
}

sub processFile {
	local (*handle) = @_;

	# read attrs from SCA header

	my %sca_attrs = ();
	while (<handle>) {

		# header ends on empty line
		last if (m{^\s*$});

		# line must contain scalar data
		next unless (m{
				^attr
				\s+
				(("([^"]+)")|([^\s]+))
				\s+
				(("([^"]+)")|([^\s]+))
				\r?\n$
			}x ||
			m{
                                ^itervar
                                \s+
                                (("([^"]+)")|([^\s]+))
                                \s+
                                (("([^"]+)")|([^\s]+))
                                \r?\n$
                        }x);

		my $attr = defined($3)?$3:"" . defined($4)?$4:"";
		my $value = defined($7)?$7:"" . defined($8)?$8:"";

		next if ($attr =~ m{datetime|inifile|iterationvars|iterationvars2|measurement|network|processid|replication|resultdir|seedset});

		$sca_attrs{$attr} = $value;

		if ($attr eq 'experiment') {
			my @parts = split('-', $value);
			foreach my $part (@parts) {
				my @av = split('_', $part);
				if ($av[1]) {
					$sca_attrs{$av[0]} = $av[1];
				} else {
					$sca_attrs{$av[0]} = $av[0];
				}
			}
		}
	}


	# read SCA body, output CSV body

	my $current_nod_name = "";
	my %sca_values = %sca_attrs;
	my $have_sca_values = 0;
	while (<handle>) {
		# line must contain scalar data
		next unless (m{
				^scalar
				\s+
				(("([^"]+)")|([^\s]+))
				\s+
				(("([^"]+)")|([^\s]+))
				\s+
				([0-9.-]+)
				\r?\n$
			}x);

		my $nod_name = defined($3)?$3:"" . defined($4)?$4:"";
		my $sca_name = defined($7)?$7:"" . defined($8)?$8:"";
		my $value = $9;

		if (defined($modulesRe) and ($modulesRe)) {
			next unless ($nod_name =~ $modulesRe);
			if (defined($+{module})) {
				$nod_name = $+{module};
			}
		}

		# sca_name must be among those given on cmdline
		next unless exists($sca_known{$sca_name});

		# new nod_name?
		if (!($nod_name eq $current_nod_name)) {

			# see if there's anything in the buffer, print it
			if ($have_sca_values) {
				print $current_nod_name;
				foreach my $sca_name (@sca_names) {
					my $value = $sca_values{$sca_name};
					print "\t".(defined $value ? $value : "");
				}
				print "\n";
			}

			# start over
			$current_nod_name = $nod_name;
			%sca_values = %sca_attrs;
			$have_sca_values = 0;

		}

		# buffer value
		$sca_values{$sca_name} = $value;
		$have_sca_values = 1;

	}

	# see if there's anything in the buffer, print it
	if ($have_sca_values) {
		print $current_nod_name;
		foreach my $sca_name (@sca_names) {
			my $value = $sca_values{$sca_name};
			print "\t".(defined $value ? $value : "");
		}
		print "\n";
	}
}

# remove first (empty?!) component of array passed via "-f" parameter
shift @fileNames;

if (scalar @fileNames == 0) {
	processFile(*STDIN);
} else {
	foreach my $fname (@fileNames) {
		open(F, $fname);
		processFile(*F);
		close F;
	}
}
