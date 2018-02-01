#!/usr/bin/perl
#
# License to use per the terms of the GNU Public License (GPL)
#
# CHANGES:
# Modified by Nagios Enterprises January 2010 to return performance data
#
#$Id$

# configure nagios utils
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS);

use strict;
use Getopt::Long;
use Data::Dumper;
use IO::Socket;
                                                                               
Getopt::Long::Configure('bundling');

my $opt_debug = 0;
my $opt_ver = 0;
my $opt_help = 0;
my $opt_typ = '';
my $opt_temp = 'x/x,x/x';
my $opt_hum = 'x/x,x/x';
my $opt_illum = 'x/x,x/x';
my $opt_timeout = $TIMEOUT;

GetOptions
(  "version|v" => \$opt_ver,
   "debug|d" => \$opt_debug,
   "help|h" => \$opt_help,
   "type=s" => \$opt_typ,
   "temp|temperature=s" => \$opt_temp,
   "hum|humidity=s" => \$opt_hum,
   "illum|illumination=s" => \$opt_illum,
);
my $sensor = $ARGV[0] || &syntax();

if ($opt_help) {
    &syntax();
}

#############################################
my @temp = split(/[\/,]/, $opt_temp);
my @hum = split(/[\/,]/, $opt_hum);
my @illum = split(/[\/,]/, $opt_illum);

my $vals = &read_sensor($sensor, $opt_timeout);

my @msgs = ();
my $condition = $ERRORS{'OK'};
&check_value('temperature', $vals, @temp);
&check_value('humidity', $vals, @hum);
&check_value('illumination', $vals, @illum);

if ($#msgs > -1) {
    print join("; ", @msgs);
}

if ($opt_typ eq '') {
	#print "[";
	print "Temp: $vals->{'temperature'} $vals->{'temp-unit'}, ";
	print "Humidity: $vals->{'humidity'}%, ";
	print "Illum: $vals->{'illumination'}\n";
	#print "]\n";
} else {
	#print "[";
	if ($opt_typ eq "temp") {
		print "Temp: $vals->{'temperature'} $vals->{'temp-unit'}";
		print "|";
		print "temperature=$vals->{'temperature'}$vals->{'temp-unit'};;;; ";
	} elsif ($opt_typ eq "hum") {
		print "Humidity: $vals->{'humidity'}%";
		print "|";
		print "humidity=$vals->{'humidity'}%;;;; ";
	} elsif ($opt_typ eq "illum") {
		print "Illum: $vals->{'illumination'}";
		print "|";
		print "illumination=$vals->{'illumination'};;;; ";
	}

	#print "]\n";
}

exit($condition);

#############################################


sub check_value {
    my ($type, $vals, $w_lo, $w_hi, $c_lo, $c_hi) = @_;
    my $current = $vals->{$type};

    my $uctype = ucfirst $type;
    if ($c_lo ne 'x' && $current < $c_lo) {
        push(@msgs, "CRITICAL LOW $uctype (<$c_lo) - ");
        $condition = $ERRORS{'CRITICAL'};
    } elsif ($c_hi ne 'x' && $current > $c_hi) {
        push(@msgs, "CRITICAL HIGH $uctype (>$c_hi) - ");
        $condition = $ERRORS{'CRITICAL'};
    } elsif ($w_lo ne 'x' && $current < $w_lo) {
        push(@msgs, "WARNING LOW $uctype (<$w_lo) - ");
        $condition = $ERRORS{'WARNING'};
    } elsif ($w_hi ne 'x' && $current > $w_hi) {
        push(@msgs, "WARNING HIGH $uctype (>$w_hi) - ");
        $condition = $ERRORS{'WARNING'};
    }
};

sub syntax {
  print <<END;
Syntax: $0 [options] {sensor}

  {sensor} is the address of sensor on network (name or IP)

  --debug
    print debug messages to stdout
  --timeout=x
    how long to wait before failing.  Default=$opt_timeout
  --type={all|temp|hum|illum}
    which sensor data you want to retrieve.
    If you did not specify this option, then this plugin will return all 
    sensor data.
  --{temp|hum|illum}=warnlow/warnhi,critlow/crithi
    four values are required.  'x' is used to specify no value.
    Example:

	check_em01.pl --type=temp --temp=65/75,60/80
        check_em01.pl --type=all --temp=65/75,60/80 --hum=30/40,25/50 --illum=40/70,30/80
END
  exit($ERRORS{'UNKNOWN'});
}

sub read_sensor {
    my ($host,$timeout) = @_;

    my $remote = IO::Socket::INET->new(
         Proto    => "tcp",
         PeerAddr => $host,
         PeerPort => 80,
         Timeout  => $timeout,
    );

    if (!$remote) {
        &debug("connect error: $!\n");
        print "failed to connect\n";
        exit($ERRORS{'UNKNOWN'});
    }
    &debug("connected to $host:80\n");

    my $didalarm = 0;
    my $hdrs = {};
    my $read = {};
    eval {
        local $SIG{'ALRM'} = sub { $didalarm=1; die "alarm\n"; };
        alarm($timeout);

        # HTTP/1.1 bug found by Fabrice Duley (Fabrice.Duley@alcatel.fr)
        print $remote "GET /index.html?em345678 HTTP/1.1 \r\n";
        my $inhdr = 1;
        while (<$remote>) {
            if ($inhdr) {
                s/[\n\r]+$//;
                if (!length($_)) {
                    $inhdr = 0;
                } elsif (/^([^ :]+)([ :])\s*(.*)$/) {
                    my $n = lc $1;
                    my $v = $3;
                    if (!exists($hdrs->{$n})) {
                        $hdrs->{$n} = [$v];
                    } else {
                        push(@{$hdrs->{$n}}, $v);
                    }
                } else {
                    &debug("Unexpected HTTP header at line $.: $_\n");
                }
            } elsif (/T\D*?([A-Z])\D*?([0123456789.]+)\D*?
                      HU\D*?([0123456789.]+)\D*?
                      IL\D*?([0123456789.]+)/gx)
            {
                $read->{'temp-unit'} = $1;
                $read->{'temperature'} = $2;
                $read->{'humidity'} = $3;
                $read->{'illumination'} = $4;
            }
        }
        close($remote);
        alarm(0);
    };

    if ($@) {
        die if $didalarm != 1;
        &debug("timeout(alarm) during sensor read\n");
        print "Unable to read sensor\n";
        exit($ERRORS{'UNKNOWN'});
    }

    return $read;
};

sub debug {
    my ($msg) = @_;

    if ($opt_debug) {
        print STDERR $msg;
    }
};

