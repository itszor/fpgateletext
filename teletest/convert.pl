#!/usr/bin/perl

my $file = ""; 
while (<STDIN>) { $file .= $_; }
my $o = "";
my $cx = 0;
my $cy = 0;
my @t = ();
for ( my $i = 0; $i < length($file); $i++ ) { 	
	my $c = substr($file, $i, 1);
	if ( $c eq "\n" ) {
		$cy++; 
		$cx = 0; 
	} else {
		$f[$cx][$cy] = $c;
		$cx++;
		}	
	}
for ( my $y = 0; $y < 25; $y++ ) { 
	for ( my $x = 0; $x < 40; $x++ ) { 
		my $c = $f[$x][$y];
		if ( $c eq "" ) { $c = " "; } 
		my $o = ord($c);
		my $o1 = $o % 16;
		my $o2 = int ( ( $o - $o1 ) / 16 );
		print substr("0123456789ABCDEF", $o2, 1);
		print substr("0123456789ABCDEF", $o1, 1);
		print "\n";
		}
	}
	
