<?php
/**
 * @desc This php file accepts requests for mpeg dash segments and return their content.
 *       Optionally this script can generate errors on request, report how many failed retry attempts has happened. 
 *       Script stores relevant information about requests in a session, where each test execution represents single session.
 *       Session keys used to store different types of information are referred as files.
 *
 * @param - $ERROR - boolean value that indicates if segment server should return error on segment request
 * @param - $ERROR_CODE - header value that includes status code and message (eg. HTTP 200 OK)
 * @param - $ERROR_SEGMENT - request for specified segment will return response with specified error
 * @param - $REPORT - boolean value that indicates if segment server should create json report
 * @param - $REPORT_FILE - Session key under which report is stored, formatted as .json file
 * @param - $REPORT_JSON - name of property in json report
 * @param - $REQUEST_LOG - if true, segment server will log every segment request into the session
 * @param - $REQ_SEGMENT_COUNT - if set and true set segment counter from request log, not from segment URL ($REQUEST_LOG required as true)
 * @param - $SEGMENT_LOAD_REPORT - if set it creates an extensive log of the load sequence of the segments (baseURL, segment id, url, UnixDate, HTTPDate [$RFC7231_Format])
 * @param - $SEGMENT_LOAD_REPORT_FILE - key to be used within session to store load report, it must be defined when $SEGMENT_LOAD_REPORT is set
 * @param - $ERROR_CONTENT - custom content of the error response
 * @param - $LOG_MPD_REQUESTS - if set and true, MPD request will be logged in specified json file 

 * @author 
 * RT-RK Institute for Computer Based Systems LLC 2017
 * 
 * @license
 * This material is licensed under the HbbTV Test Suite License Agreement 
 * and any use of this material not in accordance with that agreement is strictly prohibited.
 *
 */

class cSegList {
    
    public $sDashDir = '';

    public function __construct($sURL) {

        $this->sDashDir = dirname(__FILE__) . '/';
        
        $aURL = explode('/', $sURL);
        $sURL = "{$aURL[2]}/$aURL[3]";

        $aSegList = $this->parseSegList($this->sDashDir . $aURL[0] . '/seglist.xml');

        if (key_exists($sURL, $aSegList)) {

            header("HTTP 200 OK");
            header('Content-Description: File Transfer');

            $aSegment = $aSegList[$sURL];

            $fp = fopen($this->sDashDir . "$aURL[0]/{$aSegment['video']}", 'r');


            $this->my_fseek($fp, floatval($aSegment['start']));
            $sContentType = (in_array($aURL[2], array('audio', 'video', 'subtitle')))? (($aURL[2]==='subtitle')?'application':$aURL[2]) : 'video';
            header('Content-type: ' . $sContentType . '/mp4');

            echo fread($fp, $aSegment['size']);

            fclose($fp);
        } else {
            header("HTTP/1.0 404 Not Found");
        }
    }

    private function my_fseek($fp, $pos, $first = 0) {

        // set to 0 pos initially, one-time
        if ($first)
            fseek($fp, 0, SEEK_SET);

        // get pos float value
        $pos = floatval($pos);

        // within limits, use normal fseek
        if ($pos <= PHP_INT_MAX)
            fseek($fp, $pos, SEEK_CUR);

        // out of limits, use recursive fseek
        else {
            fseek($fp, PHP_INT_MAX, SEEK_CUR);
            $pos -= PHP_INT_MAX;
            $this->my_fseek($fp, $pos);
        }
    }

    private function parseSegList($sXMLFile) {
        $aFiles = array();

        $xmlparser = xml_parser_create();
        $xmldata = file_get_contents($sXMLFile);
        xml_parse_into_struct($xmlparser, $xmldata, $elements);
        xml_parser_free($xmlparser);

        foreach ($elements as $K => $V) {

            if ($V['tag'] == 'FILE' && $V['type'] == 'open') {
                $sLastFile = $V['attributes']['REF'];
                $aFiles[$sLastFile] = array();
            }

            if ($V['type'] == 'complete') {
                $aFiles[$sLastFile][strtolower($V['tag'])] = $V['value'];
            }
        }

        return $aFiles;
    }

}

$ERROR = isset($ERROR) ? $ERROR : false;
$REPORT = isset($REPORT) ? $REPORT : false;
$REQUEST_LOG = isset($REQUEST_LOG) ? $REQUEST_LOG : false;
$SEGMENT_LOAD_REPORT = isset($SEGMENT_LOAD_REPORT) ? $SEGMENT_LOAD_REPORT : false;
$ERROR_CONTENT = isset($ERROR_CONTENT) ? $ERROR_CONTENT : '';
$LOG_MPD_REQUESTS = isset($LOG_MPD_REQUESTS) ? $LOG_MPD_REQUESTS : false;

$REQUEST_LOG_FILE = 'request_log.json';

if (!isset($_GET['sid'])) {
    header('HTTP/1.1 400 Bad Request');
    die("Request does not contain session ID as the GET parameter.");
}
$sid = $_GET['sid'];
session_id($sid); 
session_start();


$unixTimestamp = (double)millitime();
$dt = new DateTime('UTC');
$RFC7231_Format = $dt->format('D, d M Y H:i:s \G\M\T'); // ETSI TS 103 285 V1.1.1 (2015-05) 4.7.2 Service Provider Requirements


    preg_match("/[^_]+\\_(\\d+)\\./", $_GET['url'], $matches);
    $realSegment = 0;
    
    if(isset($matches[1])) {
        $segment = (int) $matches[1];
        $realSegment = $segment;
    } else {
        $segment = false;
    }    

    if ($REQUEST_LOG) {
        
        $url =  "{$_SERVER['HTTP_HOST']}{$_SERVER['REQUEST_URI']}";
        
        if (isset($_SESSION[$REQUEST_LOG_FILE])) {
            // Get serialized list from session, add item to it, serialize it back to session
            $url_array = json_decode($_SESSION[$REQUEST_LOG_FILE]);
            array_push($url_array, $url);
            $_SESSION[$REQUEST_LOG_FILE] = json_encode($url_array);
        }
        else {
            // if session key doesn't exist create it
            // transform http query to json string
            $url_array = array($url);
            $_SESSION[$REQUEST_LOG_FILE] = json_encode($url_array);
        }

        if (isset($REQ_SEGMENT_COUNT) and $REQ_SEGMENT_COUNT===TRUE) { //set segment counter from request log, not from segment URL
            $segment = count($url_array) - 1; // minus one, because we don't count init request
        }

    }


    if ($SEGMENT_LOAD_REPORT) {
        //check if session file exists
        if (isset($_SESSION[$SEGMENT_LOAD_REPORT_FILE])) {
            $loadReport = (array) json_decode($_SESSION[$SEGMENT_LOAD_REPORT_FILE]);
        } else {
            $loadReport = array();
        }
        
        
        if (isset($REQ_SEGMENT_COUNT) and $REQ_SEGMENT_COUNT===TRUE) { //set segment counter from request log, not from segment URL
            $segment = count($loadReport); // init request is 0 / when $loadReport = array()
        }

        $loadReport[] = array(
            'baseURL' => "{$_SERVER['HTTP_HOST']}{$_SERVER['REQUEST_URI']}",
            'segment' => $realSegment,
            'url' => $_GET['url'],
            'UnixDate' => $unixTimestamp,
            'HTTPDate' => $RFC7231_Format,
            'isErrorSegment' => !!( $ERROR && $segment === $ERROR_SEGMENT || $_SESSION['ERROR_SEGMENT_URL'] === $_GET['url'] )
        );
        $_SESSION[$SEGMENT_LOAD_REPORT_FILE] = json_encode($loadReport);
    }

    // instruct dash_static_mpd_serve.php and dash_dynamic_serve.php to write MPD request in specified json file
    // used in tests where MPD needs to reload and MPD request is then logged with other segment requests
    if ($LOG_MPD_REQUESTS) {
        if($SEGMENT_LOAD_REPORT) {
            $_SESSION['LOG_MPD_REQUESTS'] = $SEGMENT_LOAD_REPORT_FILE;
        } elseif($REQUEST_LOG) {
            $_SESSION['LOG_MPD_REQUESTS'] = $REQUEST_LOG_FILE;
        }
    }

    // if server should report error after specified segment number, or segment is already served as error segment it should be served again as error segment
    if ( $ERROR && ($ERROR_SEGMENT != -1) && ($segment == $ERROR_SEGMENT)) {

        // Remember first segment on which error ocurred, so that we can see if there was retry attempt.
        if ($segment === $ERROR_SEGMENT) {
            $_SESSION['ERROR_SEGMENT_URL'] = $_GET['url'];            
        }
        header($ERROR_CODE);

        echo($ERROR_CONTENT); //if $ERROR_CONTENT is set

    } else {

        $_SESSION['LOADCOUNT'] ++;

        if ($REPORT) {
            $report[$REPORT_JSON] = true;
            $_SESSION[$REPORT_FILE] =  json_encode($report);
        }
        
        //do not block the session while segment data is transferred
        session_write_close();

        $oSegList = new cSegList($_GET['url']);
    }


function returnJSON($aJSON) {
    header('Content-Type: application/json');
    $aJSON['action'] = $_GET['action'];
    $aJSON['status'] = 'OK';
    echo json_encode($aJSON);
}

/**
 *  Returns UnixTimeStamp in milliseconds as String 
 */
function millitime() {
    $microtime = microtime();

    $comps = explode(' ', $microtime);

    // Note: Using a string here to prevent loss of precision
    // in case of "overflow" (PHP converts it to a double)
    return sprintf('%d%03d', $comps[1], $comps[0] * 1000);
  }

?>