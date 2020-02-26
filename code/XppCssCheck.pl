#*****************************************************************************
#*                           XppCssChecker   			                     *
#*            this software is licensed under the MIT license                *
#*****************************************************************************
# V00.01 - 2020/02/16 - start


use strict;
use warnings;
use 5.028;

use Getopt::Long;
use Path::Tiny;
use XML::Simple;

#can comment this out for production version
use Data::Dumper;

#some variables
my $Debug = 5;
my $ErrorNr = 0;
my $Rules;

#=============================================================
#  MAIN
#=============================================================
umask 000;
my $file = preFlight();
my $css = readFile($file);
#scan and parse into rules
scanForRules($css);
printCssRules() if ( $Debug > 5 );
#no need to dig any further - first resolve these errors
if ($ErrorNr) {
	printErrors();
	exit(-1);
}

exit();!
# into properties and values
scanRules();


exit();

#=============================================================
#  FUNCTIONS
#=============================================================
#-------------------------------------------------------------
sub message {
#-------------------------------------------------------------
	#level 0 = fatal error
	#level 1 = progress
	#level 2 = error
	#level 3 = warning
	#level 5 = info
	#level 9 = debug
	my $mesg = shift;
	my $level = shift || 5;
	say $mesg; #if ($level <= $Debug);
	
	return;
}

#-------------------------------------------------------------
sub preFlight {
#-------------------------------------------------------------
	unless ( exists $ENV{'XYV_EXECS'} ) {
		message('This system is not set up to run XPP software', 0);
		exit(-1);
	}
	my $prog = progName();
	my $config = path($ENV{'XYV_EXECS'}, 'procs', 'config', $prog,  "${prog}_config.xml");
	unless ( $config->exists ) {
		message("This system is not set up to run this tool, config file is missing: $config", 0);
		exit(-1);
	}


	GetOptions('debug=i' => \$Debug) or printUsage();
	my $noa = scalar(@ARGV);
	printUsage() if ( $noa > 1 );

	my $file = shift @ARGV;
	unless ( -r $file ) {
		message("could not read CSS file: $file", 1);
		exit(-1);
	}
	
	return($file);
}

#-------------------------------------------------------------
sub progName {
#-------------------------------------------------------------
    my $prog = $0;
    $prog = path($prog)->basename;
    $prog =~ s/\..*$//;
    return($prog);
}


#-------------------------------------------------------------
sub printCssRules {
#-------------------------------------------------------------
	my $rulesCss = scalar(@{$Rules->{'css'}}) - 1;
	message("$rulesCss CSS rules found", 5);
	for my $ruleNr ( 1 .. $rulesCss ) {
		my $declarations = stripWS($Rules->{'css'}->[$ruleNr]->{'rule'});
		my $selector = stripWS($Rules->{'css'}->[$ruleNr]->{'selector'});
		message("rule $ruleNr", 9);
		message(" selector:  $selector", 9);
		message(" declarations:  $declarations", 9);
	}	
	
	return;
}

#-------------------------------------------------------------
sub printErrors {
#-------------------------------------------------------------
	message("$ErrorNr errors detected: ", 2);
	for my $error ( 1 .. $ErrorNr ) {
		message($Rules->{'errors'}->[$error], 2);
	}
	
	return;
}

#-------------------------------------------------------------
sub readFile {
#-------------------------------------------------------------
	my $file = path(shift);
	my $css = $file->slurp_utf8;

	return($css);
}

#-------------------------------------------------------------
sub scanForRules {
#-------------------------------------------------------------
	my $css = shift;
	my $lineNr = 1;
	my $atRuleNr = 0;
	my $cssRuleNr = 0;
	my $currentRuleNr;
	my $selector = "";
	my $string = "";
	my $terminator = ";|}";
	my $inRule = "";
	my $inComment = 0;

	my $length = length($css);
	#forced to use c-style for loop, need to be able to modify $i
	for ( my $i = 0; $i < $length; $i++ ) {
		my $chr = substr $css, $i, 1;
		#line counter
		if ( $chr eq "\n" ) { 
			$lineNr++;
			$string .= $chr;
		}
		#comment start
		elsif ( $chr eq "/" ) {
			my $chrNext = substr $css, $i+1, 1;
			if ( $chrNext eq '*' ) {
				$inComment = 1;
				message(" line: $lineNr \tstart of comment", 7);				
			} else {
				$string .= $chr;
			}			
		}
		#comment end
		elsif ( $inComment and $chr eq '*' ) {
			my $chrNext = substr $css, $i+1, 1;
			if ( $chrNext eq '/' ) {
				$inComment = 0;
				$i++;
				message(" line: $lineNr \t end of comment", 7);				
			}		
		}
		elsif ( $inComment ) {
			#nothing to do - just suppress
		}

		#at and css rules: illegal start
		elsif ( $inRule and ($chr eq '@' or $chr eq '{') ) {
			$ErrorNr++;
			my $ruleLineNr = $Rules->{$inRule}->[$currentRuleNr]->{'line'};
			$Rules->{'errors'}->[$ErrorNr] = "ERROR line: $ruleLineNr - open rule not ended";
			
			$ErrorNr++;
			$Rules->{'errors'}->[$ErrorNr] = "ERROR line: $lineNr - illegal start of statement found $chr";
		}
		#at-rule: start
		elsif ( $chr eq '@' ) {
			$atRuleNr++;
			$currentRuleNr = $atRuleNr;
			$inRule = 'at';
			message(" line: $lineNr \tstart of at-rule $currentRuleNr", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'line'} = $line;
			$terminator = ';';
			$string = "";
		} 
		#css rule: start
		elsif ( $chr eq "{" ) {
			$cssRuleNr++;
			$currentRuleNr = $cssRuleNr;
			$inRule = 'css';
			message(" line: $lineNr \tstart of css-rule $rule", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'line'} = $line;
			$Rules->{$inRule}->[$currentRuleNr]->{'selector'} = $string;
			$terminator = '}';
			$string = "";
		} 
		#at and css rules: legal end
		elsif ( $inRule and ($chr eq $terminator) ) {
			message(" line: $lineNr \t end of ${inRule}-rule $rule", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'rule'} = $string;
			$string = "";
			$terminator = ";|}";
			$inRule = "";
		}
		#at and css rules: illegal end
		elsif ( $chr =~ m/$terminator/ ) {
			$ErrorNr++;
			$Rules->{'errors'}->[$ErrorNr] = "ERROR line: $lineNr - illegal end of statement found $chr ";
		}
		#normal character
		else {
			$string .= $chr;
		}
	}
	
	return;
}

#-------------------------------------------------------------
sub scanRules {
#-------------------------------------------------------------
	my $rulesCss = 0;
	for my $ruleNr ( 1 .. $Rules ) {
		my $type = $CSS->{'rules'}->[$ruleNr]->{'type'};
		if ( $type eq 'css' ) {
			validateCSS($ruleNr);
		} elsif ($type eq 'at'){
			validateAT($ruleNr);
		};
	}
	
	return;
}

#-------------------------------------------------------------
sub stripWS {
#-------------------------------------------------------------
	my $string = shift;
	$string =~ s/^\s+//gs;
	$string =~ s/\s+$//gs;
	return $string;
}

#-------------------------------------------------------------
sub validateAT {
#-------------------------------------------------------------
	my $ruleNr = shift;

	return();
}

#-------------------------------------------------------------
sub validateCSS {
#-------------------------------------------------------------
	my $ruleNr = shift;
	my $selector = $CSS->{'rules'}->[$ruleNr]->{'selector'};
	my $declarations = $CSS->{'rules'}->[$ruleNr]->{'declarationblock'};
	my $line = $CSS->{'rules'}->[$ruleNr]->{'line'};
	my $inComment = 0;
	my $inValue = 0;
	my $declarationNr = 0;
	my $string = "";
	
	my $length = length($declarations);
	#forced to use c-style for loop, need to be able to modify $i
	for ( my $i = 0; $i < $length; $i++ ) {
		my $chr = substr $declarations, $i, 1;
		#line counter
		if ( $chr eq "\n" ) { 
			$line++;
			$string .= $chr;
		}
		#comment start
		elsif ( $chr eq "/" ) {
			my $chrNext = substr $declarations, $i+1, 1;
			if ( $chrNext eq '*' ) {
				$inComment = 1;
				message(" line: $line \tstart of comment", 7);				
			} else {
				$string .= $chr;
			}			
		}
		#comment end
		elsif ( $comment and $chr eq '*' ) {
			my $chrNext = substr $declarations, $i+1, 1;
			if ( $chrNext eq '/' ) {
				$inComment = 0;
				say "pos:  $i";
				$i++;
				message(" line: $line \t end of comment", 7);				
			}		
		}
		elsif ( $inComment ) {
			#nothing to do - just suppress
		}
		elsif ($chr eq ':') {
			$declarationNr++;
			message("line: $line \tstart of declaration $declarationNr in rule $ruleNr", 7);
			my $property = stripWS($string);
			$CSS->{'rules'}->[$ruleNr]->{'declarations'}->[$declarationNr]->{'property'} = $property;
			$string = "";
			$inValue = 1;
		}
		elsif ($inValue and $chr eq ";") {
			message("line: $line \t end of declaration $declarationNr in rule $ruleNr", 7);
			my $value = stripWS($string);
			$CSS->{'rules'}->[$ruleNr]->{'declarations'}->[$declarationNr]->{'value'} = $value;
			$string = "";
			$inValue = 0;			
		}
		elsif ($inValue and $chr eq ":") {
			
		}

	
	
	}
	return();
}