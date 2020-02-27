#*****************************************************************************
#*                           XppCssChecker   			                     *
#*            this software is licensed under the MIT license                *
#*****************************************************************************
# V00.01 - 2020/02/16 - start
# V00.02 - 2020/02/27 - first version
our $Version = "00.02";

use strict;
use warnings;
use 5.028;

use Getopt::Long;
use Path::Tiny;
use XML::Simple;

#can comment this out for production version
use Data::Dumper;

#some variables
my $Css;
my $Config;
my $Debug = 5;
my $ErrorNr = 0;
my $Properties;
my $ProblemNr = 0;
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
if ($ProblemNr) {
	printProblems();
	exit(-1);
}
#parse css rules properties and values
scanCssRules();

#printErrors();
#printWarnings();
printProblems();

exit();

#=============================================================
#  FUNCTIONS
#=============================================================
#-------------------------------------------------------------
sub addError {
#-------------------------------------------------------------
	my $lineNr = shift;
	my $error = shift;
	#$ErrorNr++;
	#$Rules->{'errors'}->[$ErrorNr] = "ERROR line: $lineNr - $error";
	$ProblemNr++;
	$Rules->{'problems'}->[$ProblemNr] = "ERROR line: $lineNr - $error";

	return;
}
#-------------------------------------------------------------
sub addWarning {
#-------------------------------------------------------------
	my $lineNr = shift;
	my $warning = shift;
	#$WarningNr++;
	#$Rules->{'warnings'}->[$WarningNr] = "WARNING line: $lineNr - $warning";
	$ProblemNr++;
	$Rules->{'problems'}->[$ProblemNr] = "WARNING line: $lineNr - $warning";

	return;
}

#-------------------------------------------------------------
sub checkPropertyValue {
#-------------------------------------------------------------
	my $lineNr = shift;
	my $property = shift;
	my $value = shift;
	if ( exists $Properties->{$property} ) {
		my $short = $Properties->{$property}->{'short'};
		my $long = $Properties->{$property}->{'long'};
		unless ($value =~ m/^$long$/) {
			addError($lineNr, "in property '$property' the value '$value' did not parse pattern '$short'");
		}
	} else {
		addWarning($lineNr, "unsupported property '$property'");
	}
	return();
}

#-------------------------------------------------------------
sub checkDeclarations {
#-------------------------------------------------------------
	my $ruleNr = shift;
	my $declarations = shift;
	my $declarationsTot = scalar(@{$declarations}) - 1;
	for my $declarationNr (1 .. $declarationsTot) {
		message(" CSS rule $ruleNr", 8);
		my $lineNr = $declarations->[$declarationNr]->{'lineNr'};
		$lineNr++;
		my $property = $declarations->[$declarationNr]->{'property'};
		my $value = $declarations->[$declarationNr]->{'value'};
		message("  property: $property", 8);
		message("  value: $value", 8);
		checkPropertyValue($lineNr, $property, $value);
		
	}
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
	message("-reading config file",1);
	$Config = eval { XMLin($config->canonpath, KeyAttr => ['name']) };
	if ($@) {
		message("config file error: file corrupt\n  see: <$config>\n$@\n");
		exit(-1);
	}
	if ($Debug == 9) {
		print Dumper($Config);
	}
	
	#create @Properties
	foreach my $property ( keys %{$Config->{'properties'}->{'property'}} ) {
		my $value = $Config->{'properties'}->{'property'}->{$property}->{'value'};
		$Properties->{$property}->{'short'} = $value;
		#expand recursively
		1 while ( $value =~ s/%([\w-]+)%/propertyExpand($1)/e );
		#store
		$Properties->{$property}->{'long'} = $value;
		message(" property: $property - value: $value", 9);
	}
	my $properties = scalar(keys %{$Properties});
	message(" $properties CSS properties found in config file", 1);
	return($file);
}

#-------------------------------------------------------------
sub propertyExpand {
#-------------------------------------------------------------
	my $value = shift;
	if ( exists $Config->{'values'}->{'value'}->{$value} ) {
		return( $Config->{'values'}->{'value'}->{$value}->{'pattern'} )
	} else {
		message("config file error: pattern for value '$value' is not defined",0);
		exit(-1);
	}

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
	return unless ( exists $Rules->{'at'});
	my $rules = scalar(@{$Rules->{'at'}}) - 1;
	message(" $rules AT rules found", 5);
	if ($Debug >= 8) {
		for my $ruleNr ( 1 .. $rules ) {
			my $statement = stripWS($Rules->{'at'}->[$ruleNr]->{'rule'});
			my $selector = stripWS($Rules->{'css'}->[$ruleNr]->{'selector'});
			message("  ATrule $ruleNr", $Debug);
			message("   statement:  $statement", $Debug);
		}	
	}
	
	return;
}


#-------------------------------------------------------------
sub printCssRules {
#-------------------------------------------------------------
	return unless ( exists $Rules->{'css'});
	my $rules = scalar(@{$Rules->{'css'}}) - 1;
	message(" $rules CSS rules found", 5);
	if ($Debug >= 8) {
		for my $ruleNr ( 1 .. $rules ) {
			my $declarations = stripWS($Rules->{'css'}->[$ruleNr]->{'rule'});
			my $selector = stripWS($Rules->{'css'}->[$ruleNr]->{'selector'});
			message("  CSS rule $ruleNr", $Debug);
			message("   selector:  $selector", $Debug);
			message("   declarations:  $declarations", $Debug);
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
sub printProblems {
#-------------------------------------------------------------
	if ($ProblemNr) {
		message("** $ProblemNr problems found: ", 2);
		for my $error ( 1 .. $ProblemNr ) {
			message($Rules->{'problems'}->[$error], 2);
		}
	} else {
		message("No problems found", 2);
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
sub readFile {
#-------------------------------------------------------------
	my $file = path(shift);
	message("-reading CSS file $file",1);
	my $css = $file->slurp_utf8;

	return($css);
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
		my $declarations = $Rules->{'css'}->[$ruleNr]->{'rule'};
		scanCssDeclarations($declarations, $ruleNr);
		checkDeclarations($ruleNr, $Rules->{'css'}->[$ruleNr]->{'declarations'});
	}
	
	return;
}

#-------------------------------------------------------------
sub scanCssDeclarations {
#-------------------------------------------------------------
	my $css = shift;
	my $ruleNr = shift;
	my $declarationNr = 0;
	my $lineNr = $Rules->{'css'}->[$ruleNr]->{'lineNr'};
	my $inQuote = 0;
	my $inProperty = 1;
	my $inValue = 0;
	my $string = "";
	#; at end of block is optional
	$css .= ';' unless ($css =~ m/;$/);
	#scan
	my $length = length($css);
	#C-style for loop 
	for ( my $i = 0; $i < $length; $i++ ) {
		my $chr = substr $css, $i, 1;
		#line counter
		if ( $chr eq "\n" ) { 
			$lineNr++;
			$string .= $chr;
		}
		#quoted strings
		elsif ( $inQuote and $chr eq '"' ) {
			$inQuote = 0;
			$string .= $chr;			
		}
		elsif ( $chr eq '"' ) {
			$inQuote = 1;
			$string .= $chr;					
		}
		elsif ( $inQuote ) {
			$string .= $chr;
			if (length($string) > 1024) {
				addWarning($lineNr, "string too long - end quote might be missing");
			}
		}
		elsif ($chr eq ':' and $inValue) {
			addError($lineNr, "syntax error - ':' found in value definition: $string");
		}
		elsif ($chr eq ':') {
			$declarationNr++;
			$Rules->{'css'}->[$ruleNr]->{'declarations'}->[$declarationNr]->{'property'} = stripWS($string);
			$Rules->{'css'}->[$ruleNr]->{'declarations'}->[$declarationNr]->{'lineNr'} = $lineNr;
			$inValue = 1;
			$inProperty = 0;
			$string = "";
		}
		elsif ($chr eq ';' and $inProperty) {
			addError($lineNr, "syntax error - ';' found in property definition: $string");
		}
		elsif ($chr eq ';') {
			$Rules->{'css'}->[$ruleNr]->{'declarations'}->[$declarationNr]->{'value'} = stripWS($string);
			$inProperty = 1;
			$inValue = 0;
			$string = "";
		}
		else {
			$string .= $chr;
		}		
	}
	if ($inValue) {
		addError($lineNr, "syntax error - missing ';' found in definition: $string");
	}

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
				message(" line: $lineNr - start of comment", 7);				
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
				message("  line: $lineNr - end of comment", 7);				
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
				addWarning($lineNr, "string too long - end quote might be missing");
			}
		}
		#at and css rules: illegal start
		elsif ( $inRule and ($chr eq '@' or $chr eq '{') ) {
			my $ruleLineNr = $Rules->{$inRule}->[$currentRuleNr]->{'lineNr'};
			addError($ruleLineNr, "open statement not ended");
			addError($lineNr, "illegal start of statement found $chr");
		}
		#at-rule: start
		elsif ( $chr eq '@' ) {
			$atRuleNr++;
			$currentRuleNr = $atRuleNr;
			$inRule = 'at';
			message(" line: $lineNr - start of at-rule $currentRuleNr", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'lineNr'} = $lineNr;
			$terminator = ';';
			$string = "";
		} 
		#css rule: start
		elsif ( $chr eq "{" ) {
			$cssRuleNr++;
			$currentRuleNr = $cssRuleNr;
			$inRule = 'css';
			message(" line: $lineNr - start of css-rule $currentRuleNr", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'lineNr'} = $lineNr;
			$Rules->{$inRule}->[$currentRuleNr]->{'selector'} = $string;
			$terminator = '}';
			$string = "";
		} 
		#at and css rules: legal end
		elsif ( $inRule and ($chr eq $terminator) ) {
			message("  line: $lineNr - end of ${inRule}-rule $currentRuleNr", 7);
			$Rules->{$inRule}->[$currentRuleNr]->{'rule'} = stripWS($string);
			$string = "";
			$terminator = ";|}";
			$inRule = "";
		}
		#at and css rules: illegal end
		elsif ( $chr =~ m/$terminator/ ) {
			addError($lineNr, "illegal end of statement found $chr");
		}
		#normal character
		else {
			$string .= $chr;
		}
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


