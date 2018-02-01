#!/usr/bin/php
<?php
/*

check_nagios_performance.php - nagios plugin

#Originally written by Hendrik Baecker in 2007 in perl
#Revised and rewritten in php by Mike Guthrie - Nagios Enterprises 2011

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. 
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details. 
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA. 

*/


//$out = print_r($argv);
$states = array('OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2, 'UNKNOWN' => 3);
$state = 'OK';
// path to util.pm !!
$lib = "/usr/local/nagios/libexec";

// path to your nagiostats binary
$bin = '/usr/local/nagios/bin/nagiostats';

// path to your external command file
$nagios_extcmd_file = "/usr/local/nagios/var/rw/nagios.cmd";

$commands = array(
    //active checks    //on-demand           //scheduled        //total checked
    'ahc1' => "NUMOACTHSTCHECKS1M,NUMSACTHSTCHECKS1M,NUMACTHSTCHECKS1M",
    'ahc5' => "NUMOACTHSTCHECKS5M,NUMSACTHSTCHECKS5M,NUMACTHSTCHECKS5M",
    'ahc15' => "NUMOACTHSTCHECKS15M,NUMSACTHSTCHECKS15M,NUMACTHSTCHECKS15M",
    'asc1' => "NUMOACTSVCCHECKS1M,NUMSACTSVCCHECKS1M,NUMACTSVCCHECKS1M",
    'asc5' => "NUMOACTSVCCHECKS5M,NUMSACTSVCCHECKS5M,NUMACTSVCCHECKS5M",
    'asc15' => "NUMOACTSVCCHECKS15M,NUMSACTSVCCHECKS15M,NUMACTSVCCHECKS15M",
    //passive checks totals
    'phc1' => "NUMPSVHSTCHECKS1M",
    'phc5' => "NUMPSVHSTCHECKS5M",
    'phc15' => "NUMPSVHSTCHECKS15M",
    'psc1' => "NUMPSVSVCCHECKS1M",
    'psc5' => "NUMPSVSVCCHECKS5M",
    'psc15' => "NUMPSVSVCCHECKS15M",
    //problem counts
    'sprob' => 'NUMSVCPROB',
    'hprob' => 'NUMHSTPROB',
    //execution times average   -- need to divide by 1000 (in ms)
    'hxt' => 'AVGACTHSTEXT',
    'sxt' => 'AVGACTSVCEXT',
    //latencies average      // -- need to divide by 1000 (in ms)
    'ahlat' => 'AVGACTHSTLAT',
    'aslat' => 'AVGACTSVCLAT',
    'phlat' => 'AVGPSVHSTLAT',
    'pslat' => 'AVGPSVSVCLAT',
    //command buffer usage
    'ucb' => 'USEDCMDBUF',
    'hcb' => 'HIGHCMDBUF',
    //external command usage
    'eco1' => 'NUMEXTCMDS1M',
    'eco5' => 'NUMEXTCMDS5M',
    'eco15' => 'NUMEXTCMDS15M',

);

//check for valid command option 
if (array_key_exists(trim($argv[1]), $commands)) {

    $chk = $argv[1];
    $warn = isset($argv[2]) ? $argv[2] : '';
    $crit = isset($argv[3]) ? $argv[3] : '';
    $multi = array('ahc1', 'ahc5', 'ahc15', 'asc1', 'asc5', 'asc15'); //array keys that will return multiple values
    //handle multiple values
    if (in_array($chk, $multi)) {
        $pre = "$bin -m -D ';' -d "; //command prefix
        $cmd = $pre . $commands[$chk]; //assemble the full command
        $data = exec($cmd);
        //explode values to create output
        $vals = explode(';', $data); //0 is on-demand, 1 is scheduled, 2 is total
        if ($crit != '' && $vals[2] >= $crit) $state = 'CRITICAL';
        elseif ($warn != '' && $vals[2] >= $warn) $state = 'WARNING';
        $output = return_output($chk, $vals);
        //printf("My multiple values are: ".$data."\n");
        printf($output);
        exit($states[$state]);
    } else //handle single value
    {
        $pre = "$bin -m -d"; //command prefix
        $cmd = $pre . $commands[$chk]; //assemble the full command
        $data = exec($cmd);
        //if(!$data) $data=0;
        //check against array keys that will return milliseconds
        $ms = array('hxt', 'sxt', 'ahlat', 'phlat', 'aslat', 'pslat');
        if (in_array($chk, $ms)) $data = $data * .0001; //convert to milliseconds
        //check thresholds
        if ($crit != '' && trim($data) >= $crit) $state = 'CRITICAL';
        elseif ($warn != '' && trim($data) >= $warn) $state = 'WARNING';

        //output
        $output = return_output($chk, $data);
        printf($output);
        exit($states[$state]);
    } //end single value IF
} //end IF for valid command option 
else printf("ERROR: invalid option " . $argv[1] . "\n");
exit($states['UNKNOWN']);


/**
 * @param $arg
 * @param $data
 *
 * @return string
 */
function return_output($arg, $data)
{
    global $warn;
    global $crit;
    global $state;

    $wc = $warn . ';' . $crit . ';';
    $output = $state . ' - ';
    //multi-D array for plugin output
    switch ($arg) {
        //active checks
        case 'ahc1':
        case 'ahc5':
        case 'ahc15':
        case  'asc1':
        case    'asc5':
        case 'asc15':
            $output .= "" . _('Total Checks:') . "{$data[2]}; " . _('On-Demand:') . "{$data[0]}; " . _('Scheduled:') . "{$data[1]} | Total_Checks={$data[2]};$wc On_Demand={$data[0]};$wc Sched_Checks={$data[1]};$wc";
            break;
        //passive checks totals
        case 'phc1':
        case 'psc1':
            $output .= "" . _('Passive Checks Last') . " 1mn:$data; | Passive_Checks_1mn=$data;$wc";
            break;
        case 'phc5':
        case 'psc5':
            $output .= "" . _('Passive Checks Last') . " 5mn:$data; | Passive_Checks_5mn=$data;$wc";
            break;
        case 'phc15':
        case 'psc15':
            $output .= "" . _('Passive Checks Last') . " 15mn:$data; | Passive_Checks_15mn=$data;$wc";
            break;

        //problem counts
        case 'sprob' :
            $output .= "$data " . _('service problems') . "; | service_problems=$data;$wc";
            break;
        case 'hprob':
            $output .= "$data " . _('host problems') . "; | host_problems=$data;$wc";
            break;

        //execution times average   -- need to divide by 1000 (in ms)
        case 'hxt':
        case 'sxt':
            $output .= "" . _('Average execution time:') . "{$data}ms | Execution_time={$data}ms;$wc";
            break;

        //latencies average      // -- need to divide by 1000 (in ms)
        case 'ahlat' :
        case 'aslat' :
        case 'phlat' :
        case 'pslat' :
            $output .= "Average latency:{$data}ms | Avg_Latency={$data}ms;$wc";
            break;

        //command buffer usage
        case 'ucb' :
            $output .= "C" . _('urrent command buffer usage:') . "{$data} | Command_buffer_usage={$data};$wc";
            break;
        case 'hcb':
            $output .= "" . _('High command buffer usage:') . "{$data} | High_command_buffer_usage={$data};$wc";
            break;

        //external command usage
        case 'eco1' :
            $output .= "" . _('External commands last') . " 1mn:{$data} | External_command_last_1mn={$data};$wc";
            break;
        case 'eco5' :
            $output .= "" . _('External commands last') . " 5mn:{$data} | External_command_last_5mn={$data};$wc";
            break;
        case 'eco15' :
            $output .= "" . _('External commands last') . " 15mn:{$data} | External_command_last_15mn={$data};$wc";
            break;

    } //end switch
    //append thresholds if applicable
    $output .= "\n";
    return $output;

}


?>