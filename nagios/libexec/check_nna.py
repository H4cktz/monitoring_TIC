#!/usr/bin/env python
"""
Nagios Network Analyzer Plugin

Check Network Analyzer sources, views, and sourcegroups for abnormal behavior.

"""
import sys
import optparse
try:
    import json
except:
    import simplejson as json
import urllib
import urllib2
import tempfile
import time
import os


# Display a list of options to be sent to the plugin
def parse_args():
    parser = optparse.OptionParser()
    
    # Add the basic options (hostname and api key)
    parser.add_option(  "-H","--hostname",
                        help="The Nagios Network Analyzer server's hostname to be connected to." )
    parser.add_option(  "-K","--key",
                        help="An API key to use for authentication on the connecting Nagios Network Analyzer server.")

    # Add options for type of action to check on
    parser.add_option(  "-m","--metric",
                        help="The type of action to check: 'bytes', 'flows', 'packets', and 'behavior' (Abnormal behavior works on sources only).")

    # Add option for source, sourcegroup, or source & view (name or not... depending on if it's a int)
    parser.add_option(  "-S","--source",
                        help="The source to run the check on. Use SID or Source Name. (Must use only one: source or sourcegroup)")
    parser.add_option(  "-G","--sourcegroup",
                        help="The sourcegroup to run the check on. Use GID or Sourcegroup Name. (Must use only one: source or sourcegroup)")
    
    parser.add_option(  "-v","--view",
                        help="Add a view to a source run. Use VID or View Name. (Must be used with a source only)")

    # Warning and Critical options
    parser.add_option(  "-w","--warning",
                        default=None,
                        type="int",
                        help="Warning value to be passed for the check.")
    parser.add_option(  "-c","--critical",
                        default=None,
                        type="int",
                        help="Critical value to be passed for the check.")

    # Additional options that need to be added just in case
    parser.add_option(  "--verbose",
                        action="store_true",
                        default=False,
                        help="Set true for verbose error output.")
    parser.add_option(  "--noperfdata",
                        action="store_true",
                        default=False,
                        help="Set true for perfdata in the output.")
    parser.add_option(  "--secure",
                        action="store_true",
                        default=False,
                        help="Use secure coonnection (HTTPS) instead of HTTP.")
    parser.add_option(  "--exists",
                        action="store_true",
                        default=None,
                        help="Check to make sure the source, view, or sourcegroup actually exists.")

    options, args = parser.parse_args()
    
    # Verify hostname and api key exists before running
    if not options.hostname:
        parser.error("Hostname is required for use. Use --help for more info.")
    if not options.key:
        parser.error("You must use an API key. Use --help for more info.")

    # Verify that we are running properly for abnormal behavior (only on a source)
    if options.metric == "behavior":
        if not options.source:
            parser.error("You must only use the Abnormal Behavior check on sources. Use --help for more info.")

    # Verify that we are using a view ONLY on a source
    if options.view:
        if not options.source:
            parser.error("You must use a view only if you have a source selected. Use --help for more info.")
    
    # Verify that there is a warning and critical threshhold
    if options.metric != "behavior":
        if not options.warning and not options.critical and not options.exists:
            parser.error("You must set warning and critical values. Use --help for more info.")

    # Verify that only a Source or Sourcegroup is set
    if options.source and options.sourcegroup:
        parser.error("You must use only a Source or Sourcegroup. Use --help for more info.")

    # Verify that the user set a metic type
    if not options.metric and not options.exists:
        parser.error("You must set a metric to use. Use --help for more info.")

    return options


# Main function that generates and sends requests to the NNA server
def main(options):
    url_tmpl = '%s://%s/nagiosna/index.php/api/%s?%%s'

    # Check if secure request
    sec_request = 'http'
    if options.secure:
        sec_request = 'https'

    # Check for the sid, vid, or gid
    if options.source:
        id_type = 'sid'
        id_val = options.source
        text_type = 'source'
    elif options.sourcegroup:
        id_type = 'gid'
        id_val = options.sourcegroup
        text_type = 'group'

    # If it is just checking if something exists lets start here
    if options.exists:
        action = text_type + "s/read"
        q = "q[" + id_type + "]"

        # Check if object type with id exists 
        host = url_tmpl % (sec_request, options.hostname, action)
        gets = {'token'     : options.key,
                q           : id_val }
        gets = dict((k,v) for k,v in gets.iteritems() if v is not None)
        query = urllib.urlencode(gets)
        url = host % query

        # Send request to URL created
        response = urllib2.urlopen(url)
        data = json.load(response)

        if not data:
            print "DOWN - The " + text_type + " you are trying to use doesn't exist"
            sys.exit(2)

        print "UP - " + text_type + " exists"
        sys.exit(0)

    # Do a abnormal behavior check instead of a standard check
    if options.metric == 'behavior':
        action = "graphs/failures"

        # Check for abnormal behavior
        host = url_tmpl % (sec_request, options.hostname, action)
        gets = {'token'     : options.key,
                'sid'       : options.source,
                'begindate' : "-5 minutes",
                'enddate'   : "-1 second"}
        gets = dict((k,v) for k,v in gets.iteritems() if v is not None)
        query = urllib.urlencode(gets)
        url = host % query

        # Send request to URL created
        data = get_url_json(url)
        if data['data'][0]:
            time.sleep(3) # Sleep three seconds and try again (failures may return 0 while calculating)
            data = get_url_json(url)

        # Display error instead of actual data
        if 'error' in data:
            print 'CRITICAL - ' + data['error']
            sys.exit(2)

        # If there is abnormal behavior, send CRITICAL otherwise OK
        if data['data'][0]:
            print 'CRITICAL - Abnormal behavior detected'
            sys.exit(2)
        else:
            print 'OK - No abnormal behavior detected'
            sys.exit(0)

    else:
        action = "graphs/execute"

        # Get metric based on what we sent for -m
        if options.metric == 'bytes':
            get_type = 'q[Bytes]'
        elif options.metric == 'flows':
            get_type = 'q[Flows]'
        elif options.metric == 'packets':
            get_type = 'q[Packets]'

        # Generate URL and add in variables
        host = url_tmpl % (sec_request, options.hostname, action)
        gets = {'token'     : options.key,
                get_type    : options.metric,
                id_type     : id_val,
                'begindate' : "-5 minutes",
                'enddate'   : "-1 second"}

        # Add a view to the source if we are using a view
        if options.view and options.source:
            gets['vid'] = options.view

        gets = dict((k,v) for k,v in gets.iteritems() if v is not None)
        query = urllib.urlencode(gets)
        url = host % query

        # Send request to URL created
        data = get_url_json(url)
        if data[0]['total'] == 0:
            time.sleep(3) # Sleep three seconds and try again (graph data may return 0 while calculating)
            data = get_url_json(url)
       
        # Check for an error returning
        if 'error' in data:
            print 'CRITICAL - ' + data['error']
            sys.exit(2)

        data = data[0]['total']
    
        # Check total with what we have defined for warning and critical
        check_warning_critical(data, options.metric, options.warning, options.critical, options.noperfdata)
    
    sys.exit(0)

# Function for grabbing the request
def get_url_json(url):
    response = urllib2.urlopen(url)
    data = json.load(response)
    return data

# Function to check warning and critical versus the value returned
def check_warning_critical(value, value_type, warning, critical, noperfdata):
    if value >= critical:
        print 'CRITICAL - ' + str(value) + ' ' + value_type + ' sent/recieved' + add_perfdata(value, value_type, noperfdata)
        sys.exit(2)
    elif value >= warning:
        print 'WARNING - ' + str(value) + ' ' + value_type + ' sent/recieved' + add_perfdata(value, value_type, noperfdata)
        sys.exit(1)
    elif value <= warning:
        print 'OK - ' + str(value) + ' ' + value_type + ' sent/recieved' + add_perfdata(value, value_type, noperfdata)
        sys.exit(0)
    else:
        print 'UNKNOWN - Could not read warning/critical threshholds.'
        sys.exit(3)


# Function to add perfdata to an output
def add_perfdata(value, value_type, noperfdata):
    if noperfdata:
        return ''
    else:
        return '|' + value_type + '=' + str(value)

# Main part of the plugin that runs everything
if __name__ == "__main__":
    options = parse_args()
    
    try:
        main(options)
    except Exception, e:
        if options.verbose:
            print "And error was encountered:"
            print e
            sys.exit(3)
        else:
            try:
                main(options, False)
            except Exception, e:
                print 'UNKNOWN - Error occurred while running the plugin.'
                sys.exit(3)