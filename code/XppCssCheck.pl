#*****************************************************************************
#*                           XppCssChecker   			                     *
#*            this software is licensed under the MIT license                *
#*****************************************************************************
# V00.01 - 2020/02/16 - start
our $Version = "00.01";

use strict;
use warnings;
use 5.028;

use Getopt::Long;
use Path::Tiny;
use XML::Simple;

#can comment this out for production version
use Data::Dumper;

#some variables
my $Config;
my $Debug = 5;
my $ErrorNr = 0;
my $Rules;
my $WarningNr = 0;

#=============================================================
#  MAIN
#=============================================================
umask 000;
my $file = preFlight();
my $css = readFile($file);
#scan and parse into rules
scanForRules($css);
printAtRules();
printCssRules();
#no need to dig any further - first resolve these errors
if ($ErrorNr) {
	printErrors();
	exit(-1);
}
#parse css rules properties and values
scanCssRules();

printErrors();
printWarnings();

exit();

#=============================================================
#  FUNCTIONS
#=============================================================
#-------------------------------------------------------------
sub addError {
#-------------------------------------------------------------
	my $lineNr = shift;
	my $error = shift;
	$ErrorNr++;
	$Rules->{'errors'}->[$ErrorNr] = "ERROR line: $lineNr - $error";

	return;
}
#-------------------------------------------------------------
sub addWarning {
#-------------------------------------------------------------
	my $lineNr = shift;
	my $warning = shift;
	$WarningNr++;
	$Rules->{'warnings'}->[$WarningNr] = "WARNING line: $lineNr - $warning";

	return;
}
#-------------------------------------------------------------
sub checkSelector {
#-------------------------------------------------------------
	my $selectors = stripWS(shift);
	my $ruleNr = shift;
	my $lineNr = $Rules->{'css'}->[$ruleNr]->{'lineNr'};
	my @selectors = split /\n/, $selectors;
	foreach (reverse @selectors) {
		my $selector = stripWS($_);
		my $selectorChecked = $selector;
		#remove valid pseudo elements
		$selectorChecked =~ s/::before|::after//gs;
		if ($selectorChecked =~ m/::/) {
			addError($lineNr, "illegal '::' separtor found, see: $selector");
		}
		if ($selectorChecked =~ s/:before|:after//gs) {
			addWarning($lineNr, "':before' or ':after' are deprecated, use '::before' or '::after' instead, see: '$selector'");
		}
		#remove valid pseudo selectors
		$selectorChecked =~ s/:first-child|:nth-child\(\[d\+n-*]+\)|:first-of-type|nth-of-type\(\[d\+n-*]+\)//gs;
		#remove namespace :
		$selectorChecked =~ s/\\://gs;
		if ($selectorChecked =~ m/:\w+/) {
			addWarning($lineNr, "unsupported pseudo-selector '$&', see: '$selector'");
		}
		if ($selectorChecked =~ m/"]/) {
			addWarning($lineNr, "do not use double quotes in selectors, see: '$selector'");
		}
		$lineNr--;
	}
	return($lineNr);
}

#-------------------------------------------------------------
sub message {
#-------------------------------------------------------------
	#level 0 = fatal error
	#level 1 = progress
	#level 2 = error
	#level 3 = warning
	#level 5 = info
	#level 8 = noisy
	#level 9 = debug
	my $mesg = shift;
	my $level = shift || 5;
	say $mesg if ($level <= $Debug);
	
	return;
}

#-------------------------------------------------------------
sub preFlight {
#-------------------------------------------------------------
	#start message
	my $prog = progName();
	message("$prog V:$Version",1);
	
	#prelim checks
	unless ( exists $ENV{'XYV_EXECS'} ) {
		message('This system is not set up to run XPP software', 0);
		exit(-1);
	}
	my $config = path($ENV{'XYV_EXECS'}, 'procs', 'config', $prog,  "${prog}_config.xml");
	unless ( $config->exists ) {
		message("This system is not set up to run this tool, config file is missing: $config", 0);
		exit(-1);
	}

	#command line options
	GetOptions('debug=i' => \$Debug) or printUsage($prog);
	my $noa = scalar(@ARGV);
	printUsage() if ( $noa > 1 );
	
	#input file?
	my $file = shift @ARGV;
	unless ( -r $file ) {
		message("could not read CSS file: $file", 1);
		exit(-1);
	}
	
	#read config file
	$Config = eval { XMLin($config) };
	if ($@) {
		message("config file error: file corrupt\n  see: <$config>\n$@\n");
		exit(-1);
	}
	if ($Debug == 9) {
		print Dumper($Config);
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
sub printAtRules {
#-------------------------------------------------------------
	my $rules = scalar(@{$Rules->{'at'}}) - 1;
	message(" $rules AT rules found", 5);
	if ($Debug >= 8) {
		for my $ruleNr ( 1 .. $rules ) {
			my $statement = stripWS($Rules->{'at'}->[$ruleNr]->{'rule'});
			my $selector = stripWS($Rules->{'css'}->[$ruleNr]->{'selector'});
			message("rule $ruleNr", $Debug);
			message(" statement:  $statement", $Debug);
		}	
	}
	
	return;
}


#-------------------------------------------------------------
sub printCssRules {
#-------------------------------------------------------------
	my $rules = scalar(@{$Rules->{'css'}}) - 1;
	message(" $rules CSS rules found", 5);
	if ($Debug >= 8) {
		for my $ruleNr ( 1 .. $rules ) {
			my $declarations = stripWS($Rules->{'css'}->[$ruleNr]->{'rule'});
			my $selector = stripWS($Rules->{'css'}->[$ruleNr]->{'selector'});
			message("rule $ruleNr", $Debug);
			message(" selector:  $selector", $Debug);
			message(" declarations:  $declarations", $Debug);
		}	
	}
	
	return;
}

#-------------------------------------------------------------
sub printErrors {
#-------------------------------------------------------------
	if ($ErrorNr) {
		message("** $ErrorNr errors found: ", 2);
	} else {
		message(">No errors found")
	}
	for my $error ( 1 .. $ErrorNr ) {
		message($Rules->{'errors'}->[$error], 2);
	}
	
	return;
}

#-------------------------------------------------------------
sub printWarnings {
#-------------------------------------------------------------
	if ($WarningNr) {
		message("** $WarningNr warnings found: ", 2);
	}
	for my $error ( 1 .. $WarningNr ) {
		message($Rules->{'warnings'}->[$error], 2);
	}
	
	return;
}

#-------------------------------------------------------------
sub readConfig {
#-------------------------------------------------------------
	
}
#-------------------------------------------------------------
sub readFile {
#-------------------------------------------------------------
	my $file = path(shift);
	message("-reading CSS file $file",1);
	my $css = $file->slurp_utf8;

	return($css);
}

#-------------------------------------------------------------
sub scanForRules {
#-------------------------------------------------------------
	message("-scanning for rules",1);
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
	my $inQuote = 0;

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
		#quoted strings
		elsif ( $inQuote and $chr eq '"' ) {
			$inQuote = 0;
			$string .= $chr;			
		}
		elsif ( $inRule and $chr eq '"' ) {
			$inQuote = 1;
			$string .= $chr;					
		}
		elsif ( $inQuote ) {
			$string .= $chr;
			if (length($string) > 1024) {
				$WarningNr++;
				$Rules->{'warnings'}->[$WarningNr] = "WARNING line: $lineNr - string too long - end quote might be missing";
			}
		}
		#at and css rules: illegal start
		elsif ( $inRule and ($chr eq '@' or $chr eq '{') ) {
			$ErrorNr++;
			my $ruleLineNr = $Rules->{$inRule}->[$currentRuleNr]->{'lineNr'};
			$Rules->{'errors'}->[$ErrorNr] = "ERROR line: $ruleLineNr - open statement not ended";
			
			$ErrorNr++;
			$Rules->{'errors'}->[$ErrorNr] = "ERROR line: $lineNr - illegal start of statement found $chr";
		}
		#at-rule: start
		elsif ( $chr eq '@' ) {
			$atRuleNr++;
			$currentRuleNr = $atRuleNr;
			$inRule = 'at';
			message(" line: $lineNr \tstart of at-rule $currentRuleNr", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'lineNr'} = $lineNr;
			$terminator = ';';
			$string = "";
		} 
		#css rule: start
		elsif ( $chr eq "{" ) {
			$cssRuleNr++;
			$currentRuleNr = $cssRuleNr;
			$inRule = 'css';
			message(" line: $lineNr \tstart of css-rule $currentRuleNr", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'lineNr'} = $lineNr;
			$Rules->{$inRule}->[$currentRuleNr]->{'selector'} = $string;
			$terminator = '}';
			$string = "";
		} 
		#at and css rules: legal end
		elsif ( $inRule and ($chr eq $terminator) ) {
			message(" line: $lineNr \t end of ${inRule}-rule $currentRuleNr", 7);
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
sub scanCssRules {
#-------------------------------------------------------------
	my $rules = scalar(@{$Rules->{'css'}}) - 1;
	return if ($rules < 0);
	message("-parsing CSS rules",1);
	for my $ruleNr (1 .. $rules) {
		my $selector = $Rules->{'css'}->[$ruleNr]->{'selector'};
		checkSelector($selector, $ruleNr);
		my $rule = $Rules->{'css'}->[$ruleNr]->{'rule'};
	
	
	}
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

