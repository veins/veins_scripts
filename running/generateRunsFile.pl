#!/usr/bin/env perl

#
# Copyright (C) 2012-2014 Christoph Sommer <sommer@ccs-labs.org>
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
# Runs './run -a' in the current directory and outputs all possible combinations of './run -u Cmdenv -c X -r Y' lines.
# Output is formatted for use with runmaker4.py (see <https://github.com/veins/runmaker>).
#

use List::Util qw(shuffle);

my $command = "./run -u Cmdenv -c";

my @configs = `./run -a`;
my @runs = ();

foreach (@configs) {
	if ($_ =~ /Config ([^\:]*): (\d*)/) {
		for (my $i=0; $i < $2; $i++) {
			if ($ARGV[0] ne "") {
				push(@runs,". $command $1 -r $i --result-dir=\"$ARGV[0]\"\n");
			} else {
				push(@runs,". $command $1 -r $i\n");
			}
		}
	}
}

print $_ foreach(shuffle @runs);
