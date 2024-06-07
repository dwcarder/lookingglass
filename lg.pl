#!/usr/bin/perl -w

#==================================================================
#    L G  -  R T R  2 .  C G I
#
#    Looking Glass tool.
#	 This code has the following lineage (that I know of):
#
#    - Inspired by DIGEX, and the Looking Glass by Ed Kern, ejk@digex.net
#    - Rewritten by Jesper Skriver, jesper@skriver.dk (circa 2000)
#	   http://www.nanog.org/mailinglist/mailarchives/old_archive/2000-11/msg00551.html
#
#    - Initially Adapted for use at UW for AANTS by Dale W. Carder and 
#       Dave Plonka, 2003-12-01
#    - Modified to include timestamping feature & html cleanup by Dale W. Carder
#    - Major Feature addition for diff counters by Dave Plonka, 2004-07-18
#    - Maintenance over 10+ years & a major refactoring by Charles Thomas
#    - Updated to use clogin instead of Skriver's cisco telnet function, plus
#      some code clean up & safety additions to make suitable for public use.
#	   This has differed far enough, that this is now version 2.0. 
#	   Dale W. Carder, 2014-03-27
#    - took out some UW library dependencies, 2024-05-06
#
#==================================================================


#==================================================================
#    U S E  /  R E Q U I R E
#==================================================================
use CGI qw(:standard);
use CGI::Carp ('fatalsToBrowser');   # Send any errors to the browser
use Config::General;
use HTTP::Request::Common qw(GET);
use JSON::XS;
use strict;
use Tie::IxHash;
#use Data::Dumper;  # only need this for debugging

use Regexp::Common;
use Regexp::IPv6 qw($IPv6_re);     # for testing IPv6 addresses


#==================================================================
#    P R O T O T Y P E S
#==================================================================
sub getParams();
sub validateParams();
sub processInput();
sub scrubResults($);
sub printResults($);
sub shellToRouter($$);
sub printForm();
sub printJavascriptCMDSelect();
sub checkLockFile($);
sub slog($$);
sub loadFile($$;$);


#==================================================================
#     C O N F I G
#==================================================================
my $config_file = '/usr/local/ns/etc/lg.config';

my %config;

{
   my ($result, $err) = loadFile(\%config, $config_file, 'cfg');
   die $err if $err;
}

$ENV{'PATH'}='/bin:/usr/bin';	# for timeoutcmd
$ENV{'HOME'}='/tmp';			# for clogin


#==================================================================
#    C G I  P A R A M S
#==================================================================
my $remotehost = $ENV{'REMOTE_ADDR'};
my $router = '';
my $query = '';
my $arg = '';
my $quiet = '';

my %valid_queries;
{
   my ($result, $err) = loadFile(\%valid_queries, $config{'lg_commands'});
   die $err if $err;
}

my %devices;
tie(%devices,'Tie::IxHash');

{
   my %tmp;
   my ($result, $err) = loadFile(\%tmp, $config{'lg_hosts'});
   die $err if $err;

   if ($config{'lg_hosts_unsorted'}) {
     foreach (keys %tmp) {
     	%{$devices{$_}} = %{$tmp{$_}};
     }
   } else {
     foreach (sort keys %tmp) {
        %{$devices{$_}} = %{$tmp{$_}};
     }
   }
}

#==================================================================
#     M A I N
#==================================================================

#===== Get CGI Obj
my $cgi_obj = new CGI;
die "Unable to get CGI Obj!\n" unless ref($cgi_obj);

getParams();

#===== Print header
if ($quiet) {
   print "Content-type: text/plain\n\n";
} else {
   print "Content-type: text/html\n\n";
   print "<html>\n";
   print "<head>\n";
   print "<title>$config{'title'}</title>\n";
   print "</head>\n";
   print "<body>\n";
   print "<center><h1><a href=\"$ENV{'SCRIPT_NAME'}\">$config{'title'}</a></h1></center>\n";
}

   #print "<pre>";
   #print Dumper %ENV;
   #print "</pre>";


validateParams();

if ($router and $query) {	# it's a valid query
  processInput();
  checkLockFile($router);

  # run the command
  slog(5,"$remotehost running command \"$query $arg\" on $router");
  print "Issuing the command \"$query $arg\" to " if $config{'debug'};
  print "the router ".$router.".<br>\n" if $config{'debug'};
  my $cmd_result = shellToRouter($router, "$query $arg");
  $cmd_result = scrubResults($cmd_result);
  printResults($cmd_result);

} else {	# otherwise issue the form
  printJavascriptCMDSelect();
  printForm();
}

if (!$quiet) {
   print "<hr>\n";
   print "<a href=\"$ENV{'SCRIPT_NAME'}\">$config{'title'}</a> operated by $config{'operator'}<br>\n";
   print "Network Operations Center: $config{'noc_phone'} or email $config{'noc_email'}<br>\n";
   print "</body>\n";
   print "</html>\n";
}

exit(0);


######################### BEGIN SUBROUTINES ####################

sub scrubResults($) {
   my ($result) = (@_);
   my $new_result = '';
   if (defined($result)) {
   foreach my $line (split (/\n/, $result)) {
     chop $line;
     if ($line =~ m/\s+quit\s*$/) {
        # skip to hide juniper username
     } else {
	# $new_result .= "test-'$line'\n";
	$new_result .= $line . "\n";
     }
   }
   }
   return $new_result;
}
  

sub printJavascriptCMDSelect() {
	# spit out the javascript that specifies what commands are appropriate
	# for each device class

	print "<script type=\"text/javascript\"><!--\n";
	print "function displayCommands(deviceclass) {\n";
	print "var container = document.getElementById(\"commandselect\");\n";

	foreach my $cmd_set (keys %valid_queries) {
		print "if (deviceclass == '$cmd_set') {\n";
		print "container.innerHTML = \"";
		foreach my $cmd (sort keys %{$valid_queries{$cmd_set}}) {
			print "<dd><input type='radio' name='query' value='$cmd'>$cmd";
		}
		print "\"";
		print "\n}";
	}

	print "\n}";
	print qq~//--></script>~;
	print "\n";

}

sub getParams() {
  # read in values from cgi
  if (param('router')){ $router = param('router');}
  if (param('query')){ $query = param('query');}
  if (param('arg')){ $arg = param('arg');}
  if (param('quiet')){ $quiet = param('quiet');}
} # end of getParams()


sub validateParams() {
  # untaint the parameters

  if ($arg) {
    my $msg = "$remotehost query='$query' sent illegal value in parameter 'arg'.  Value was '$arg'";

    #die $arg;
    if ($query eq 'show route') {
    	if ($arg =~ m%aspath-regex%) {
	   $msg = "Sorry, this combination of query and arg is not allowed";
	   goto ARG_BAD;
	}
    }

    if ($query eq 'show firewall filter') {
      if ($arg eq '__flowspec_default_inet__') {
        goto ARG_OK;
      }
    } elsif ($arg =~ m%^($RE{net}{IPv4}/\d+)$% || $arg =~ m%^$IPv6_re/\d+$% || $arg =~ m/^([\.\/0-9a-zA-Z- |?.:_]+)$/) {
      $arg = $1;
      goto ARG_OK;
    }

    ARG_BAD:
    slog(4,$msg);
    die($msg);
  }

  ARG_OK:

  if ($query) {
    if ($query =~ m/^([0-9a-zA-Z- ]+)$/) {
      $query = $1;
    } else {
      my $msg = "$remotehost sent illegal value in parameter 'query'.  Value was '$query'";
      slog(4,$msg);
      die($msg);
    }
  }

  if ($router) {
    if ($router =~ m/^([0-9a-zA-Z-.]+)$/) {
      $router = $1;
    } else {
      my $msg = "$remotehost sent illegal value in parameter 'router'.  Value was '$router'";
      slog(4,$msg);
      die($msg);
    }
  }
} # end of validateParams()


sub processInput() {
	# sanity checking

  print "Checking if \"".$router."\" is a valid router<br>\n" if $config{'debug'};

  unless (defined($devices{$router})) {
    printResults("Not a valid router.\n");
	slog(6,"$remotehost not a valid router");
	exit();
  }

  print "Checking if valid query<br>\n" if $config{'debug'};

  my $devclass = $devices{$router}{'deviceclass'};

  unless (defined($valid_queries{$devclass}{$query})) {
    printResults("Not a valid command.\n");
	slog(6,"$remotehost not a valid command");
	exit();
  }

  # these commands do not get an arguement
  if ($valid_queries{$devclass}{$query} == 0) {
	$arg='';
  }

  # these commands must have an arguement
  if ($valid_queries{$devclass}{$query} == 2) {
	unless (defined($arg) && $arg =~ /^\S/ ) {
		printResults("This command must take an argument.\n");
		exit();
	}
  }

  #wopat removed \? 2018-03-23
  #if ( $arg and $arg !~ /^[0-9a-zA-Z\.\s\-\_\s\$\*\+\/\\:|\?"]*$/ ) {
  if ( $arg and $arg !~ /^[0-9a-zA-Z\.\s\-\_\s\$\*\+\/\\:|"]*$/ ) {
    print "Checking characters in arg <br>\n" if $config{'debug'};
    printResults("Invalid characters in argument.\n");
	slog(6,"$remotehost invalid characters in argument.");
	exit();
  }

  # if there is a pipe, then you can't do these special things
  if (defined($arg) and $arg =~ m/\|/) {
		if ($arg =~ m/(save|request|file| script|xargs|append|redirect|tee)/i) {
			printResults("Invalid command in argument.\n");
			slog(6,"$remotehost invalid command in argument.");
			exit();
		}
  }

  # special hack to prevent pings that can go on forever
  my $pingarg;
  if ($devclass =~ m/(junos|ios-xr)/) { 
	$pingarg = "count"; 

	if ($query =~ m/ping/) {
		if (!defined($arg) || (defined($arg) && $arg !~ m/${pingarg} \d+/)) {
			if ($devclass =~ m/(junos)/) {
				$arg = "${pingarg} 5 " . $arg;
			} elsif ($devclass =~ m/(ios-xr)/) {
				$arg = $arg . " ${pingarg} 5";
			}
		} else {
			if ($arg =~ m/${pingarg} (\d+)/) {
				if ($1 > 10) {
					$arg =~ s/${pingarg} \d+/${pingarg} 10/;
				}
			}
		}
	}
  }

} # end of processInput()


sub printResults($) {
  my $cmd_result = shift;

  if (!$quiet) {
     print "<center><b>Device:</b> ";
     if (!(defined($devices{$router}{'description'}))) {
	slog (1, "No description for device='$router'");
     }

     print $devices{$router}{'description'}."<br>\n";
     print "<b>Query:</b> $query<br>\n";

     if ( defined($arg) and $arg ne '' ) {
    	print "<b>Argument:</b> ".$arg."\n";
     }
     print "</center>\n<br><p>\n</font><pre>\n";
  }

  print $cmd_result;
  print "</pre>\n" if !$quiet;

} # end of printResults()


sub shellToRouter($$)
{

  my $router = shift or
    die "Must supply router to shellToRouter()!\n";
  my $cmd = shift or 
    die "Must supply command to shellToRouter()!\n";

  my $clogin_cmd = "$config{'Timeoutcmd'} $devices{$router}{'clogin'} $config{'Clogin_opts'} -c \"$cmd\" $router |";

  slog(5, "$clogin_cmd");

  my @cloginoutput = do {
	  open(CLOGIN,$clogin_cmd) 
		or slog(4,"Can't call clogin: $!") && die("Can't call connect to the device.");
	  <CLOGIN>;
  };

  # Replace any HMTL-ish chars unless we are in text/plain mode
  if (!$quiet) {
    my @new_clogin_output;
    foreach my $line (@cloginoutput) {
	$line =~ s/[\>]/\&gt\;/g;  # > becomes &gt;
        $line =~ s/[\<]/\&lt\;/g;  # < becomes &lt;
	push (@new_clogin_output, $line);
    }
    @cloginoutput = @new_clogin_output;
  }

	close(CLOGIN);
	if ($config{'debug'}) { 
	   print "<pre>";
	   print @cloginoutput; 
	   print "</pre>";
	   
	}
	my $result;

	# try to only return the results from the command being issued and
	# not the login banner, etc.
	my $command_issued=0;
	my $counter=0;	# this is a hack for IOS-XR and the command not being echoed

	# this works around clogin prompt wraps
	my $short_cmd = substr($cmd, 0, 40);

	print "looking for '$short_cmd'\n" if $config{'debug'};

	foreach my $line (@cloginoutput) {
		#$result = $result . "$cmd    $command_issued  $counter     \n";

		# this doesn't work and is matching other things
		# 
		# Mar 19 09:20:34 coulomb lg.pl[28988]: [warning]: I Found an error:   Link-level type: Flexible-Ethernet, MTU: 9192, Speed: 100Gbps, BPDU Error: None, Loopback: Disabled, Source filtering: Disabled,#015
		# Mar 19 09:22:09 coulomb lg.pl[29599]: [warning]: I Found an error:   Link-level type: Flexible-Ethernet, MTU: 9192, Speed: 30Gbps, BPDU Error: None, MAC-REWRITE Error: None, Loopback: Disabled,#015
		#if ($line =~ m/error:/i) {
		#	slog(4,"I found an error: $line");

		# the SSH@hostname syntax is to all netiron/foundry/brocade/extreme/ruckus
		# while trying to squelch all other artifacts from the device interaction
		# this also may be a little bit too greedy..
		if ($line =~ m/(ssh|password|spawn)/i && $line !~ /(^SSH\@)/ ) {
			next; 
		} elsif ( $line =~ m/^term width 0/) {	
			$counter++;
		} elsif ($line =~ m/exit/) {
			$command_issued=0;
			$counter=0;
		} 

		if ($command_issued || $counter > 3) {
			$result = $result . $line;
		}
		if ($line =~ m/\Q${short_cmd}\E/ ) {
			$command_issued=1;
		}
		if ($counter) { $counter++; }
	}
	return($result);

} # end of shellToRouter()


sub printForm() {

  print "<form method=\"GET\">\n";
  print "<table align=\"center\" cellpadding=\"10\" cellspacing=\"10\">";

  print "<tr><td valign=\"top\" bgcolor=\"#EEEEEE\" >\n";

  print "<h3>Device:</h3>\n";
  my $numitems = scalar(keys %devices);
  if ($numitems > 20) { $numitems = 20; }

  print "<SELECT name=\"router\" size=\"$numitems\" onchange=\"displayCommands(this.options[this.selectedIndex].getAttribute('deviceclass'))\">\n";
  foreach my $dev (keys %devices) {
      my $devclass = $devices{$dev}{'deviceclass'};
      if (!$devclass) {
	my $msg = "Sorry, no device class for device='$dev'";
	slog (3, $msg);
	next;
	# die $msg;
      }
      print "<OPTION deviceclass=\"$devclass\"";
      print " selected=true" if ($router && $router eq $dev); 
      print " VALUE=\"$dev\">";
      print $devices{$dev}{'description'}."</OPTION>\n";
  }
  print "</SELECT>\n";

  print "</td><td valign=\"top\" bgcolor=\"#EEEEEE\"><h3>Query:</h3>\n";

  print "<div id=\"commandselect\">\n&nbsp;";
  print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\n";
  print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\n";
  print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\n";
  print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\n";
  print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\n";
  print "</div>\n";

  {
  my $htmltext=<<EOM;
<tr><td colspan=2 valign=\"top\" bgcolor=\"#EEEEEE\">
<font size=3><b>Arguments (optional):</b></font>
<p>
&nbsp; &nbsp;<input name=\"arg\" size=64>
<p>
<input type="submit" value="Submit"> | <input type="reset" value="Reset">
<p>
</td></tr>
</form></td></tr></table>
<br><br>

EOM

  print $htmltext;
}

} # end of printForm()


sub checkLockFile($) {
	# Rewritten for UW's router looking glass, Dale W. Carder 2014-02-26
	#
	# Credit for this function goes to checkLastRun() from GRNOC's proxy-output.cgi:
	#   Author:
	#     Clinton Wolfe, clwolfe@indiana.edu, May 2001
	#     Somewhat based on the original Abilene Router Proxy by Mark Meiss
	#     Additional changes by Grover Browning, February 2002. 
	#
	#   Copyright:
	#     Copyright (c) 2001 the Trustees of Indiana University.
	#     All rights reserved.

	my $rtr = shift;
	my $rtr_file = $config{'tmp_dir'} .'/'. $config{'tmp_scriptname'} .'_'. $rtr . '.lastused';

	# only allow 1 query per 2 seconds, (note: -M is in days)
	if ((-e $rtr_file) && (-M $rtr_file < 2/86400)) {
		printResults("Access to router $rtr is rate limited, please try again later.");
		slog(4,"$remotehost - access to router $rtr is rate limited");
		exit();
	} else {
		system('/bin/touch',$rtr_file);
		if ($? == -1) {
			slog(4,"$remotehost - Can't use tmp file: $rtr_file $!");
			exit();
		}
	}

}

sub slog($$) {
    # parameters:
    #   syslog severity (1-7)
    #   log message (string)

    # if you want to send stuff to syslog, put something here
    return(1);

}

sub loadFile($$;$) {
    my $hash = shift;
    my $file = shift;
    my $type = shift;
    my $fh;

    die ("Couldn't read file '$file'" )  if (!(stat($file)));

    my $fhresult = open($fh, $file);
    if (!$fhresult) {
        die("loadFile $file failed: $!");
    }

    my $content = do { local $/; <$fh> };
    close $fh;

    if ( $type eq 'cfg' ) {
        %$hash = Config::General::ParseConfig(-String => $content, -SplitPolicy => "equalsign", CComments => 0);

    } else {  # type is json

        my $json_obj = JSON::XS->new->utf8;
        my $valid_json = eval { %$hash = %{$json_obj->decode($content)}; 1 };
        unless($valid_json) {
            slog(1, "file='$file' return invalid JSON");
            die("invalid json in $file");
        }
    }
    return(1);
}

