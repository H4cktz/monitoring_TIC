#!/usr/bin/php
<?php
//
// Check SLA Plugin
// Copyright (c) 2016-2017 Nagios Enterprises, LLC. All rights reserved.
//

// Plugin definitions
define("PROGRAM", 'check_xisla.php');
define("VERSION", '1.1.5');
define("STATUS_OK", 0);
define("STATUS_WARNING",  1);
define("STATUS_CRITICAL", 2);
define("STATUS_UNKNOWN", 3);
define("REQUEST_URI", '/sla.php');
if(!defined("PHP_BINARY")) define("PHP_BINARY", 'php-cgi');
define("DEBUG", false);

// SLA definitions/defaults
define("SLA_DEFAULT_LEVEL", 95);
define("ADVANCED", 0);
define("ASSUMEINITIALSTATE", 'yes');
define("ASSUMESTATERET", 'yes');
define("ASSUMESTATEDURINGDOWN", 'yes');
define("SOFTSTATE", 'no');
define("ASSUMEDHOSTSTATE", 3);
define("ASSUMEDSERVICESTATE", 6);
define("MANUAL_RUN", 1);
define("REPORTPERIOD", 'last24hours');

/**
 * @return array
 */
function parse_args() {
	$specs = array(
				array('short' => 'H',
					  'long' => 'hostname',
					  'required' => true),
				array('short' => 'h',
					  'long' => 'targethost',
					  'required' => false),
				array('short' => 's', 
					  'long' => 'targetservice',
					  'required' => false),
				array('short' => 'g', 
					  'long' => 'targethostg',
					  'required' => false),
				array('short' => 'e', 
					  'long' => 'targetserviceg',
					  'required' => false),
				array('short' => 'u',
					  'long' => 'username',
					  'required' => true),
				array('short' => 't',
					  'long' => 'ticket',
					  'required' => true),
				array('short' => 'w', 
					  'long' => 'warning',
					  'required' => false),
				array('short' => 'c', 
					  'long' => 'critical',
					  'required' => false),
				array('short' => 'A', 
					  'long' => 'auth_file',
					  'required' => false),
				array('short' => 'a', 
					  'long' => 'advanced',
					  'required' => false),
				array('short' => '--ssl',
					  'long' => 'ssl',
					  'required' => false),
				array('short' => '--help',
					  'long' => 'help',
					  'required' => false)
			);
	
	$options = parse_specs($specs);
	return $options;
}

/**
 * @param $specs
 *
 * @return array
 */
function parse_specs($specs) {

	$shortopts = '';
	$longopts = array();
	$opts = array();

	// Create the array that will be passed to getopt
	// Accepts an array of arrays, where each contained array has three 
	// entries, the short option, the long option and required
	foreach ($specs as $spec) {
		if (!empty($spec['short'])) {
			$shortopts .= "{$spec['short']}:";
		}

		if (!empty($spec['long'])) {
			$longopts[] = "{$spec['long']}:";
		}
	}

	// Parse with the builtin getopt function
	$parsed = getopt($shortopts, $longopts);

	// Make sure the input variables are sane. Also check to make sure that 
	// all flags marked required are present.
	foreach($specs as $spec) {
		$l = $spec['long'];
		$s = $spec['short'];

		if(array_key_exists($l, $parsed) && array_key_exists($s, $parsed)) {
			plugin_error("Command line parsing error: Inconsistent use of flag: " . $spec['long']);
		}

		if (array_key_exists($l, $parsed)) {
			$opts[$l] = $parsed[$l];
		} else if(array_key_exists($s, $parsed)) {
			$opts[$l] = $parsed[$s];
		} else if($spec['required'] == true) {
			// If auth file supplied then ignore user/ticket requirement - otherwise error as normal
			if ($s == 'u' || $s == 't') {
				if (!array_key_exists('A', $parsed)) {
					if (!array_key_exists('auth_file', $parsed)) {
						plugin_error("Command line parsing error: Required variable " . $spec['long'] . " not present.");
					} else {

					}
				}
			} else {
				plugin_error("Command line parsing error: Required variable " . $spec['long'] . " not present.");
			}
		}
	}

	return $opts;
}


/**
 * @param $message
 */
function debug_logging($message) {
	if(DEBUG) {
		echo $message;
	}
}

/**
 * @param $error_message
 */
function plugin_error($error_message) {

	if(is_array($error_message)) {
		print("ERROR: \n");

		foreach ($error_message as $err => $message) {
			print_r("\n" . $message . "\n");
		}
	} else {
		print("ERROR:\n{$error_message}\n  ------  \n");
	    fullusage();
	    xisla_exit('', STATUS_UNKNOWN);		
	}
}

/**
 * @param string $stdout
 * @param int    $exitcode
 */
function xisla_exit($stdout='', $exitcode=0) {
	print($stdout);
	exit($exitcode);
}

function main() {

	$options = parse_args();
	
	if(array_key_exists('version', $options)) {
		print('Plugin version: ' . VERSION);
		fullusage();
		xisla_exit('', STATUS_OK);
	}

	check_environment();
	$output = "";
	
	// get SLA data from Nagios XI Host
	$json = get_nagios_xi_availability($options);

	// run plugin with the data
	check_sla($options, $json);
}

// sanity
function check_environment() {
	exec(PHP_BINARY . ' -v', $execout, $return_var);

	if ($return_var != 0) {
		plugin_error("Cannot locate your php-cgi binary.");
	}
}

function check_sla($options, $json) {
	$output = "";
	// initialize errors
	$errors=0;
	$errmsg=array();

	// get args that were passed
	$xi_hostname = isset($options['hostname']) ? $options['hostname'] : "";
	$target_hostname = isset($options['targethost']) ? $options['targethost'] : "";
	$target_servicename = isset($options['targetservice']) ? $options['targetservice'] : "";
	$target_hostgroup = isset($options['targethostg']) ? $options['targethostg'] : "";
	$target_servicegroup = isset($options['targetserviceg']) ? $options['targetserviceg'] : "";	
	$warning = isset($options['warning']) ? $options['warning'] : "";
	$critical = isset($options['critical']) ? $options['critical'] : "";

	if (!$json) {
		xisla_exit("Nagios XI Host: " . $xi_hostname . " SLA report not retreiving data.  Verify correct user and ticket.\n", STATUS_UNKNOWN);
	}

	// parse output and exit
	if ($target_servicename && $target_servicename != "average") {
		$host = isset($json->host) ? $json->host : "";
		$service = isset($json->service) ? $json->service : "";
		$sla = isset($json->$host->$service->sla) ? $json->$host->$service->sla : "";

		$response = get_formatted_sla_output($sla, $host . ": " . $service, $warning, $critical);
		if ($response['error']) {
			plugin_error($response['msg']);
		}
		
		xisla_exit($response['output'], $response['result_code']);

	} else if ($target_hostgroup) {
		$hostgroup = isset($json->hostgroup) ? $json->hostgroup : "";
		$sla = isset($json->$hostgroup->sla) ? $json->$hostgroup->sla : "";

		$response = get_formatted_sla_output($sla, $hostgroup, $warning, $critical);
		if ($response['error']) {
			plugin_error($response['msg']);
		}

		xisla_exit($response['output'], $response['result_code']);

	} else if ($target_servicegroup) {
		$servicegroup = isset($json->servicegroup) ? $json->servicegroup : "";
		$sla = isset($json->$servicegroup->sla) ? $json->$servicegroup->sla : "";

		$response = get_formatted_sla_output($sla, $servicegroup, $warning, $critical);
		if ($response['error']) {
			plugin_error($response['msg']);
		}		

		xisla_exit($response['output'], $response['result_code']);

	} else {
		$host = isset($json->host) ? $json->host : "";
		$service = isset($json->service) ? $json->service : "";

		$sla = isset($json->$host->average->sla) ? $json->$host->average->sla : "";

		if (empty($sla)) {
			$sla = isset($json->$host->sla) ? $json->$host->sla : "";
		}

		$response = get_formatted_sla_output($sla, $host, $warning, $critical);
		if ($response['error']) {
			plugin_error($response['msg']);
		}

		xisla_exit($response['output'], $response['result_code']);
	}
}


function get_nagios_xi_availability($options) {
	$execout = "";

	// initialize errors
	$errors = 0;
	$errmsg = array();
	$uri = "http://";

	if (isset($options['ssl'])) {
        $uri = "https://";
	}

	// get args that were passed
	$xi_hostname = isset($options['hostname']) ? $options['hostname'] : "";
	$target_hostname = isset($options['targethost']) ? $options['targethost'] : "";
	$target_servicename = isset($options['targetservice']) ? $options['targetservice'] : "";
	$target_hostgroup = isset($options['targethostg']) ? $options['targethostg'] : "";
	$target_servicegroup = isset($options['targetserviceg']) ? $options['targetserviceg'] : "";
	$warning = isset($options['warning']) ? $options['warning'] : "";
	$critical = isset($options['critical']) ? $options['critical'] : "";
	$advanced = isset($options['advanced']) ? $options['advanced'] : "";

	// Check for auth file
	if (isset($options['auth_file'])) {
		// error if not found or not readable
		$read = is_readable($options['auth_file']);

		if (!$read) {
			plugin_error("The supplied authorization file was not available or is not readable: " . $options['auth_file']);
		}

		$auth_contents = file_get_contents($options['auth_file']);
		$auth_contents = explode("\n", $auth_contents);

		if (isset($auth_contents[0])) {
			// find username from auth file/ trim 
			$user = substr($auth_contents[0], strpos($auth_contents[0], "=") + 1);
			$options['username'] = trim($user);
		} else {
			plugin_error("There was an error reading the authorization file: " . $options['auth_file'] . ".  Verify correct format.");
		}

		if (isset($auth_contents[1])) {
			// find ticket number from auth file/ trim 
			$ticket = substr($auth_contents[1], strpos($auth_contents[1], "=") + 1);
			$options['ticket'] = trim($ticket);
		} else {
			plugin_error("There was an error reading the authorization file: " . $options['auth_file'] . ".  Verify correct format.");
		}
	} else {
		// fallback to username and ticket
		$options['username'] = isset($options['username']) ? $options['username'] : "";
		$options['ticket'] = isset($options['ticket']) ? $options['ticket'] : "";
	}

	if ($advanced) {
		// parse advanced options
		$advanced = explode(',', $advanced);		

		foreach ($advanced as $k => $v) {
			list($optionname, $val) = explode('=', $v);
			if (!is_numeric($val) && $optionname !== 'reportperiod') {
				if (!in_array($val, array('yes','no'), true)) {
					$errmsg[$errors++]="ERROR: Advanced option using incorrect value, check usage.";
					continue;
				}
			}

			if ($optionname == "assumeinitials") {
				$options['assumeinitialstates'] = $val;
			}
			
			if ($optionname == "assumestater") {
				$options['assumestateretention'] = $val;
			}

			if ($optionname == "assumedown") {
				$options['assumestatesduringdowtime'] = $val;
			}

			if ($optionname == "softstate") {
				$options['includesoftstates'] = $val;
			}

			if ($optionname == "asssumehs") {
				$options['assumedhoststate'] = $val;
			}

			if ($optionname == "asssumess") {
				$options['assumedservicestate'] = $val;
			}

			if ($optionname == "reportperiod") {
				$options['timeperiod'] = $val;
			}
		}

		// reset to true
		$options['advanced'] = 1;
	} else {
		// if no advanced option set to false
		$options['advanced'] = 0;
	}

	// build initial query URL
	$url =  $uri . $xi_hostname . "/nagiosxi/reports" . REQUEST_URI;
	$query = 'mode=xml&';

	// what type of report do we run? set type	
	if (isset($options['targethostg'])) {
		$query .= "hostgroup=" . urlencode($target_hostgroup);
	} else if (isset($options['targetserviceg'])) {
		$query .= "servicegroup=" . urlencode($target_servicegroup);
	} else if (isset($options['targethost'])) {
		if (isset($options['targetservice'])){
			$query .= "host=" . urlencode($target_hostname) . "&";
			$query .= "service=" . urlencode($target_servicename);
		} else {
			$query .= "host=" . urlencode($target_hostname);
		}
	}

	// add all options to query URL
	foreach ($options as $k => $v) {
		if (!in_array($k, array("hostname", "targethostg", "targetserviceg", "hostgroup", "servicegroup", "auth_file", "ssl"), true )) {
			$query .= "&" . urlencode($k) . "=" . urlencode($v);
		}
	}

	//print $url;
	//print $query;

	// get SLA JSON
	$curl = curl_init();
	curl_setopt($curl, CURLOPT_URL, $url);
	curl_setopt($curl, CURLOPT_POST, true);
	curl_setopt($curl, CURLOPT_POSTFIELDS, $query);
	curl_setopt($curl, CURLOPT_RETURNTRANSFER, true); 
	curl_setopt($curl, CURLOPT_COOKIESESSION, true);
	curl_setopt($curl, CURLOPT_TIMEOUT, 30);
	if (isset($options['ssl'])) {
		curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
	}

	// debug curl session
	// curl_setopt($curl, CURLOPT_VERBOSE, TRUE);

	$data = curl_exec($curl);
	$json = json_decode($data);

	// catch curl errors
	if (curl_errno($curl)) {
		$error = curl_error($curl);
		$errmsg[$errors++] = "SLA data not available: " . $error . STATUS_UNKNOWN;
	}

	// close curl session
	curl_close($curl);

	// check all errors
	if ($errors > 0) {
		plugin_error($errmsg);
	}

	return $json;
}

function get_formatted_sla_output($sla, $target, $warning, $critical) {
    if (!$sla) {
        $response['result_code'] = 3;
        $response['output'] = "UNKNOWN: Could not get data from Nagios XI Server.";
    }

    $result_code = 0;
    $result_prefix = "OK: ";
    
    if (!empty($warning)) {

        switch (check_sla_threshold($warning, $sla)) {
            case 3:
                $response['error'] = true;
                $response['msg'] = _("In range threshold START:END, START must be less than or equal to END");
                return $response;
            case 1:
                $result_code = 1;
                $result_prefix = "WARNING: ";
        }
    }

    if (!empty($critical)) {

        switch (check_sla_threshold($critical, $sla)) {
            case 3:
                $response['error'] = true;
                $response['msg'] = _("In range threshold START:END, START must be less than or equal to END");
                return $response;
            case 1:
                $result_code = 2;
                $result_prefix = "CRITICAL: ";
        }
    }

    $response['error'] = false;
    $response['result_code'] = $result_code;
    $response['output'] = $result_prefix . " $target SLA is $sla% |sla=$sla%;$warning;$critical\n";

    return $response;
}

// Verify that the threshold type including range thresholds
function check_sla_threshold($threshold, $value) {
    $inside = ((substr($threshold, 0, 1) == '@') ? true : false);
    $range = str_replace('@','', $threshold);
    $parts = explode(':', $range);

    if (count($parts) > 1) {
        $start = $parts[0];
        $end = $parts[1];
    } else {
        $start = 0;
        $end = $range;
    }

    if (substr($start, 0, 1) == "~") {
        $start = -999999999;
    }
    if (!is_numeric($end)) {
        $end = 999999999;
    }
    if ($start > $end) {
        return 3;
    }
    if ($inside > 0) {
        if ($start <= $value && $value <= $end) {
            return 1;
        }
    } else {
        if ($value < $start || $end < $value) {
            return 1;
        }
    }

    return 0;
}

// fullusage
function fullusage() {
$advmask = 	"               |%-42.42s | %-11.11s | %-55.55s |\n";
print(
	"check_xisla.php - v" . VERSION . "
 	Copyright (c) 2016-2017 Nagios Enterprises <lgroschen@nagios.com>

	This plugin checks Service Level Agreement(SLA) status on a Nagios XI server and monitors if it has been met by using target
	 and/ or threshold SLA .

	Usage: " . PROGRAM . " -H <XI hostname> [-h <hostname> -s <service> -g <hostgroup> -e <servicegroup>] 
	 	  (-t <ticket number> -u <username> || -A <auth_file>) [-w <SLA % warning>] [-c <SLA % critical>] [-a '<advanced option 1>,<2..>']
	Options:
	-H
		Nagios XI hostname.
	-h
		Target hostname.
	-s
		Target service.  Must include a target hostname.
	-g
		Target Hostgroup.
	-e
		Target Servicegroup.
	-u
		SLA username (ie, nagiosadmin)
	-t
		SLA ticket number (Accessible in the Nagios XI User Interface: Admin > Manage Components > Backend API URL 
		 > Edit Settings.  Select a user and check the first URL.  The ticket will be located at the end of the URL 
		 in format: ticket='ticket_number')
	-w
		SLA percentage (%) to result in a Warning status. (Target - @95 [x >= 95] | Range - 85:95 [85 > x > 95] | 
		 Target Range - @85:95 [85 >= x >= 95])
	-c
		SLA percentage (%) to result in a Critical status. (See Warning)
	-A
		The full path to the Authorization file.  This file will keep your Nagios XI ticket number and username secure.  
		To override this setting use -u and -t.

	       Authentication File format is
	         username=NagiosXIuser
	         ticket=NagiosXIticket

	    Set your own values for NagiosXIuser and NagiosXIticket.
	-a
		Advanced SLA Report Options.  Comma seperated list of advanced SLA Report options:
	       ---------------------------------------------------------------------------------------------------------------------
");
// SLA Advanced options table
printf($advmask, "Options (argument name)", "Default", "Value");
print("   	       ---------------------------------------------------------------------------------------------------------------------
");
printf($advmask, "Assume Initial States (assumeinitials)", ASSUMEINITIALSTATE, "yes/no");
printf($advmask, "Assume State Retention (assumestater)", ASSUMESTATERET, "yes/no");
printf($advmask, "Assume States During Downtime (assumedown)", ASSUMESTATEDURINGDOWN, "yes/no");
printf($advmask, "Include Soft States (softstate)", SOFTSTATE, "yes/no");
printf($advmask, "First Assumed Host State (asssumehs)", ASSUMEDHOSTSTATE, "0 = Unspecified, -1 = Current State, ");
printf($advmask, "", "", "3 = Host Up, 4 = Host Down, 5 = Host Unreachable");
printf($advmask, "First Assumed Service State (asssumess)", ASSUMEDSERVICESTATE, "0 = Unspecified, -1 = Current State, 6 = Service OK, ");
printf($advmask, "", "", "7 = Service Warning, 8 = Service Unknown, 9 = Service");
printf($advmask, "Report Time Period (reportperiod)", REPORTPERIOD, "Choose a time period from the Nagios XI server by name, ");
printf($advmask, "", "", "create a new one or use the default.");
print("   	       ---------------------------------------------------------------------------------------------------------------------

		Example: -a 'assumeinitials=no,asssumehs=-1,reportperiod=xi_timeperiod_24x7'
	--ssl
		Use this boolean flag as true to query a secure remote server over SSL/TLS (--ssl true)
	--help
		Print this help and usage message

	This plugin will get information from the Nagios XI SLA API.  If it fails ensure the nagios service is running.	Example:
	  ./" . PROGRAM . " -H 192.168.1.23 -h slaprod01 -t dkfrmkasl -u nagiosadmin -w @95 -c 90:94 \n\n"
	);
}

main();
