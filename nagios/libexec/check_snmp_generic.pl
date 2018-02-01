#!/usr/bin/perl -w
#
# check_snmp_generic  v1.0 - Nagios(r) and Icinga monitor plugin
#
# Copyright (c) 2009 Michael Stahn, <m1kes (at) web.de>
#
# This is a generic SNMP-Check-Plugin for Ngsio/Icinga.
# For details call: check_snmp_generic.pl -h
#

use strict;
use Getopt::Long;
use Fcntl ':flock';
use IO::Handle;

my $name		= 'check_snmp_generic.pl';
my $version		= '1.0';

my $do_verbose		= undef;
my $do_version		= undef;
my $do_help		= undef;
my $do_delta		= undef;
my $do_relative		= undef;

my $HOST		= "127.0.0.1";			# default is localhost
my $DESCRIPTION		= "Current Value:";
my $LABEL		= "LABEL";
my $UOM			= "";
my $WARNING		= undef;			# warning as real value
my $CRITICAL		= undef;			# critical as real value
my $CURRENT_REAL	= "";
my $CURRENT_PERCENT	= undef;
my $MIN			= "";
my $MAX			= "";

my $STR_CMPR		= undef;
my $DIVIDER		= 1;
my $REGEX	= undef;
my $TABLE_COLS	= undef;

my $NET_SNMP_OPTS = "-OqvU";			# standard options, only value/no OID or units
my $NET_SNMP_OPTS_ADD = undef;			# user defined options
my $SNMP_CMD	= "snmpget";
my $TMP_VALUES_FILE	= "/tmp/SNMP_MONITORING_VALUES_TMP.txt";
my $TMP_VALUE_VARNAME	= undef;

my %STATUS_CODE = (	'OK' => '0',
			'WARNING'  => '1',
			'CRITICAL' => '2',
			'UNKNOWN' => '3' );

#############
# FUNCTIONS #
#############
				# parameter:
sub print_version();
sub print_usage();
sub print_help();
sub verb($);
sub round($$);			# number, places after "."
sub get_diff_over_time($$);	# varname, value
sub do_exit($;$);		# [OK|WARNING..], [new Description|original Description]


sub print_version() { print "$name version: $version\n"; }
sub print_usage() {

print <<EOT;
USAGE:

$name \\
[-H host] [-d descr] [-l label] [-u unit] \\
[-w warnval -c criticalval [-min minval] [-max maxval] [-D divider] [-r] [-e] | -S ] \\
[-T "1 2 3"] [-R regex] [-N "-opt1 arg1 -opt2 arg2"] OID1 OID2..


EOT
}

sub print_help() {

print_usage();
print <<EOT;
This is a generic SNMP-Check-Plugin for Nagios/Icinga.
The output of this Plugin is 100% Nagios-Plugin-Standard compatible, which means its output
will look like this:

<[OK|WARNING|CRITICAL|UNKNOWN]> <description> <currentvalue> | <label>=<currentvalue><uom>;<warn>;<critical>;<min>;<max>

This Plugin checks the current value for 1 or more OID-values. WARN and CRITICAL is given by % or
absolute value, based on --relative option.  WARN = 10(%) means inklusive 10(%) up to critical
(exklusive). String-comparing can be done by specifying a Regex with --regex.
This Plugin will check autmatically if the given WARN/CRITICAL-values are down or upraising.
An example for a upraising definition is Disk-space-useage: -w 80 -c 100.
If the needed value resides in a table, this can be done by combining --table and --regex
to select specific columns and search der right row. On numeric-compare this regex MUST
capture a numeric value!

This Addon uses Net-SNMP v5.5, which should be set up correctly (config-file configuration needed)
Additional Parameters can be given by the -N Parameter.
NOTE: Net-SNMP chaches values for 5 sec as default, faster requests do need an explicit change
of this behaviour.

Features:
	Compare numerical and string values (see -S)
	Combine multiple numerical values by giving 100% and x%-OID (WARN/CRITICAL will be interpreted as %) (see -r)
	Sum up multiple values (see -r)
	Search specific values in a table (see -T)
	Compare numerical differences over time (see -e)
	Adjust numerical values to make them more compareable (see -D)
	Use every encryption-Method available (V1-3) (see SNMP config-file)
Limitations:
	Extended Range-Definitions like :10 or \@10 are not supported.
	No Multiple-output values (eg Load over 1/5/15 Min together)
	No combination of Table-values with anything else


============
= EXAMPLES =
============

Absolute value measurement:
---------------------------
# Number of users:
        $name -d "Number of Users:" -l "Users" -w 20 -c 40 1.3.6.1.2.1.25.1.5.0
# Number of processes:
        $name -d "Number of proccesses:" -l proccesses -w 200 -c 250 1.3.6.1.2.1.25.1.6.0
# Search Process:
        $name -d "process init state" -S -R "init (running|runnable)" -T "2 7" 1.3.6.1.2.1.25.4.2
# 1-Minute AVG Load:
        $name -d "Load 1 min:" -w 1.0 -c 2.0 1.3.6.1.4.1.2021.10.1.3.1
# 5-Minute AVG Load:
        $name -d "Load 5 min:" -w 0.9 -c 1.2 1.3.6.1.4.1.2021.10.1.3.2
# 15-Minute AVG Load:
        $name -d "Load 15 min:" -w 0.7 -c 1.0 1.3.6.1.4.1.2021.10.1.3.3
# Interface up:
        $name -d "Intferface wlan0 state" -l "iface_up" -T "2 8" -S -R "wlan0 up" 1.3.6.1.2.1.2.2
# IP datagrams received (#/s)
        $name -d "IP datagrams in:" -l ip_in -w 400 -c 600 -e 1.3.6.1.2.1.4.3.0
# IP datagrams out (#/s)
        $name -d "IP datagrams out (#/s):" -l ip_out -w 400 -c 600 -e 1.3.6.1.2.1.4.10.0
# IP datagrams discarded (error)
        $name -d "IP datagrams errors (out)" -l ip_out -w 400 -c 600 -e 1.3.6.1.2.1.4.4.0 1.3.6.1.2.1.4.5.0

# TCP-Connections (established + close-wait):
        $name -d "TCP Connections:" -l tcpcon -w 200 -c 250  1.3.6.1.2.1.6.9.0
# TCP-Active open (#/s) (CLOSED -> SYN-SENT):
        $name -d "TCP active open (x/s):" -l tcpcon -w 100 -c 150 -e 1.3.6.1.2.1.6.5.0
# TCP-passive open (#/s) (SYN-RCVD -> LISTEN):
        $name -d "TCP passive open (x/s):" -l tcpcon -w 100 -c 150 -e 1.3.6.1.2.1.6.5.0
# TCP-segments received (#/s):
        $name -d "TCP segment received:" -l tcpcon -w 200 -c 250 -e 1.3.6.1.2.1.6.10.0
# TCP-segments send (#/s):
        $name -d "TCP segment sent:" -l tcpcon -w 200 -c 250 -e 1.3.6.1.2.1.6.11.0
# TCP-segments errors (#/s)  (in):
        $name -d "TCP segment error (in):" -l tcpcon -w 200 -c 250 -e 1.3.6.1.2.1.6.14.0

# UDP-Datagrams in (#/s):
        $name -d "UDP Datagrams in:" -l tcpcon -w 200 -c 250 -e 1.3.6.1.2.1.7.1.0
# UDP-Datagrams out (#/s):
        $name -d "UDP Datagrams out:" -l tcpcon -w 200 -c 250 -e 1.3.6.1.2.1.7.4.0
# UDP-Datagram errors  (#/s):
        $name -d "UDP Datagram errors (in):" -l tcpcon -w 200 -c 250 -e 1.3.6.1.2.1.7.3.0

# Output Traffic in KB/s:
        $name -d "Output traffic:" -l traffic -u KB -w 400 -c 800 -T "2 16" -R "wlan0 ([0-9]+)" -e -D 1000 1.3.6.1.2.1.2.2
# Input Traffic in KB/s:
        $name -d "Input traffic:" -l traffic -u KB -w 400 -c 800 -T "2 10" -R "wlan0 ([0-9]+)" -e -D 1000 1.3.6.1.2.1.2.2
# Packets not transmitted (#/s) because of errors:
        $name -d "Packet errors (out):" -l errors -w 10 -c 20 -T "2 20" -R "wlan0 ([0-9]+)" -e 1.3.6.1.2.1.2.2
# Packets not received (#/s) because of errors:
        $name -d "Packet errors (in)" -l errors -w 10 -c 20 -T "2 14" -R "wlan0 ([0-9]+)" -e 1.3.6.1.2.1.2.2
# SNMP Errors (#/s):
        $name -d "SNMP Errors (in)" -l snmperrors -w 5 -c 10 -e 1.3.6.1.2.1.11.8.0 1.3.6.1.2.1.11.9.0 1.3.6.1.2.1.11.10.0 1.3.6.1.2.1.11.11.0 1.3.6.1.2.1.11.9.0
# SNMP Errors (#/s):
        $name -d "SNMP Errors (out)" -l snmperrors -w 5 -c 10 -e 1.3.6.1.2.1.11.20.0 1.3.6.1.2.1.11.21.0 1.3.6.1.2.1.11.22.0 1.3.6.1.2.1.11.24.0


Relative value measurement:
---------------------------
# Ram usage:
        $name -d "Phys. Mem. usage" -l memory -u MB -r -T "3 5 6" -R "Physical memory (\\d+) (\\d+)" -w 70 -c 80 -D 1000 1.3.6.1.2.1.25.2.3
# Ram left (without table)
        $name -d "Phys. Mem. left" -l memory -u MB -w 30 -c 20 -D 1000 -r 1.3.6.1.4.1.2021.4.5.0 1.3.6.1.4.1.2021.4.6.0 1.3.6.1.4.1.2021.4.14.0 1.3.6.1.4.1.2021.4.15.0
# Swap usage:
        $name -d "Swap usage" -l swap -u MB -T "3 5 6" -r -R "Swap space (\\d+) (\\d+)" -w 60 -c 70 -D 1000 1.3.6.1.2.1.25.2.3
# Root Diskspace usage:
        $name -d "Disk usage" -l disk -u GB -w 70 -c 85 -r -D 262144 -T "3 5 6" -R "\/ (\\d+) (\\d+)" 1.3.6.1.2.1.25.2.3


<---====== Standard options ======--->

-v, --verbose
	Activate vorbose output
-V, --Version
	print version
-h, --help
	Show (this) help
-H, --hostname=HOSTNAME
	IP/hostname to ask for values
	Default is: 127.0.0.1
-d, --description=DESCRIPTION
	Set Description for Output
-l, --label=LABEL
	Set label for Output
-u, --uom=[ |s|%|B|KB|MB|GB|TB|c]
	Set unit of measurement for Output
-w, --warning=INTEGER
	warning threshold, absolute value if 1 OID, %-value if more.
	WARNING-status will be set if this value is reached (upraising),
	or undergone (downraising)
-c, --critical=INTEGER
	critical threshold (see warning-threshold)
	Escalation is the same like -w
--min
	Set the min-value for absolute-value comparing
--max
	Set max.. see -min option
-r, --relative
	1st OID is interpreted as 100%, every following OID will be summed up.
	This will be measured as: (x_sum_OIDs/100%_OID)*100. WARN and CRITICAL
	will be interpreted as %-values.
	Default is: Sum up ALL OID-values.

<---====== Advanced options ======--->

-e, --delta
	Measure differences over time: (NEW_VAL-OLD_VAL)/SECONDS_PASSED. The
	1st measured value will be ignored if there is nothing captured (Returns
	UNKNOWN). This is intended to be used to measure bandwith or packet-failures
	over time. Standard MIBs don't give you the ability to do this. Relative
	comparing doesn't make much sense here.

	NOTE: This will create a tmp-file at $TMP_VALUES_FILE to store the values.
	Varnames are build by: 'SNMP'_HOSTNAME_DESCRIPTION_LABEL_UOM. Be aware to take individual
	descriptions/labels! Every modification on this values will reset the last state!
	The same will happen on reboot where /tmp is going to be flushed.
-S, --stringcompare (needs: R, if not set: needs w and c)
	Set this to compare a String-Value (eg Running Process).
	Default is: Compare numeric values
-R, --regex=REGEX
	Set Regex to match against or to capture numerical values (tables and single OID)
	Dont forget to escape special regex-chars! . => \\., - => \\-

	Note: if --stringcompare is NOT set, this REGEX MUST match numerical values!
	Example for numerical matching: "([0-9]+) /dev/sda"
-T, --table="2 3" (needs: R, no matter if S)
	Compare values in a Table.  Specify Columns (starting at 1) to 
        match against the Regex, every table-row will be compared separately.
	The OID  has to be the Table-startingpoint. All returned row-values
	will be separated by whitespaces. This option will implicitly call snmptable.
	Example: -T "2 7" -S -R "[0-9]+ /dev/sda"
-D, --divider=INTEGER
	Divider for all integer-values
	Example:
		Ram measured in Kb -> Mb (x / 1000)
		Bandwith measured in B/s -> KB/s (used with --delta) (x / 1000)
		CPU-Load as 1.23 -> 123 (x / 0.01)
-N, --netsnmpopts="OPTIONS"
	Net-SNMP Options surrounded by \"\". This overrides settings made in snmp.conf.
EOT
}

sub verb($) { my $t=shift; print $t,"\n" if defined($do_verbose); }
sub round($$) { sprintf "%.$_[1]f", $_[0]; }

# returns abs( (NEW_VALUE - OLD_VALUE)/SECONDS_PASSED ) from a value saved last time calling
# this function and saves back the new key/value and timestamp. The return-value be
# always positive or -1 if the old value couldn't be retrieved. The minimum calling-intervall
# is 1sec. This function expcects 2 parameters:  1) valuename 2) new_value. For valuename,
# only alphanumeric values are allowed, new_value can be any number inclusive
# rational numbers (0, 1, 2... 0.1, 0.2 ..). This will create a tempfile at
# $TMP_VALUES_FILE to store all variables and all entries will look
# like: KEY;VALUE;SECONDS\n
sub get_diff_over_time($$) {
# This way only valid key/values get into the tmp-file. No other function will read this file!
if (    !defined($_[0]) ||
        !defined($_[1]) ||
        $_[0]=~m/[^\w\_]+/ ||           # key: only alphanumeric values and _
        $_[1]!~m/\-?\d+(\.\d+)?/ ) {    # value: all decimals (negative and floats)
verb "!!! invalid Parameter: $_[0] $_[1]";
return -1;
} else { verb "got param key/value: $_[0] $_[1]"; }

open(FILE, "+<", $TMP_VALUES_FILE) or open(FILE, "+>", $TMP_VALUES_FILE) or die "Cant open/create file: $TMP_VALUES_FILE";      # create file if not present
flock(FILE, LOCK_EX);   # this will lock access until unlock is called by the blocking script

my %TMP_VALUES;
my $diff_value  = 0;
my $diff_sec    = 0;
my $val_per_sec = -1;
my $row         = undef;
my @key_value;

while($row = <FILE>) {                                  # read the entire file
        chomp $row;
        @key_value = split(";", $row);                  # values are saved as NAME;VALUE;SECONDS

        if (@key_value != 3) { 			       # skip if not exactly 3 arguments
                verb "skipping: @key_value";
                next;
                }

        verb "got tmp value: $key_value[0];$key_value[1];$key_value[2]";
        $TMP_VALUES{$key_value[0]}      = ( [ "$key_value[1]", "$key_value[2]"] );		# get key/value-pairs: name -> {value, time}
        }

# always update to keep timestamp up-to-date!
#if ( !defined($TMP_VALUES{$_[0]})  || $TMP_VALUES{$_[0]}->[0] != $_[1] ) {
#	verb "updating old value: $TMP_VALUES{$_[0]} => $_[1]";

        my $ctime                       = time;

        if (defined($TMP_VALUES{$_[0]})) { 							# calc the diff if old value was found
                $diff_value             = $_[1] - $TMP_VALUES{$_[0]}->[0];
                $diff_value             = abs($diff_value) if $diff_value < 0;                  # only positive value-diffs
                $diff_sec               = $ctime - $TMP_VALUES{$_[0]}->[1];

		if ($diff_sec > 0) {								# no getative times or division by 0, $val_per_sec will remain -1
			$val_per_sec	= round($diff_value/$diff_sec, 0);
		} else {
                	verb "got negative timediff for $_[0]: $diff_sec";
		}
        } else { verb "$_[0] not found, first save?"; }

	verb "diff_value/diff_sec: $diff_value/$diff_sec";

        $TMP_VALUES{$_[0]}      = ( [ "$_[1]", $ctime ] );					# save new key/value pair
        verb "saving new value: ".$_[0].";".$TMP_VALUES{$_[0]}->[0].";$ctime";

        truncate(FILE, 0) or die "Cant truncate file: $TMP_VALUES_FILE";			# clear file to save new values
	seek(FILE, 0, 0) or die "Unable to reset Filepointer in $TMP_VALUES_FILE";

        foreach my $key (keys %TMP_VALUES) {
                print FILE "$key;".$TMP_VALUES{$key}->[0].";".$TMP_VALUES{$key}->[1]."\n";
                }
#        }

#flock(FILE, LOCK_UN);
close(FILE);	# auto-unlock

return $val_per_sec;
}

#`echo "@ARGV" >> /home/mike/folder/nagios.log`;



#####################
# PARAMETER PARSING #
#####################

Getopt::Long::Configure ("bundling");

if (!GetOptions(
	'V|version'		=> \$do_version,
	'v|verbose'    		=> \$do_verbose,
        'h|help'		=> \$do_help,
        'H|host=s'		=> \$HOST,
        'w|warning=f'		=> \$WARNING,		# is any value if 1 OID, else 0-100
        'c|critical=f'		=> \$CRITICAL,		# see max
        'min=f'			=> \$MIN,
        'max=f'			=> \$MAX,
        'r|relative'		=> \$do_relative,
        'e|delta'		=> \$do_delta,
        'd|description=s'	=> \$DESCRIPTION,
        'l|label=s'		=> \$LABEL,
        'u|uom=s'		=> \$UOM,
        'S|stringcompare'	=> \$STR_CMPR,		# needs: R, if not set: needs w and c
        'R|regex=s'		=> \$REGEX,
        'T|table=s'		=> \$TABLE_COLS,	# needs: R, no matter if S
        'D|divider=f'		=> \$DIVIDER,
        'N|netsnmpopts=s'	=> \$NET_SNMP_OPTS_ADD
	)
) {
	verb "Error parsing options!";
	exit($STATUS_CODE{"UNKNOWN"});
}

if (defined($do_help)) { print_help(); exit($STATUS_CODE{"UNKNOWN"}); }
if (defined($do_version)) { print_version(); exit($STATUS_CODE{"UNKNOWN"}); };

# arguments: returncode [OK|WARNING|CRITICAL|UNKOWN], [DESCRIPTION]
# new description is optional
sub do_exit($;$) {
	$WARNING	= "" if !defined($WARNING);
	$CRITICAL	= "" if !defined($CRITICAL);

	print $_[0]." - ",(defined($_[1]) ? $_[1] : "$DESCRIPTION $CURRENT_REAL$UOM")," | $LABEL=$CURRENT_REAL$UOM;$WARNING;$CRITICAL;$MIN;$MAX\n";
	exit($STATUS_CODE{$_[0]});
}


verb "OIDs ".@ARGV.":\n@ARGV";

# Check amount of OID, min 1
if ( @ARGV == 0 ) {
	do_exit "UNKNOWN", "OID Missing";
}
elsif ( @ARGV == 1 ) {
	if ( !defined($STR_CMPR)) {
		verb "Will search absolute value";
		verb "..or relative if table returns >1 values" if ($TABLE_COLS);
	}
}
else {
	if (defined($TABLE_COLS)) {
		do_exit "UNKNOWN",">1 OID for table-compare: @ARGV";
	}

	if ( !defined($STR_CMPR)) {
		verb "Will search relative Value..";
	}
}

verb "Will search for a string" if (defined($STR_CMPR));

# This is for extended definitions like 1.2.3.\"test\"
#if ( "@ARGV"=~ m/[\"+]/g ) {							# check for right OID style
#	verb "Got \", modifying..";
#	$ARGV	=~ s/(\")/\\\"/g;
#}


do_exit "UNKNOWN","Divider = 0?" if ($DIVIDER == 0);

# check for WARNING/CRITICAL if numeric compare or regex if string-compare
if (	!defined($STR_CMPR) && (!defined($WARNING) || !defined($CRITICAL)) ||
	defined($STR_CMPR) && (!defined($REGEX) || $REGEX eq "")) {
	do_exit "UNKNOWN","Not enough Parameters, Numeric OR String compare?";
}
# regex is needed for table-compare, this is for numeric AND string-compare
elsif (	defined($TABLE_COLS) && (!defined($REGEX) ||  $REGEX eq "")) {
	do_exit "UNKNOWN","Regex missing for Table-compare";
}
# check %-values for relative compare
elsif ( $do_relative && ($WARNING > 100 || $CRITICAL > 100 || $WARNING < 0 || $CRITICAL < 0)) {
	do_exit "UNKNOWN", "wrong %-values for relative compare, check parameters";
}
# delta-compare is just for numeric values, difference of 2 strings? xX
elsif (defined($do_delta) && defined($STR_CMPR)) {
	do_exit "UNKNOWN", "Delta-difference enabled AND string-compare?";
}


if (defined($TABLE_COLS)) {							# different options for table-compare
	$SNMP_CMD = "snmptable";
	$NET_SNMP_OPTS = "-CH -Cf ';'";						# using ; as delimiter, this shouldnt be found in table-values
};

if (defined($NET_SNMP_OPTS_ADD)) { $NET_SNMP_OPTS .=" $NET_SNMP_OPTS_ADD"; }	# add user-defined options


$TMP_VALUE_VARNAME	= "SNMP\_$HOST\_$DESCRIPTION\_$LABEL\_$UOM";

if (defined($do_delta)) {
	$TMP_VALUE_VARNAME =~ s/[\W]+/\_/g;						# create valuename for delta-difference, replace all non-alphanumerical characters with "_"
}



######################
# EXECUTE SNMP-CHECK #
######################

# TODO: shorter
#my $VALUES	= "$SNMP_CMD $NET_SNMP_OPTS -t2 -r0 $HOST @ARGV 2>/dev/null";		# options: dont retry, timeout 2 sec, TODO: test redirect
my $VALUES	= "$SNMP_CMD $NET_SNMP_OPTS -t2 -r0 $HOST @ARGV 2>&1";			# options: dont retry, timeout 2 sec
$VALUES		=~ s/\\?"/\\\"/g;							# replace " => \" for custom OID values like 1.3.6.1.2...\"xxx\", there shouldnt be other "

verb "Executing: $VALUES";
$VALUES		= `$VALUES`;

# check if return is timeout/invalid oid
do_exit "UNKNOWN","Timeout.. check your SNMP-agent-connection!" if( $VALUES=~ m/snmp.+ Timeout$/g );
do_exit "UNKNOWN","Invalid OID, no value found at this place!" if( $VALUES=~ m/^No Such Object available on this agent at this OID$/g );


verb "Got following Values:\n$VALUES\n\n";

# get the table columns
if (defined($TABLE_COLS)) {
	$VALUES		=~ s/"(.*?)"/$1/gm;	# remove surrounding "", this will find snmptable itself with ';'  when searching for a process but that entry doesnt matter here
	my $do_exec	= "echo \"$VALUES\" | cut -d ';' -s --output-delimiter=' ' -f '$TABLE_COLS'";
#	verb "Will now execute: $do_exec\n\n";
	$VALUES	= `$do_exec`;			# cut the specified columns
	verb "Got following columns:\n$VALUES\n\n";
}

my @VALUE_MATCHES;

if (defined($REGEX)) {			# regex is present if: table or string
	if (@VALUE_MATCHES = ($VALUES =~ m/^$REGEX$/gm)) {	# check if we got some match, this can be string or integer
		if (defined($STR_CMPR)) { $VALUES = "value found!"; }
		else {			# get numeric values
#			my $MATCHES	= "";

#			foreach (1..$#-) {	# get all matches: 1 123.3 3434 ...
#				$MATCHES        .= substr($VALUES, $-[$_], $+[$_]-$-[$_]).(($_ == $#+)?"":" ");	# TODO: strict ref doesnt work with ${\$_}
#			}

			$VALUES	= "@VALUE_MATCHES";

			verb "Matches (Table or single OID) for \"$REGEX\": $VALUES";
		}
	} else {			# there is no match: no integer and no string, error!
			$VALUES	= "";
			verb "Did not match: $REGEX";
	}
}

if (!defined($STR_CMPR)) {						# this should be a numeric value, "123 123.." for table or "123\n123.." for snmpget
	if ( 	$VALUES eq "" ||
		$VALUES	!~ m/^(\-?[\d]+(\.[\d]+)?\s*)+$/g) {		# only accept numerical values
		$VALUES =~ s/\s+/ /mg;					# replace newline with whitespace for displaying
		do_exit "UNKNOWN", "Non-numeric value found: $VALUES";
	}

}				# this is a string, end up here
else {
	if ($VALUES ne "") {
		($CURRENT_REAL, $WARNING, $CRITICAL, $MIN, $MAX)	= (1,0,0,0,1);
		do_exit "OK","$DESCRIPTION";
	} else {
		($CURRENT_REAL, $WARNING, $CRITICAL, $MIN, $MAX)	= (0,0,0,0,1);
		do_exit "CRITICAL","$DESCRIPTION";
	}
}

my @VALUES_SPLIT	= split(/\s+/, $VALUES);				# split numeric values

do_exit "UNKNOWN","Just 1 value for relative compare?" if defined($do_relative) && @VALUES_SPLIT <= 1;	# enough values?

##########################
# COMPARE NUMERIC VALUES #
##########################

my $VAL_100	= $VALUES_SPLIT[0];
$CURRENT_REAL	= 0;

for (my $i=1; $i < @VALUES_SPLIT; ++$i) {				# sum up values
		$CURRENT_REAL += $VALUES_SPLIT[$i];			# TODO: feature: add "-" option: -1.3.6.1.4.1....
}

if ($DIVIDER != 1) {							# multiplicate to make values more compareable
	verb "Dividing by $DIVIDER";
	$VAL_100	= round($VAL_100 / $DIVIDER, 1);
	$CURRENT_REAL	= round($CURRENT_REAL / $DIVIDER, 1) if ($CURRENT_REAL > 0);
}

verb "\$VAL_100/\$CURRENT_REAL: $VAL_100/$CURRENT_REAL";

# Auto-Recognize if escalation is Up or Downwards
# based on WARNING and CRITICAL values
# UPWARDS escalation (OK-WARNING-CRITICAL) eg: PING-times or DOWNWARDS, eg SWAP left
my	$is_upwards	= $WARNING <= $CRITICAL ? 1 : 0;

if ( !defined($do_relative) ) {					# check absolute value, CURRENT_REAL + VAL_100 is now current value
	$CURRENT_REAL	+= $VAL_100;				# just 1 OID value (absolute value)

	if ($do_delta) {
		$CURRENT_REAL	= get_diff_over_time($TMP_VALUE_VARNAME, $CURRENT_REAL);

		if ($CURRENT_REAL < 0) {	# value not saved until now or invalid
			do_exit "UNKNOWN", "Waiting for next value to diff (1st call in delta-mode)";
		}
	}

	if (($is_upwards && $CURRENT_REAL < $WARNING) || (!$is_upwards && $CURRENT_REAL > $WARNING))
		{ do_exit "OK"; }
	elsif
	(($is_upwards && $CURRENT_REAL >= $WARNING  && $CURRENT_REAL < $CRITICAL) || (!$is_upwards && $CURRENT_REAL <= $WARNING && $CURRENT_REAL > $CRITICAL))
		{ do_exit "WARNING"; }
	else
		{ do_exit "CRITICAL"; }

}
else									# check relative value
{
	if ( $VAL_100 == 0) { $VAL_100 = 1; }				# no devision by zero, TODO: return state UNKNOWN?

	if ($do_delta) {
		$CURRENT_REAL	= get_diff_over_time($TMP_VALUE_VARNAME, $CURRENT_REAL);

		if ($CURRENT_REAL < 0) {	# value not saved until now or invalid
			do_exit "UNKNOWN", "Waiting for next value to diff (1st call in delta-mode)";
		}
	}

	$CURRENT_PERCENT	= round(($CURRENT_REAL / $VAL_100) * 100, 1);		# calculate current value as %

	# check percent here, cant be sure if relative comparing on table-compare
	if ($CURRENT_PERCENT > 100) {
		do_exit "UNKNOWN", "got >100%, check OIDs";
	}

	$WARNING		= ($WARNING * $VAL_100 ) / 100;		# warning-value percent -> real value
	$CRITICAL		= ($CRITICAL * $VAL_100 ) / 100;	# critical-value percent -> real value
	$MIN			= 0;
	$MAX			= $VAL_100;

	if (($is_upwards && $CURRENT_REAL < $WARNING) || (!$is_upwards && $CURRENT_REAL > $WARNING))
		{ do_exit "OK","$DESCRIPTION $CURRENT_PERCENT%"; }
	elsif
	(($is_upwards && $CURRENT_REAL >= $WARNING && $CURRENT_REAL < $CRITICAL) || (!$is_upwards && $CURRENT_REAL <= $WARNING && $CURRENT_REAL > $CRITICAL))
		{ do_exit "WARNING","$DESCRIPTION $CURRENT_PERCENT%"; }
	else
		{ do_exit "CRITICAL","$DESCRIPTION $CURRENT_PERCENT%"; }
}
