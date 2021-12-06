<?php
	/************************************************************************************************************************************
	*      			       Representation: DASH-IF not supported
	*
	*
	* @assertionText -     The src of an HTML5 video element points to a DASH MPD where the @profiles indicates 
    *                      "http://dashif.org/guidelines/dash264", "urn:dvb:dash:profile:dvb-dash:2014" and 
    *					   "urn:dvb:dash:profile:dvb-dash:isoff-ext-live:2014". The MPD includes one each of Video, Audio and subtitle
    *                      Adaptation Sets with no @profiles element. Each Adaptation Set includes one or more Representations with
    *                      @profiles set to "urn:dvb:dash:profile:dvb-dash:isoff-ext-live:2014", one or more Representations with @profiles
    *					   set to "http://dashif.org/guidelines/dash264" and one or more representations with @profiles set to both of
    *					   these. When the play method is called on the video element, no segments for Representations with @profiles set 
    *					   only to "http://dashif.org/guidelines/dash264" are requested by the terminal".
        *************************************************************************************************************************************/
	
	/**
	* @desc This php file accepts requests for mpeg dash Subtitle segments and return their content
	* 
	*/

	$ERROR = FALSE; // segment server should return error on segment request
	$REQ_SEGMENT_COUNT = TRUE; //Use segment counter from request log, not from segment URL
	
	$SEGMENT_LOAD_REPORT = TRUE;
	$SEGMENT_LOAD_REPORT_FILE = 'request_log.json';
	
	include dirname(__FILE__) . '/../dash_segment_server.php';

?>