#!/bin/perl
# nagios: -epn
## check_pnp_rrds - PNP4Nagios.
## Copyright (c) 2006-2009 Joerg Linge (http://www.pnp4nagios.org)
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
##
## $Id: check_pnp_rrds.pl.in 614 2009-03-19 17:31:59Z pitchfork $
##
use File::Find;
use File::Basename;
use warnings;
use strict;
use Getopt::Long;

Getopt::Long::Configure('bundling');
my ( $opt_d, $opt_V, $opt_h, $opt_b );
my $opt_a    = 7;
my $opt_w    = 1;
my $opt_c    = 10;
my $opt_t    = 10;
my $opt_p    = "/usr/local/nagios/share/perfdata";
my $opt_ncmd = "/usr/local/nagios/var/rw/nagios.cmd";
my $opt_phost = "";
my $opt_pservice = "";
my $VERSION  = "0.4.14";
my $PROGNAME = basename($0);
my $PASV = 0;
my $USER = getpwuid($<);

sub print_help () ; 
sub print_usage () ; 

GetOptions(
    "V"          => \$opt_V,
    "version"    => \$opt_V,
    "h"          => \$opt_h,
    "help"       => \$opt_h,
    "t=i"        => \$opt_t,
    "timeout=i"  => \$opt_t,
    "w=i"        => \$opt_w,
    "warning=i"  => \$opt_w,
    "c=i"        => \$opt_c,
    "critical=i" => \$opt_c,
    "fileage=i"  => \$opt_a,
    "a=i"        => \$opt_a,
    "p=s"        => \$opt_p,
    "rrdpath=s"  => \$opt_p,
    "passiv-hostname=s" => \$opt_phost,
    "passiv-servicedesc=s" => \$opt_pservice,
    "nagios-cmd=s" => \$opt_ncmd,
) or print_help();



print_help() if ($opt_h);

my $RRD_ERRORS    = 0;
my $RRD_ERR       = "";
my $RRD_AGE       = "";
my $XML_COUNT_AGE = 0;
my $XML_COUNT     = 0;
my $RRD_COUNT     = 0;
my $RC            = 0;
my $OUT           = "OK: ";
my $PERF          = "";

$SIG{'ALRM'} = sub {
    print "UNKNOWN: Timeout after $opt_t sec.\n";
    exit 3;
};

alarm($opt_t);

$PASV = 1 if($opt_phost && $opt_pservice && $opt_ncmd); 

if($PASV == 1 && !-e $opt_ncmd){
    print "\n\nUNKNOWN: $opt_ncmd does not exist\n\n";
    print_usage();
    exit 3;
}

if($PASV == 1 && !-w $opt_ncmd){
    print "\n\nUNKNOWN: $opt_ncmd is not writable by \"$USER\" \n\n";
    print_usage();
    exit 3;
}

if ( -r $opt_p ) {
    find { no_chdir => 1,
           wanted   => \&inspect_files,
         }          => $opt_p
}
else {
    print "UNKNOWN: $opt_p not readable\n";
    exit 3;
}

sub inspect_files {
    my $found = 0;
    my $TXT   = "";
    my $host;
    my $service;
    my $file = $File::Find::name;
    my $dir  = $File::Find::dir;
    return unless -f $file;
    if ( $file =~ /\.xml/ ) {
        $XML_COUNT++;
        $service = basename($file);
        $host    = dirname($file);
        $host    = basename($host);
        open F, $file or print "couldn't open $file\n" && return;
        while (<F>) {
            if (m/<RC>(.*)<\/RC>/) {
                $found = $1;
            }
            if ( $found != 0 && m/<TXT>(.*)<\/TXT>/ ) {
                $TXT = $1;
                last;
            }
        }
        close F;
        my $mtime   = ( stat($file) )[9];
        my $fileage = ( ( time() - $mtime ) / 86400 );
        if ( $fileage >= ( $opt_a ) ) {

            #print "Age -> ".$fileage."\n";
            $XML_COUNT_AGE++;
            $RRD_AGE .= sprintf(".../%s/%s is %d days old.\n",$host,$service,$fileage);
        }
        $RRD_ERRORS++ if $found != "0";
        $RRD_ERR .= ".../$host/$service $TXT\n" if $found != 0;
    }
    else {
        return;
    }
}

sub PROCESS_SERVICE_CHECK_RESULT {
    my $RC = shift;
    my $OUT = shift;
    my $time = time();
    my $CommandLine         = "[$time] PROCESS_SERVICE_CHECK_RESULT;$opt_phost;$opt_pservice;$RC;$OUT";

    print "PROCESS_SERVICE_CHECK_RESULT\n";
    print $OUT;

    open(CommandFile, ">>$opt_ncmd");
    print CommandFile $CommandLine;
    close CommandFile;
}


if ( $XML_COUNT == 0 ) {
    print "UNKNOWN: No XML files found in $opt_p\n";
    exit 3;
}

if ( $RRD_ERRORS >= $opt_c || $XML_COUNT_AGE >= $opt_c ) {
    $RC  = 2;
    $OUT = "CRITICAL: ";
}
if ( $RRD_ERRORS >= $opt_w || $XML_COUNT_AGE >= $opt_w ) {
    $RC  = 1;
    $OUT = "WARNING: ";
}

$OUT .= "$XML_COUNT XML Files checked. $RRD_ERRORS RRD Errors found. $XML_COUNT_AGE old XML Files found";
$PERF = " | total=$XML_COUNT errors=$RRD_ERRORS;$opt_w;$opt_c;0;$XML_COUNT old=$XML_COUNT_AGE;$opt_w;$opt_c;0;$XML_COUNT\n";
$OUT .= $PERF . $RRD_ERR . $RRD_AGE;
if($PASV == 0){
    print $OUT;
    exit $RC;
}else{
    PROCESS_SERVICE_CHECK_RESULT($RC,$OUT);
}

sub print_help (){
    print "Copyright (c) 2008 Joerg Linge, Pitchfork\@pnp4nagios.org\n\n";
    print "\n";
    print "$PROGNAME $VERSION\n";
    print "$PROGNAME is used to find old or unusable RRD Files\n";
    print "\n";
    print_usage();
    print "\n";
    print "\n";
    print_support();
    exit 3;
}

sub print_usage () {
    print "USAGE: $PROGNAME [OPTIONS]\n";
    print "  -w,--warning\n";
    print "       Default: $opt_w\n";
    print "  -c,--critical\n";
    print "        Default: $opt_c\n";
    print "  -a,--fileage Max XML File Age.\n";
    print "       Default: $opt_a Days\n";
    print "  -p,--rrdpath Path to your RRD and XML Files.\n";
    print "       Default: $opt_p\n";
    print "  -t,--timeout Max Plugin Runtime.\n";
    print "       Default: $opt_t Seconds\n";
    print "\n\n";
    print "  --passiv-hostname=\n";
    print "       Nagios Hostname\n";
    print "  --passiv-servicedesc=\n";
    print "       Nagios Servicedesc\n";
    print "  --nagios-cmd=\n";
    print "       External Command File (nagios.cmd)\n";

}

sub print_support {
    print "SUPPORT: http://www.pnp4nagios.org/pnp/\n";
    print "\n\n";
}

# vim: set ai tabstop=4 shiftwidth=4
