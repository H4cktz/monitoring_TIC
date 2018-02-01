#!/usr/bin/php
<?php
// check_logserver.php
//
// Copyright 2014 Nagios Enterprises, LLC.
// Portions Copyright others - see source code below.
/* License:

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
* Neither the name of the Nagios Enterprises, LLC nor the names of its
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/


// Our working variables and initial values.
$url     = null;
$apikey  = null;
$warn    = null;
$crit    = null;
$minutes = null;
$id      = null;
$file    = null;
$query   = null;
$string  = null;
$timeout = 30; // Plugin timeout to query Log Server.
$debug   = 0; // Debug level, 0 is nothing.

$usageString = <<<USAGE

check_logserver - Copyright 2014 Nagios Enterprises, LLC.
                 Portions Copyright others (see source code).

Usage: {$argv[0]} <options>

Options:
--url=<URL>             The URL used to access the Nagios Log Server web interface
                        e.g. http://logserver.yourdomain.com/nagioslogserver/

--apikey=<APIKEY>       The apikey used for accessing the server

--minutes=<MINUTES>     The number of minutes to perform the query over

--timeout=<SECONDS>     Seconds before plugin times out (default=$timeout seconds)

--id=<ID>               Check count of logs matching a saved alert ID in Nagios Log Server

--file=<FILE>           Check count of logs matching a JSON query from a file

--query=<QUERY>         Check count of logs matching a given JSON query

--string=<STRING>       Check count of logs matching a raw Lucene query string

--warn=<WARNING>        The warning values, see:
                          https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
--crit=<CRITICAL>       The critical values, see
                          https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT


This plugin checks the status of a Nagios Log Server query.

USAGE;



doit();

function doit() {
	global $argv;
	global $url, $apikey, $warn, $crit, $minutes, $mode, $id, $file, $query, $string, $timeout;
	global $debug;

	if (!function_exists('json_decode')) {
		$message = "This plugin requires the json_decode() function from PHP 5.2.0 or later.";
		if (version_compare(phpversion(), '5.2.0', '<')) {
			echo_and_exit($message, 3);
		} else {
			echo_and_exit(
				$message.PHP_EOL
				."On Ubuntu systems this may need to be installed by running:".PHP_EOL
				."    sudo apt-get install php5-json",
				3
			);
		}
	}

	// Get and check command line args.
	process_args();


	// Build the full request url.
	if (substr($url, -1) != '/') $url .= '/'; // Make base url end in a slash.
	$url .= "index.php/api/check/";

	if ($id) {
		$url .= "id/$id?token=$apikey&minutes=$minutes";
	} else {
		if ($file) {
			$query = file_get_contents($file);
			if (!$query) {
				echo_and_exit("UNKNOWN: Cannot read input file", 3);
			}
		} else if ($string) {
			$query = <<<QUERY
{
	"query": {
		"filtered": {
			"query": {
				"bool": {
					"should": [
						{
							"query_string": {
								"query": "$string"
							}
						}
					]
				}
			},
			"filter": {
				"bool": {
					"must": [
						{
							"range": {
								"@timestamp": {
									"from": 0,
									"to": 0
								}
							}
						}
					]
				}
			}
		}
	}
}
QUERY;
		}
		$url .= "query?token=$apikey&minutes=$minutes&query=".urlencode($query);
	}

	if ($warn) $url .= "&warning=$warn";
	if ($crit) $url .= "&critical=$crit";

	if ($debug) echo("Request URL: ".print_r($url, true).PHP_EOL);


	// Send the request and get the result.
	$result = load_url($url, array(
		"method" => "post",
		"timeout" => $timeout,
		"return_info" => true,
	));

	if ($debug) echo("Response: ".print_r($result, true));

	if (!$result) {
		echo_and_exit("UNKNOWN: Cannot connect to Nagios Log Server", 3);
	}

	$result = json_decode($result['body']);

	if ($debug) echo("Result: ".print_r($result, true));

	if (!is_object($result)) {
		echo_and_exit("UNKNOWN: Server returned invalid output", 3);
	} else if (!empty($result->error)) {
		echo_and_exit($result->message, 3);
	} else {
		echo_and_exit($result->output, $result->result_code);
	}
}

////////////////////////////////////////////////////////////////////////
// Argument handling functions
////////////////////////////////////////////////////////////////////////

function print_usage($message=null) {
	global $usageString;
	if ($message) echo(PHP_EOL.$message.PHP_EOL);
	echo_and_exit($usageString, 3); // Exit status 3 for Nagios plugins is 'unknown'.
}


function process_args() {
	global $argc, $argv;
	global $url, $apikey, $warn, $crit, $minutes, $id, $file, $query, $string, $timeout;
	global $debug;

	if ($argc < 2 || array_intersect(array('--help', '-help', '-h', '-?'), $argv)) {
		print_usage();
	}

	$args = parse_args($argv);
	$modeOptions = 0;
	foreach ($args["options"] as $option) {
		switch ($option[0]) {
			case "url":
				$url = $option[1];
				break;
			case "apikey":
				$apikey = $option[1];
				break;
			case "warn":
				$warn = $option[1];
				break;
			case "crit":
				$crit = $option[1];
				break;
			case "minutes":
				$minutes = intval($option[1]);
				break;
			case "id":
				$id = $option[1];
				$modeOptions++;
				break;
			case "file":
				$file = $option[1];
				$modeOptions++;
				break;
			case "query":
				$query = $option[1];
				$modeOptions++;
				break;
			case "string":
				$string = $option[1];
				$modeOptions++;
				break;
			case "timeout":
				$timeout = intval($option[1]);
				break;
			case "debug":
				$debug = intval($option[1]);
				break;
			default:
				print_usage("ERROR: Unrecognized argument: $option[0]");
				break;
		}
	}

	// Make sure we have required arguments.
	if (!$apikey)  print_usage("ERROR: 'apikey' argument is required.");
	if (!$url)     print_usage("ERROR: 'url' argument is required.");
	if (!$minutes) print_usage("ERROR: 'minutes' argument is required.");

	// We need the mode arguments.
	if ($modeOptions == 0)
		print_usage("ERROR: 'id', 'file', 'query' or 'string' argument required.");
	if ($modeOptions > 1)
		print_usage("ERROR: Only one of 'id', 'file', 'query' or 'string' at a time.");
}

/* from anonymous and thomas harding */
/* See: http://us3.php.net/manual/en/features.commandline.php#86616 */
function parse_args($args) {
    $ret = array(
		'exec'      => '',
		'options'   => array(),
		'flags'     => array(),
		'arguments' => array(),
	);

	$ret['exec'] = array_shift( $args );

	while (($arg = array_shift($args)) != null) {
		// Is it a option? (prefixed with --)
		if ( substr($arg, 0, 2) === '--' ) {
			$option = substr($arg, 2);

			// is it the syntax '--option=argument'?
			if (strpos($option,'=') !== false)
				array_push( $ret['options'], explode('=', $option, 2) );
			else
				array_push( $ret['options'], $option );

			continue;
		}

		// Is it a flag or a serial of flags? (prefixed with -)
		if ( substr( $arg, 0, 1 ) === '-' ) {
			for ($i = 1; isset($arg[$i]) ; $i++)
				$ret['flags'][] = $arg[$i];

			continue;
		}

		// finally, it is not option, nor flag
		$ret['arguments'][] = $arg;
		continue;
	}

	return $ret;
}

////////////////////////////////////////////////////////////////////////
// Misc. helper functions
////////////////////////////////////////////////////////////////////////

/** Echo a message and exit with a status. */
function echo_and_exit($message, $status=0) {
	echo($message.PHP_EOL);
	exit($status);
}

/** Gets a value from an array, returning a default value if not found. */
function grab_array_var($a, $k, $d=null) {
	return (is_array($a) && array_key_exists($k, $a)) ? $a[$k] : $d;
}

/**
* See http://www.bin-co.com/php/scripts/load/
* Version : 1.00.A
* License: BSD
*/
/* renamed to load_url */
function load_url($url,$options=array('method'=>'get','return_info'=>false)) {

	// added 04-28-08 EG added a default timeout of 15 seconds
	if (!isset($options['timeout']))
		$options['timeout']=15;

	$url_parts = parse_url($url);

	$info = array(//Currently only supported by curl.
		'http_code'    => 200
	);
	$response = '';

	$send_header = array(
		'Accept' => 'text/*',
		'User-Agent' => 'BinGet/1.00.A (http://www.bin-co.com/php/scripts/load/)'
	);

	///////////////////////////// Curl /////////////////////////////////////
	//If curl is available, use curl to get the data.
	if (function_exists("curl_init")
				and (!(isset($options['use']) and $options['use'] == 'fsocketopen'))) { //Don't user curl if it is specifically stated to user fsocketopen in the options
		if (isset($options['method']) and $options['method'] == 'post') {
			$port = (isset($url_parts['port'])) ? ':' . $url_parts['port'] : '';
			$page = $url_parts['scheme'] . '://' . $url_parts['host'] . $port . $url_parts['path'];
		} else {
			$page = $url;
		}

		$ch = curl_init($url_parts['host']);

		// added 04-28-08 EG set a timeout
		if (isset($options['timeout']))
			curl_setopt($ch, CURLOPT_TIMEOUT, $options['timeout']);
			
		curl_setopt($ch, CURLOPT_URL, $page);
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); //Just return the data - not print the whole thing.
		curl_setopt($ch, CURLOPT_HEADER, true); //We need the headers
		curl_setopt($ch, CURLOPT_NOBODY, false); //The content - if true, will not download the contents
		if (isset($options['method']) and $options['method'] == 'post' and $url_parts['query']) {
			curl_setopt($ch, CURLOPT_POST, true);
			curl_setopt($ch, CURLOPT_POSTFIELDS, $url_parts['query']);
		}
		//Set the headers our spiders sends
		curl_setopt($ch, CURLOPT_USERAGENT, $send_header['User-Agent']); //The Name of the UserAgent we will be using ;)
		$custom_headers = array("Accept: " . $send_header['Accept'] );
		if (isset($options['modified_since']))
			array_push($custom_headers,"If-Modified-Since: ".gmdate('D, d M Y H:i:s \G\M\T',strtotime($options['modified_since'])));
		curl_setopt($ch, CURLOPT_HTTPHEADER, $custom_headers);

// 		curl_setopt($ch, CURLOPT_COOKIEJAR, "cookie.txt"); //If ever needed...
		curl_setopt($ch, CURLOPT_FOLLOWLOCATION, 1);
		curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, FALSE);

		if (isset($url_parts['user']) and isset($url_parts['pass'])) {
			$custom_headers = array("Authorization: Basic ".base64_encode($url_parts['user'].':'.$url_parts['pass']));
			curl_setopt($ch, CURLOPT_HTTPHEADER, $custom_headers);
		}

		$response = curl_exec($ch);
		$info = curl_getinfo($ch); //Some information on the fetch
		curl_close($ch);

	//////////////////////////////////////////// FSockOpen //////////////////////////////
	} else { //If there is no curl, use fsocketopen
		if (isset($url_parts['query'])) {
			if (isset($options['method']) and $options['method'] == 'post')
				$page = $url_parts['path'];
			else
				$page = $url_parts['path'] . '?' . $url_parts['query'];
		} else {
			$page = $url_parts['path'];
		}

		$fp = fsockopen($url_parts['host'], 80, $errno, $errstr, 30);
		if ($fp) {
	
			// added 04-28-08 EG set a timeout
			if (isset($options['timeout']))
				stream_set_timeout($fp,$options['timeout']);
			
			$out = '';
			if (isset($options['method']) and $options['method'] == 'post' and isset($url_parts['query'])) {
				$out .= "POST $page HTTP/1.1\r\n";
			} else {
				$out .= "GET $page HTTP/1.0\r\n"; //HTTP/1.0 is much easier to handle than HTTP/1.1
			}
			$out .= "Host: $url_parts[host]\r\n";
			$out .= "Accept: $send_header[Accept]\r\n";
			$out .= "User-Agent: {$send_header['User-Agent']}\r\n";
			if (isset($options['modified_since']))
				$out .= "If-Modified-Since: ".gmdate('D, d M Y H:i:s \G\M\T',strtotime($options['modified_since'])) ."\r\n";

			$out .= "Connection: Close\r\n";

			//HTTP Basic Authorization support
			if (isset($url_parts['user']) and isset($url_parts['pass'])) {
				$out .= "Authorization: Basic ".base64_encode($url_parts['user'].':'.$url_parts['pass']) . "\r\n";
			}

			//If the request is post - pass the data in a special way.
			if (isset($options['method']) and $options['method'] == 'post' and $url_parts['query']) {
				$out .= "Content-Type: application/x-www-form-urlencoded\r\n";
				$out .= 'Content-Length: ' . strlen($url_parts['query']) . "\r\n";
				$out .= "\r\n" . $url_parts['query'];
			}
			$out .= "\r\n";

			fwrite($fp, $out);
			while (!feof($fp)) {
				$response .= fgets($fp, 128);
			}
			fclose($fp);
		}
	}

	//Get the headers in an associative array
	$headers = array();

	if ($info['http_code'] == 404) {
		$body = "";
		$headers['Status'] = 404;
	} else {
		//Seperate header and content
		//echo "RESPONSE: ".$response."<BR><BR>\n";
		//exit();
		$separator_position = strpos($response,"\r\n\r\n");
		$header_text = substr($response,0,$separator_position);
		$body = substr($response,$separator_position+4);
	
		// added 04-28-2008 EG if we get a 301 (moved), another set of headers is received,
		if (substr($body,0,5)=="HTTP/") {
			$separator_position = strpos($body,"\r\n\r\n");
			$header_text = substr($body,0,$separator_position);
			$body = substr($body,$separator_position+4);
		}
	
		//echo "SEP: ".$separator_position."<BR><BR>\n";
		//echo "HEADER: ".$header_text."<BR><BR>\n";
		//echo "BODY: ".$body."<BR><BR>\n";

		foreach(explode("\n",$header_text) as $line) {
			$parts = explode(": ",$line);
			if (count($parts) == 2) $headers[$parts[0]] = chop($parts[1]);
		}
	}

	return empty($options['return_info'])
		? $body
		: array('headers' => $headers, 'body' => $body, 'info' => $info)
	;
}
