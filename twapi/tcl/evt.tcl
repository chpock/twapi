if {0} {
set hq [evt_query -channel Application]
set hrc [evt_render_context_xpaths [list "Event/System/Provider/@Name" "Event/System/EventID"]]
set hevt [lindex [evt_next $hq] 0]
set hvals [twapi::Twapi_EvtRenderValues $hrc $hevt NULL]
::twapi::Twapi_ExtractEVT_RENDER_VALUES $hvals
::twapi::evt_free_EVT_RENDER_VALUES $hvals


    31  set hq [evt_query -channel Application]
    32  set hevt [lindex [evt_next $hq] 0]
    33  set hrcs [evt_render_context_system]
    34  set hrcu [evt_render_context_user]
    35  set sbuf [twapi::Twapi_EvtRenderValues $hrcs $hevt NULL]
    36  set ubuf [twapi::Twapi_EvtRenderValues $hrcu $hevt NULL]
    37  proc extract {b} {::twapi::Twapi_ExtractEVT_RENDER_VALUES $b}
    38  extract $sbuf
    39  extract $ubuf
    40  set hpub [evt_open_publisher_metadata Microsoft-Windows-CertificateServicesClient]
    41  evt_publisher_metadata_property $hpub
    42  evt_publisher_metadata_property $hpub -levels
    43  evt_publisher_metadata_property $hpub -resourcefilepath -parameterfilepath -messagefilepath
    44  evt_publisher_events_metadata $hpub
    45  evt_publisher_events_metadata $hpub -id -messageid -template
    46  evt_publisher_events_metadata $hpub -id -messageid
    47  evt_format_event $hevt
    48  extract $sbuf
    49  evt_format_publisher_message $hpub 2952790018
    50  set hevt [lindex [evt_next $hq] 0]
    51  evt_format_event $hevt
    52  set hevt [lindex [evt_next $hq] 0]
    53  evt_format_event $hevt

(twapi) 55 % evt_format_event [set hevt [lindex [evt_next $hq] 0]]
The EventSystem sub system is suppressing duplicate event log entries for a duration of 86400 seconds.  The suppression timeout can be controlled by a REG_DWORD value named SuppressDuplicateDuration under the following registry key: HKLM\Software\Microsoft\EventSystem\EventLog.
(twapi) 56 % set sbuf [twapi::Twapi_EvtRenderValues $hrcs $hevt NULL]
2770112 TwapiEVT_RENDER_VALUES_HEADER*
(twapi) 57 % set ubuf [twapi::Twapi_EvtRenderValues $hrcu $hevt NULL]
2774136 TwapiEVT_RENDER_VALUES_HEADER*
(twapi) 58 % extract $ubuf
86400 SuppressDuplicateDuration {Software\Microsoft\EventSystem\EventLog}
(twapi) 59 % evt_close $hpub
(twapi) 60 % extract $sbuf
Microsoft-Windows-EventSystem {{899DAACE-4868-4295-AFCD-9EB8FB497561}} 4625 16384 4 0 0 {} 129146191710000000 4 {} {} 0 0 Application 37L4247E20-12 {} 0
(twapi) 61 % set hpub [evt_open_publisher_metadata Microsoft-Windows-EventSystem]
5 EVT_HANDLE
(twapi) 62 % evt_publisher_events_metadata $hpub -id -messageid
{-id 512 -messageid 512} {-id 2147488002 -messageid 2147488002} {-id 2147488003 -messageid 2147488003} {-id 2147488004 -messageid 2147488004} {-id 2147488005 -messageid 2147488005} {-id 2147488006 -messageid 2147488006} {-id 2147488007 -messageid 2147488007} {-id 2147488009 -messageid 2147488009} {-id 2147488010 -messageid 2147488010} {-id 3221230081 -messageid 3221230081} {-id 3221230082 -messageid 3221230082} {-id 3221230083 -messageid 3221230083} {-id 3221230084 -messageid 3221230084} {-id 3221230085 -messageid 3221230085} {-id 3221230086 -messageid 3221230086} {-id 3221230087 -messageid 3221230087} {-id 3221230088 -messageid 3221230088} {-id 3221230089 -messageid 3221230089} {-id 3221230090 -messageid 3221230090} {-id 3221230091 -messageid 3221230091} {-id 3221230092 -messageid 3221230092} {-id 3221230093 -messageid 3221230093} {-id 3221230094 -messageid 3221230094} {-id 3221230095 -messageid 3221230095} {-id 3221230096 -messageid 3221230096} {-id 1073746449 -messageid 1073746449}
(twapi) 63 % evt_format_publisher_message $hpub 512
The substitution string for insert index (%1) could not be found.
(twapi) 64 % evt_format_publisher_message $hpub 512 -values $ubuf
86400
(twapi) 65 % evt_format_publisher_message $hpub 2147488004
The substitution string for insert index (%1) could not be found.
(twapi) 66 % evt_format_publisher_message $hpub 512 -values $ubuf
86400
(twapi) 67 % evt_format_publisher_message $hpub 2147488004 -values $ubuf
The COM+ Event System failed to create an instance of the subscriber SuppressDuplicateDuration.  Software\Microsoft\EventSystem\EventLog returned HRESULT 86400.
(twapi) 68 % evt_get_event_system_fields $hevt
-providername Microsoft-Windows-EventSystem -providerguid {{899DAACE-4868-4295-AFCD-9EB8FB497561}} -eventid 4625 -qualifiers 16384 -level 4 -task 0 -opcode 0 -keywords {} -timecreated 129146191710000000 -eventrecordid 4 -activityid {} -relatedactivityid {} -processid 0 -threadid 0 -channel Application -computer 37L4247E20-12 -userid {} -version 0
(twapi) 69 % format %x 4625
1211
(twapi) 70 % format %x 2147488004
80001104
(twapi) 71 % format %x 1073746449
40001211
(twapi) 72 % evt_format_publisher_message $hpub 4625 -values $ubuf
the message resource is present but the message is not found in the string/message table
(twapi) 73 % evt_format_publisher_message $hpub 0x40001211 -values $ubuf
The EventSystem sub system is suppressing duplicate event log entries for a duration of 86400 seconds.  The suppression timeout can be controlled by a REG_DWORD value named SuppressDuplicateDuration under the following registry key: HKLM\Software\Microsoft\EventSystem\EventLog.
(twapi) 74 % evt_format_publisher_message $hpub 0x40001211 -values $ubuf
The EventSystem sub system is suppressing duplicate event log entries for a duration of 86400 seconds.  The suppression timeout can be controlled by a REG_DWORD value named SuppressDuplicateDuration under the following registry key: HKLM\Software\Microsoft\EventSystem\EventLog.
(twapi) 74 % format %x 16384
4000


Above implies that the message lookup is done by using -qualifiers (16384)
field from event system fields as the top 16 bits of event id ? Or perhaps
the 4 comes from the level ?

}

#
# Copyright (c) 2012, Ashok P. Nadkarni
# All rights reserved.
#
# See the file LICENSE for license

# Event log handling for Vista and later

namespace eval twapi {
    # We cache the render context used for getting system fields from event
    # as this is required for every event. It is an array with two elements
    #  handle - is the handle to the maintaned context
    #  buffer - is NULL or holds a pointer to the buffer used to retrieve
    #    values so does not have to be reallocated every time.
    variable _evt_system_render_context


    # Cache mapping publisher names to their meta information handles
    # Dictionary indexed with nested keys - publisher, session, lcid
    # TBD - need a mechanism to clear ?
    variable _evt_publisher_handles

    proc _evt_init {} {
        variable _evt_system_render_context
        variable _evt_publisher_handles

        set _evt_system_render_context(handle) [evt_render_context_system]
        set _evt_system_render_context(buffer) NULL

        set _evt_publisher_handles [dict create]

        # No-op the proc once init is done
        proc _evt_init {} {}
    }
}

# TBD - document
proc twapi::evt_local_session {} {
    return NULL
}

# TBD - document
proc twapi::evt_open_session {server args} {
    array set opts [parseargs args {
        user.arg
        domain.arg
        {password.arg ""}
        {authtype.arg 0}
    } -maxleftover 0]

    if {![string is integer -strict $opts(authtype)]} {
        set opts(authtype) [dict get {default 0 negotiate 1 kerberos 2 ntlm 3} [string tolower $opts(authtype)]]
    }

    if {![info exists opts(user)]} {
        set opts(user) $::env(USERNAME)
    }

    if {![info exists opts(domain)]} {
        set opts(domain) $::env(USERDOMAIN)
    }

    return [EvtOpenSession 1 [list $server $opts(user) $opts(domain) $opts(password) $opts(authtype)] 0 0]
}

# TBD - document
proc twapi::evt_channels {{hevtsess NULL}} {
    set chnames {}
    set hevt [EvtOpenChannelEnum $hevtsess 0]
    trap {
        while {[set chname [EvtNextChannelPath $hevt]] ne ""} {
            lappend chnames $chname
        }
    } finally {
        evt_close $hevt
    }

    return $chnames
}

# TBD - document
proc twapi::evt_clear_log {chanpath args} {
    array set opts [parseargs args {
        {session.arg NULL}
        {backup.arg ""}
    } -maxleftover 0]

    return [EvtClearLog $opts(session) $chanpath $opts(backup) 0]
}

# TBD - document
proc twapi::evt_archive_exported_log {logpath args} {
    array set opts [parseargs args {
        {session.arg NULL}
        {lcid.int 0}
    } -maxleftover 0]

    return [EvtArchiveExportedLog $opts(session) $logpath $opts(lcid) 0]
}

# TBD - document
proc twapi::evt_export_log {outfile args} {
    array set opts [parseargs args {
        {session.arg NULL}
        file.arg
        channel.arg
        {query.arg *}
        {ignorequeryerrors 0 0x1000}
    } -maxleftover 0]

    if {([info exists opts(file)] && [info exists opts(channel)]) ||
        ! ([info exists opts(file)] || [info exists opts(channel)])} {
        error "Exactly one of -file or -channel must be specified."
    }

    if {[info exists opts(file)]} {
        set path $opts(file)
        incr opts(ignorequeryerrors) 2
    } else {
        set path $opts(channel)
        incr opts(ignorequeryerrors) 1
    }

    return [EvtExportLog $opts(session) $path $opts(query) $outfile $opts(ignorequeryerrors)]
}

# TBD - document
proc twapi::evt_create_bookmark {{mark ""}} {
    return [EvtCreateBookmark $mark]
}

# TBD - document
proc twapi::evt_render_context_xpaths {xpaths} {
    return [EvtCreateRenderContext $xpaths 0]
}

# TBD - document
proc twapi::evt_render_context_system {} {
    return [EvtCreateRenderContext {} 1]
}

# TBD - document
proc twapi::evt_render_context_user {} {
    return [EvtCreateRenderContext {} 2]
}

# TBD - document
proc twapi::evt_open_channel_config {chanpath args} {
    array set opts [parseargs args {
        {session.arg NULL}
    } -maxleftover 0]

    return [EvtOpenChannelConfig $opts(session) $chanpath 0]
}

# TBD - document
proc twapi::evt_get_channel_config {hevt args} {
    set result {}
    foreach opt $args {
        lappend result $opt \
            [EvtGetChannelConfigProperty $hevt \
                 [_evt_map_channel_config_property $hevt $propid]]
    }
    return $result
}

# TBD - document
proc twapi::evt_set_channel_config {hevt propid val} {
    return [EvtSetChannelConfigProperty $hevt [_evt_map_channel_config_property $propid 0 $val]]
}


# TBD - document
proc twapi::_evt_map_channel_config_property {propid} {
    if {[string is integer -strict $propid]} {
        return $propid
    }
    
    # Note: values are from winevt.h, Win7 SDK has typos for last few
    return [dict get {
        -enabled                  0
        -isolation                1
        -type                     2
        -owningpublisher          3
        -classiceventlog          4
        -access                   5
        -loggingretention         6
        -loggingautobackup        7
        -loggingmaxsize           8
        -logginglogfilepath       9
        -publishinglevel          10
        -publishingkeywords       11
        -publishingcontrolguid    12
        -publishingbuffersize     13
        -publishingminbuffers     14
        -publishingmaxbuffers     15
        -publishinglatency        16
        -publishingclocktype      17
        -publishingsidtype        18
        -publisherlist            19
        -publishingfilemax        20
    } $propid]
}

# TBD - document
proc twapi::evt_event_info {hevt args} {
    set result {}
    foreach opt $args {
        lappend result $opt [EvtGetEventInfo $hevt \
                                 [dict get {-queryids 0 -path 1}]]
    }
    return $result
}


# TBD - document
proc twapi::evt_event_metadata_property {hevt args} {
    set result {}
    foreach opt $args {
        lappend result $opt \
            [EvtGetEventMetadataProperty $hevt \
                 [dict get {
                     -id 0 -version 1 -channel 2 -level 3
                     -opcode 4 -task 5 -keyword 6 -messageid 7 -template 8
                 } $opt]]
    }
    return $result
}


# TBD - document
proc twapi::evt_log_info {hevt args} {
    set result {}
    foreach opt $args {
        lappend result $opt  [EvtGetLogInfo $hevt [dict get {
            -creationtime 0 -lastaccesstime 1 -lastwritetime 2
            -filesize 3 -attributes 4 -numberoflogrecords 5
            -oldestrecordnumber 6 -full 7
        } $opt]]
    }
    return $result
}

# TBD - document
proc twapi::evt_publisher_metadata_property {hpub args} {
    set result {}
    foreach opt $args {
        set val [EvtGetPublisherMetadataProperty $hpub [dict get {
            -publisherguid 0  -resourcefilepath 1 -parameterfilepath 2
            -messagefilepath 3 -helplink 4 -publishermessageid 5
            -channelreferences 6 -levels 12 -tasks 16
            -opcodes 21 -keywords 25
        } $opt] 0]
        if {$opt ni {-channelreferences -levels -tasks -opcodes -keywords}} {
            lappend result $opt $val
            continue
        }
        set n [EvtGetObjectArraySize $val]
        set val2 {}
        for {set i 0} {$i < $n} {incr i} {
            set rec {}
            foreach {opt2 iopt} [dict get {
                -channelreferences { -channelreferencepath 7
                    -channelreferenceindex 8 -channelreferenceid 9
                    -channelreferenceflags 10 -channelreferencemessageid 11}
                -levels { -levelname 13 -levelvalue 14 -levelmessageid 15 }
                -tasks { -taskname 17 -taskeventguid 18 -taskvalue 19
                    -taskmessageid 20}
                -opcodes {-opcodename 22 -opcodevalue 23 -opcodemessageid 24}
                -keywords {-keywordname 26 -keywordvalue 27
                    -keywordmessageid 28}
            } $opt] {
                lappend rec $opt2 [EvtGetObjectArrayProperty $val $iopt $i]
            }
            lappend val2 $rec
        }

        evt_close $val
        lappend result $opt $val2
    }
    return $result
}

# TBD - document
proc twapi::evt_query_info {hq args} {
    set result {}
    foreach opt $args {
        lappend result $opt  [EvtGetQueryInfo $hq [dict get {
            -names 1 statuses 2
        } $opt]]
    }
    return $result
}

# TBD - document
proc twapi::evt_object_array_size {hevt} {
    return [EvtGetObjectArraySize $hevt]
}

# TBD - document
proc twapi::evt_object_array_property {hevt index args} {
    set result {}

    foreach opt $args {
        lappend result $opt \
            [EvtGetObjectArrayProperty $hevt [dict get {
                -channelreferencepath 7
                -channelreferenceindex 8 -channelreferenceid 9
                -channelreferenceflags 10 -channelreferencemessageid 11
                -levelname 13 -levelvalue 14 -levelmessageid 15
                -taskname 17 -taskeventguid 18 -taskvalue 19
                -taskmessageid 20 -opcodename 22
                -opcodevalue 23 -opcodemessageid 24
                -keywordname 26 -keywordvalue 27 -keywordmessageid 28
            }] $index]
    }
    return $result
}

# TBD - document
proc twapi::evt_publishers {{hsess NULL}} {
    set pubs {}
    set hevt [EvtOpenPublisherEnum $hsess 0]
    trap {
        while {[set pub [EvtNextPublisherId $hevt]] ne ""} {
            lappend pubs $pub
        }
    } finally {
        evt_close $hevt
    }

    return $pubs
}

# TBD - document
proc twapi::evt_open_publisher_metadata {pub args} {
    array set opts [parseargs args {
        {session.arg NULL}
        logfile.arg
        lcid.int
    } -nulldefault -maxleftover 0]

    return [EvtOpenPublisherMetadata $opts(session) $pub $opts(logfile) $opts(lcid) 0]
}

# TBD - document
proc twapi::evt_publisher_events_metadata {hpub args} {
    set henum [EvtOpenEventMetadataEnum $hpub]

    # It is faster to build a list and then have Tcl shimmer to a dict when
    # required
    set meta {}
    trap {
        while {[set hmeta [EvtNextEventMetadata $henum 0]] ne ""} {
            lappend meta [evt_event_metadata_property $hmeta {*}$args]
            evt_close $hmeta
        }
    } finally {
        evt_close $henum
    }
    
    return $meta
}

proc twapi::evt_query {args} {
    array set opts [parseargs args {
        {session.arg NULL}
        file.arg
        channel.arg
        {query.arg ""}
        {ignorequeryerrors 0 0x1000}
        {direction.arg forward}
    } -maxleftover 0]

    if {([info exists opts(file)] && [info exists opts(channel)]) ||
        ! ([info exists opts(file)] || [info exists opts(channel)])} {
        error "Exactly one of -file or -channel must be specified."
    }
    
    set flags $opts(ignorequeryerrors)
    incr flags [dict get {forward 0x100 reverse 0x200 backward 0x200} $opts(direction)]

    if {[info exists opts(file)]} {
        set path $opts(file)
        incr flags 0x2
    } else {
        set path $opts(channel)
        incr flags 0x1
    }

    return [EvtQuery $opts(session) $path $opts(query) $flags]
}

proc twapi::evt_next {hresultset args} {
    array set opts [parseargs args {
        {timeout.int -1}
        {count.int 1}
    } -maxleftover 0]

    return [EvtNext $hresultset $opts(count) $opts(timeout) 0]
}

# TBD - document
proc twapi::evt_decode_event_system_fields {hevt} {
    _evt_init

    proc evt_decode_event_system_fields {hevt} {
        variable _evt_system_render_context
        set _evt_system_render_context(buffer) [Twapi_EvtRenderValues $_evt_system_render_context(handle) $hevt $_evt_system_render_context(buffer)]
        return [twine {
            -providername -providerguid -eventid -qualifiers -level -task
            -opcode -keywordmask -timecreated -eventrecordid -activityid
            -relatedactivityid -processid -threadid -channel
            -computer -userid -version
        } [Twapi_ExtractEVT_RENDER_VALUES $_evt_system_render_context(buffer)]]
    }

    return [evt_get_event_system_fields $hevt]
}

proc twapi::evt_decode_event {args} {
    _evt_init

    proc evt_decode_event {hevt args} {

        array set opts [parseargs args {
            hpublisher.arg
            {values.arg NULL}
            {session.arg NULL}
            {logfile.arg ""}
            {lcid.int 0}
            ignorestring.arg
            message
            levelname
            taskname
            opcodename
            keywords
            channel
            xml
        } -ignoreunknown -hyphenated]
        
        set decoded [evt_get_event_system_fields $hevt]

        if {[info exists opts(-hpublisher)]} {
            set hpub $opts(-hpublisher)
        } else {
            # Get publisher from hevt
            variable _evt_publisher_handles

            set publisher [dict get $decoded -providername]
            if {! [dict exists $_evt_publisher_handles $publisher $opts(-session) $opts(-lcid)]} {
                dict set _evt_publisher_handles $publisher $opts(-session) $opts(-lcid) [EvtOpenPublisherMetadata $opts(-session) $publisher $opts(-logfile) $opts(-lcid) 0]
            }
            set hpub [dict get $_evt_publisher_handles $publisher $opts(-session) $opts(-lcid)]
        }

        foreach {opt optind} {
            -message 1
            -levelname 2
            -taskname 3
            -opcodename 4
            -keywords 5
            -channel 6
            -xml 9
        } {
            if {$opts($opt)} {
                if {$opt in {-level -task -opcode} &&
                    [dict get $decoded $opt] == 0 &&
                    [info exists opts(-ignorestring)]} {
                    # Don't bother making the call.
                    lappend decoded $opt $opts(-ignorestring)
                } else {
                    if {[info exists opts(-ignorestring)]} {
                        lappend decoded $opt [EvtFormatMessage $hpub $hevt 0 $opts(-values) $optind $opts(-ignorestring)]
                    } else {
                        lappend decoded $opt [EvtFormatMessage $hpub $hevt 0 $opts(-values) $optind]
                    }
                }
            }
        }
        return $decoded
    }

    return [evt_decode_event {*}$args]
}

# TBD - document
proc twapi::evt_format_publisher_message {hpub msgid args} {

    array set opts [parseargs args {
        {values.arg NULL}
    } -maxleftover 0]
        
    return [EvtFormatMessage $hpub NULL $msgid $opts(values) 8]
}

# TBD - document
# Where is this used?
proc twapi::evt_free_EVT_VARIANT_ARRAY {p} {
    evt_free $p
}

# TBD - document
# Where is this used?
proc twapi::evt_free_EVT_RENDER_VALUES {p} {
    evt_free $p
}

# TBD - document
proc twapi::evt_seek {hresults pos args} {
    array set opts [parseargs args {
        {origin.arg first {first last current}}
        bookmark.arg
        {strict 0 0x10000}
    } -maxleftover 0]

    if {[info exists opts(bookmark)]} {
        set flags 4
    } else {
        set flags [lsearch -exact {first last current} $opts(origin)]
        incr flags;             # 1 -> first, 2 -> last, 3 -> current
        set opts(bookmark) NULL
    }
        
    incr flags $opts(strict)

    EvtSeek $hresults $pos $opts(bookmark) 0 $flags
}

# TBD - document
proc evt_subscribe {path hevent args} {
    array set opts [parseargs args {
        {session.arg NULL}
        {query.arg ""}
        {origin.arg oldest}
        {ignorequeryerrors 0 0x1000}
        {strict 0 0x10000}
    } -maxleftover 0]

    set flags [expr {$opts(ignorequeryerrors) | $opts(strict)}]
    set bookmark NULL
    switch -exact -- $opts(origin) {
        "oldest" { set flags [expr {$flags | 1}] }
        "current" { set flags [expr {$flags | 2}] }
        default {
            set flags [expr {$flags | 3}]
            set bookmark $opts(origin)
        }
    }

    return [EvtSubscribe $opts(session) $hevent $path $opts(query) $bookmark $flags]
}

proc twapi::_evt_dump {args} {
    array set opts [parseargs args {
        {outfd.arg stdout}
    } -ignoreunknown]

    set hq [evt_query {*}$args]
    trap {
        while {[llength [set hevts [evt_next $hq]]]} {
            foreach hevt $hevts {
                trap {
                    set ev [evt_decode_event $hevt -message -ignorestring None.]
                    puts $opts(outfd) "[dict get $ev -timecreated] [dict get $ev -providername]: [dict get $ev -message]"
                } finally {
                    evt_close $hevt
                }                
            }
        }
    } finally {
        evt_close $hq
    }
}
