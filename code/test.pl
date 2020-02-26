use strict;
use warnings;

for my $i (0 .. 9) {
	print $i;
	$i++ if ($i == 5);
}