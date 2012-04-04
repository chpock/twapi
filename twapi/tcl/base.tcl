#
# Copyright (c) 2012, Ashok P. Nadkarni
# All rights reserved.
#
# See the file LICENSE for license

# Commands in twapi_base module

namespace eval twapi {
    # Map of Sid integer type to Sid type name
    array set sid_type_names {
        1 user 
        2 group
        3 domain 
        4 alias 
        5 wellknowngroup
        6 deletedaccount
        7 invalid
        8 unknown
        9 computer
    }

    # Well known group to SID mapping. TBD - update for Win7
    array set well_known_sids {
        nullauthority     S-1-0
        nobody            S-1-0-0
        worldauthority    S-1-1
        everyone          S-1-1-0
        localauthority    S-1-2
        creatorauthority  S-1-3
        creatorowner      S-1-3-0
        creatorgroup      S-1-3-1
        creatorownerserver  S-1-3-2
        creatorgroupserver  S-1-3-3
        ntauthority       S-1-5
        dialup            S-1-5-1
        network           S-1-5-2
        batch             S-1-5-3
        interactive       S-1-5-4
        service           S-1-5-6
        anonymouslogon    S-1-5-7
        proxy             S-1-5-8
        serverlogon       S-1-5-9
        authenticateduser S-1-5-11
        terminalserver    S-1-5-13
        localsystem       S-1-5-18
        localservice      S-1-5-19
        networkservice    S-1-5-20
    }

    # Built-in accounts
    # TBD - see http://support.microsoft.com/?kbid=243330 for more built-ins
    array set builtin_account_sids {
        administrators  S-1-5-32-544
        users           S-1-5-32-545
        guests          S-1-5-32-546
        "power users"   S-1-5-32-547
    }
}



# Return major minor servicepack as a quad list
proc twapi::get_os_version {} {
    array set verinfo [GetVersionEx]
    return [list $verinfo(dwMajorVersion) $verinfo(dwMinorVersion) \
                $verinfo(wServicePackMajor) $verinfo(wServicePackMinor)]
}

# Returns true if the OS version is at least $major.$minor.$sp
proc twapi::min_os_version {major {minor 0} {spmajor 0} {spminor 0}} {
    lassign  [twapi::get_os_version]  osmajor osminor osspmajor osspminor

    if {$osmajor > $major} {return 1}
    if {$osmajor < $major} {return 0}
    if {$osminor > $minor} {return 1}
    if {$osminor < $minor} {return 0}
    if {$osspmajor > $spmajor} {return 1}
    if {$osspmajor < $spmajor} {return 0}
    if {$osspminor > $spminor} {return 1}
    if {$osspminor < $spminor} {return 0}

    # Same version, ok
    return 1
}

# Convert a LARGE_INTEGER time value (100ns since 1601) to a formatted date
# time
interp alias {} twapi::large_system_time_to_secs {} twapi::large_system_time_to_secs_since_1970
proc twapi::large_system_time_to_secs_since_1970 {ns100 {fraction false}} {
    # No. 100ns units between 1601 to 1970 = 116444736000000000
    set ns100_since_1970 [expr {wide($ns100)-wide(116444736000000000)}]

    if {0} {
        set secs_since_1970 [expr {wide($ns100_since_1970)/wide(10000000)}]
        if {$fraction} {
            append secs_since_1970 .[expr {wide($ns100_since_1970)%wide(10000000)}]
        }
    } else {
        # Equivalent to above but faster
        if {[string length $ns100_since_1970] > 7} {
            set secs_since_1970 [string range $ns100_since_1970 0 end-7]
            if {$fraction} {
                set frac [string range $ns100_since_1970 end-6 end]
                append secs_since_1970 .$frac
            }
        } else {
            set secs_since_1970 0
            if {$fraction} {
                set frac [string range "0000000${ns100_since_1970}" end-6 end]
                append secs_since_1970 .$frac
            }
        }
    }
    return $secs_since_1970
}

proc twapi::secs_since_1970_to_large_system_time {secs} {
    # No. 100ns units between 1601 to 1970 = 116444736000000000
    return [expr {($secs * 10000000) + wide(116444736000000000)}]
}

interp alias {} ::twapi::get_system_time {} ::twapi::GetSystemTimeAsFileTime
interp alias {} ::twapi::large_system_time_to_timelist {} ::twapi::FileTimeToSystemTime
interp alias {} ::twapi::timelist_to_large_system_time {} ::twapi::SystemTimeToFileTime

# Map a Windows error code to a string
proc twapi::map_windows_error {code} {
    # Trim trailing CR/LF
    return [string trimright [twapi::Twapi_MapWindowsErrorToString $code] "\r\n"]
}

# Load given library
proc twapi::load_library {path args} {
    array set opts [parseargs args {
        dontresolverefs
        datafile
        alteredpath
    }]

    set flags 0
    if {$opts(dontresolverefs)} {
        setbits flags 1;                # DONT_RESOLVE_DLL_REFERENCES
    }
    if {$opts(datafile)} {
        setbits flags 2;                # LOAD_LIBRARY_AS_DATAFILE
    }
    if {$opts(alteredpath)} {
        setbits flags 8;                # LOAD_WITH_ALTERED_SEARCH_PATH
    }

    # LoadLibrary always wants backslashes
    set path [file nativename $path]
    return [LoadLibraryEx $path $flags]
}

# Free library opened with load_library
proc twapi::free_library {libh} {
    FreeLibrary $libh
}

# Format message string - will raise exception if insufficient number
# of arguments
proc twapi::_unsafe_format_message {args} {
    array set opts [parseargs args {
        module.arg
        fmtstring.arg
        messageid.arg
        langid.arg
        params.arg
        includesystem
        ignoreinserts
        width.int
    } -nulldefault -maxleftover 0]

    set flags 0

    if {$opts(module) == ""} {
        if {$opts(fmtstring) == ""} {
            # If neither -module nor -fmtstring specified, message is formatted
            # from the system
            set opts(module) NULL
            setbits flags 0x1000;       # FORMAT_MESSAGE_FROM_SYSTEM
        } else {
            setbits flags 0x400;        # FORMAT_MESSAGE_FROM_STRING
            if {$opts(includesystem) || $opts(messageid) != "" || $opts(langid) != ""} {
                error "Options -includesystem, -messageid and -langid cannot be used with -fmtstring"
            }
        }
    } else {
        if {$opts(fmtstring) != ""} {
            error "Options -fmtstring and -module cannot be used together"
        }
        setbits flags 0x800;        # FORMAT_MESSAGE_FROM_HMODULE
        if {$opts(includesystem)} {
            # Also include system in search
            setbits flags 0x1000;       # FORMAT_MESSAGE_FROM_SYSTEM
        }
    }

    if {$opts(ignoreinserts)} {
        setbits flags 0x200;            # FORMAT_MESSAGE_IGNORE_INSERTS
    }

    if {$opts(width) > 254} {
        error "Invalid value for option -width. Must be -1, 0, or a positive integer less than 255"
    }
    if {$opts(width) < 0} {
        # Negative width means no width restrictions
        set opts(width) 255;                  # 255 -> no restrictions
    }
    incr flags $opts(width);                  # Width goes in low byte of flags

    if {$opts(fmtstring) != ""} {
        return [FormatMessageFromString $flags $opts(fmtstring) $opts(params)]
    } else {
        if {![string is integer -strict $opts(messageid)]} {
            error "Unspecified or invalid value for -messageid option. Must be an integer value"
        }
        if {$opts(langid) == ""} { set opts(langid) 0 }
        if {![string is integer -strict $opts(langid)]} {
            error "Unspecfied or invalid value for -langid option. Must be an integer value"
        }

        # Check if $opts(module) is a file or module handle (pointer)
        if {[Twapi_IsPtr $opts(module)]} {
            return  [FormatMessageFromModule $flags $opts(module) \
                         $opts(messageid) $opts(langid) $opts(params)]
        } else {
            set hmod [load_library $opts(module) -datafile]
            trap {
                set message  [FormatMessageFromModule $flags $hmod \
                                  $opts(messageid) $opts(langid) $opts(params)]
            } finally {
                free_library $hmod
            }
            return $message
        }
    }
}

# Format message string
proc twapi::format_message {args} {
    array set opts [parseargs args {
        params.arg
        fmtstring.arg
        width.int
        ignoreinserts
    } -ignoreunknown]

    # TBD - document - if no params specified, different from params = {}

    # If a format string is specified, other options do not matter
    # except for -width. In that case, we do not call FormatMessage
    # at all
    if {[info exists opts(fmtstring)]} {
        # If -width specifed, call FormatMessage
        if {[info exists opts(width)] && $opts(width)} {
            set msg [_unsafe_format_message -ignoreinserts -fmtstring $opts(fmtstring) -width $opts(width) {*}$args]
        } else {
            set msg $opts(fmtstring)
        }
    } else {
        # Not -fmtstring, retrieve from message file
        if {[info exists opts(width)]} {
            set msg [_unsafe_format_message -ignoreinserts -width $opts(width) {*}$args]
        } else {
            set msg [_unsafe_format_message -ignoreinserts {*}$args]
        }
    }

    # If we are told to ignore inserts, all done. Else replace them except
    # that if no param list, do not replace placeholder. This is NOT
    # the same as empty param list
    if {$opts(ignoreinserts) || ![info exists opts(params)]} {
        return $msg
    }

    set placeholder_indices [regexp -indices -all -inline {%(?:.|(?:[1-9][0-9]?(?:![^!]+!)?))} $msg]

    if {[llength $placeholder_indices] == 0} {
        # No placeholders.
        return $msg
    }

    # Use of * in format specifiers will change where the actual parameters
    # are positioned
    set num_asterisks 0
    set msg2 ""
    set prev_end 0
    foreach placeholder $placeholder_indices {
        lassign $placeholder start end
        # Append the stuff between previous placeholder and this one
        append msg2 [string range $msg $prev_end [expr {$start-1}]]
        set spec [string range $msg $start+1 $end]
        switch -exact -- [string index $spec 0] {
            % { append msg2 % }
            r { append msg2 \r }
            n { append msg2 \n }
            t { append msg2 \t }
            0 { 
                # No-op - %0 means to not add trailing newline
            }
            default {
                if {! [string is integer -strict [string index $spec 0]]} {
                    # Not a insert parameter. Just append the character
                    append msg2 $spec
                } else {
                    # Insert parameter
                    set fmt ""
                    scan $spec %d%s param_index fmt
                    # Note params are numbered starting with 1
                    incr param_index -1
                    # Format spec, if present, is enclosed in !. Get rid of them
                    set fmt [string trim $fmt "!"]
                    if {$fmt eq ""} {
                        # No fmt spec
                    } else {
                        # Since everything is a string in Tcl, we happily
                        # do not have to worry about type. However, the
                        # format spec could have * specifiers which will
                        # change the parameter indexing for subsequent
                        # arguments
                        incr num_asterisks [expr {[llength [split $fmt *]]-1}]
                        incr param_index $num_asterisks
                    }
                    # TBD - we ignore the actual format type
                    append msg2 [lindex $opts(params) $param_index]
                }                        
            }
        }                    
        set prev_end [incr end]
    }
    append msg2 [string range $msg $prev_end end]
    return $msg2
}

# Revert to process token. In base package because used across many modules
proc twapi::revert_to_self {{opt ""}} {
    RevertToSelf
}

interp alias {} twapi::expand_environment_strings {} twapi::ExpandEnvironmentStrings

proc twapi::_init_security_defs {} {
    variable security_defs

    array set security_defs {

        TOKEN_ASSIGN_PRIMARY           0x00000001
        TOKEN_DUPLICATE                0x00000002
        TOKEN_IMPERSONATE              0x00000004
        TOKEN_QUERY                    0x00000008
        TOKEN_QUERY_SOURCE             0x00000010
        TOKEN_ADJUST_PRIVILEGES        0x00000020
        TOKEN_ADJUST_GROUPS            0x00000040
        TOKEN_ADJUST_DEFAULT           0x00000080
        TOKEN_ADJUST_SESSIONID         0x00000100

        TOKEN_ALL_ACCESS_WINNT         0x000F00FF
        TOKEN_ALL_ACCESS_WIN2K         0x000F01FF
        TOKEN_ALL_ACCESS               0x000F01FF
        TOKEN_READ                     0x00020008
        TOKEN_WRITE                    0x000200E0
        TOKEN_EXECUTE                  0x00020000


        SYSTEM_MANDATORY_LABEL_NO_WRITE_UP         0x1
        SYSTEM_MANDATORY_LABEL_NO_READ_UP          0x2
        SYSTEM_MANDATORY_LABEL_NO_EXECUTE_UP       0x4

        ACL_REVISION     2
        ACL_REVISION_DS  4

        ACCESS_MAX_MS_V2_ACE_TYPE               0x3
        ACCESS_MAX_MS_V3_ACE_TYPE               0x4
        ACCESS_MAX_MS_V4_ACE_TYPE               0x8
        ACCESS_MAX_MS_V5_ACE_TYPE               0x11

        STANDARD_RIGHTS_REQUIRED       0x000F0000
        STANDARD_RIGHTS_READ           0x00020000
        STANDARD_RIGHTS_WRITE          0x00020000
        STANDARD_RIGHTS_EXECUTE        0x00020000
        STANDARD_RIGHTS_ALL            0x001F0000
        SPECIFIC_RIGHTS_ALL            0x0000FFFF

        GENERIC_READ                   0x80000000
        GENERIC_WRITE                  0x40000000
        GENERIC_EXECUTE                0x20000000
        GENERIC_ALL                    0x10000000

        SERVICE_QUERY_CONFIG           0x00000001
        SERVICE_CHANGE_CONFIG          0x00000002
        SERVICE_QUERY_STATUS           0x00000004
        SERVICE_ENUMERATE_DEPENDENTS   0x00000008
        SERVICE_START                  0x00000010
        SERVICE_STOP                   0x00000020
        SERVICE_PAUSE_CONTINUE         0x00000040
        SERVICE_INTERROGATE            0x00000080
        SERVICE_USER_DEFINED_CONTROL   0x00000100
        SERVICE_ALL_ACCESS             0x000F01FF

        SC_MANAGER_CONNECT             0x00000001
        SC_MANAGER_CREATE_SERVICE      0x00000002
        SC_MANAGER_ENUMERATE_SERVICE   0x00000004
        SC_MANAGER_LOCK                0x00000008
        SC_MANAGER_QUERY_LOCK_STATUS   0x00000010
        SC_MANAGER_MODIFY_BOOT_CONFIG  0x00000020
        SC_MANAGER_ALL_ACCESS          0x000F003F

        KEY_QUERY_VALUE                0x00000001
        KEY_SET_VALUE                  0x00000002
        KEY_CREATE_SUB_KEY             0x00000004
        KEY_ENUMERATE_SUB_KEYS         0x00000008
        KEY_NOTIFY                     0x00000010
        KEY_CREATE_LINK                0x00000020
        KEY_WOW64_32KEY                0x00000200
        KEY_WOW64_64KEY                0x00000100
        KEY_WOW64_RES                  0x00000300
        KEY_READ                       0x00020019
        KEY_WRITE                      0x00020006
        KEY_EXECUTE                    0x00020019
        KEY_ALL_ACCESS                 0x000F003F

        POLICY_VIEW_LOCAL_INFORMATION   0x00000001
        POLICY_VIEW_AUDIT_INFORMATION   0x00000002
        POLICY_GET_PRIVATE_INFORMATION  0x00000004
        POLICY_TRUST_ADMIN              0x00000008
        POLICY_CREATE_ACCOUNT           0x00000010
        POLICY_CREATE_SECRET            0x00000020
        POLICY_CREATE_PRIVILEGE         0x00000040
        POLICY_SET_DEFAULT_QUOTA_LIMITS 0x00000080
        POLICY_SET_AUDIT_REQUIREMENTS   0x00000100
        POLICY_AUDIT_LOG_ADMIN          0x00000200
        POLICY_SERVER_ADMIN             0x00000400
        POLICY_LOOKUP_NAMES             0x00000800
        POLICY_NOTIFICATION             0x00001000
        POLICY_READ                     0X00020006
        POLICY_WRITE                    0X000207F8
        POLICY_EXECUTE                  0X00020801
        POLICY_ALL_ACCESS               0X000F0FFF

        DESKTOP_READOBJECTS         0x0001
        DESKTOP_CREATEWINDOW        0x0002
        DESKTOP_CREATEMENU          0x0004
        DESKTOP_HOOKCONTROL         0x0008
        DESKTOP_JOURNALRECORD       0x0010
        DESKTOP_JOURNALPLAYBACK     0x0020
        DESKTOP_ENUMERATE           0x0040
        DESKTOP_WRITEOBJECTS        0x0080
        DESKTOP_SWITCHDESKTOP       0x0100

        WINSTA_ENUMDESKTOPS         0x0001
        WINSTA_READATTRIBUTES       0x0002
        WINSTA_ACCESSCLIPBOARD      0x0004
        WINSTA_CREATEDESKTOP        0x0008
        WINSTA_WRITEATTRIBUTES      0x0010
        WINSTA_ACCESSGLOBALATOMS    0x0020
        WINSTA_EXITWINDOWS          0x0040
        WINSTA_ENUMERATE            0x0100
        WINSTA_READSCREEN           0x0200
        WINSTA_ALL_ACCESS           0x37f

        PROCESS_TERMINATE              0x0001
        PROCESS_CREATE_THREAD          0x0002
        PROCESS_SET_SESSIONID          0x0004
        PROCESS_VM_OPERATION           0x0008
        PROCESS_VM_READ                0x0010
        PROCESS_VM_WRITE               0x0020
        PROCESS_DUP_HANDLE             0x0040
        PROCESS_CREATE_PROCESS         0x0080
        PROCESS_SET_QUOTA              0x0100
        PROCESS_SET_INFORMATION        0x0200
        PROCESS_QUERY_INFORMATION      0x0400
        PROCESS_SUSPEND_RESUME         0x0800

        THREAD_TERMINATE               0x00000001
        THREAD_SUSPEND_RESUME          0x00000002
        THREAD_GET_CONTEXT             0x00000008
        THREAD_SET_CONTEXT             0x00000010
        THREAD_SET_INFORMATION         0x00000020
        THREAD_QUERY_INFORMATION       0x00000040
        THREAD_SET_THREAD_TOKEN        0x00000080
        THREAD_IMPERSONATE             0x00000100
        THREAD_DIRECT_IMPERSONATION    0x00000200
        THREAD_SET_LIMITED_INFORMATION   0x00000400
        THREAD_QUERY_LIMITED_INFORMATION 0x00000800

        EVENT_MODIFY_STATE             0x00000002
        EVENT_ALL_ACCESS               0x001F0003

        SEMAPHORE_MODIFY_STATE         0x00000002
        SEMAPHORE_ALL_ACCESS           0x001F0003

        MUTANT_QUERY_STATE             0x00000001
        MUTANT_ALL_ACCESS              0x001F0001

        MUTEX_MODIFY_STATE             0x00000001
        MUTEX_ALL_ACCESS               0x001F0001

        TIMER_QUERY_STATE              0x00000001
        TIMER_MODIFY_STATE             0x00000002
        TIMER_ALL_ACCESS               0x001F0003

        FILE_READ_DATA                 0x00000001
        FILE_LIST_DIRECTORY            0x00000001
        FILE_WRITE_DATA                0x00000002
        FILE_ADD_FILE                  0x00000002
        FILE_APPEND_DATA               0x00000004
        FILE_ADD_SUBDIRECTORY          0x00000004
        FILE_CREATE_PIPE_INSTANCE      0x00000004
        FILE_READ_EA                   0x00000008
        FILE_WRITE_EA                  0x00000010
        FILE_EXECUTE                   0x00000020
        FILE_TRAVERSE                  0x00000020
        FILE_DELETE_CHILD              0x00000040
        FILE_READ_ATTRIBUTES           0x00000080
        FILE_WRITE_ATTRIBUTES          0x00000100

        FILE_ALL_ACCESS                0x001F01FF
        FILE_GENERIC_READ              0x00120089
        FILE_GENERIC_WRITE             0x00120116
        FILE_GENERIC_EXECUTE           0x001200A0

        DELETE                         0x00010000
        READ_CONTROL                   0x00020000
        WRITE_DAC                      0x00040000
        WRITE_OWNER                    0x00080000
        SYNCHRONIZE                    0x00100000
    }

    if {[min_os_version 6]} {
        array set security_defs {
            PROCESS_QUERY_LIMITED_INFORMATION      0x00001000
            PROCESS_ALL_ACCESS             0x001fffff
            THREAD_ALL_ACCESS              0x001fffff
        }
    } else {
        array set security_defs {
            PROCESS_ALL_ACCESS             0x001f0fff
            THREAD_ALL_ACCESS              0x001f03ff
        }
    }

    # Make next call a no-op
    proc _init_security_defs {} {}
}

# Map a set of access right symbols to a flag. Concatenates
# all the arguments, and then OR's the individual elements. Each
# element may either be a integer or one of the access rights
proc twapi::_access_rights_to_mask {args} {
    _init_security_defs

    proc _access_rights_to_mask args {
        variable security_defs
        set rights 0
        foreach right [concat {*}$args] {
            if {![string is integer $right]} {
                if {[catch {set right $security_defs([string toupper $right])}]} {
                    error "Invalid access right symbol '$right'"
                }
            }
            set rights [expr {$rights | $right}]
        }
        return $rights
    }
    return [_access_rights_to_mask {*}$args]
}


# Map an access mask to a set of rights
proc twapi::_access_mask_to_rights {access_mask {type ""}} {
    _init_security_defs

    proc _access_mask_to_rights {access_mask {type ""}} {
        variable security_defs

        set rights [list ]

        if {$type eq "mandatory_label"} {
            if {$access_mask & 1} {
                lappend rights system_mandatory_label_no_write_up
            }
            if {$access_mask & 2} {
                lappend rights system_mandatory_label_no_read_up
            }
            if {$access_mask & 4} {
                lappend rights system_mandatory_label_no_execute_up
            }
            return $rights
        }

        # The returned list will include rights that map to multiple bits
        # as well as the individual bits. We first add the multiple bits
        # and then the individual bits (since we clear individual bits
        # after adding)

        #
        # Check standard multiple bit masks
        #
        foreach x {STANDARD_RIGHTS_REQUIRED STANDARD_RIGHTS_READ STANDARD_RIGHTS_WRITE STANDARD_RIGHTS_EXECUTE STANDARD_RIGHTS_ALL SPECIFIC_RIGHTS_ALL} {
            if {($security_defs($x) & $access_mask) == $security_defs($x)} {
                lappend rights [string tolower $x]
            }
        }

        #
        # Check type specific multiple bit masks.
        #
        
        set type_mask_map {
            file {FILE_ALL_ACCESS FILE_GENERIC_READ FILE_GENERIC_WRITE FILE_GENERIC_EXECUTE}
            process {PROCESS_ALL_ACCESS}
            pipe {FILE_ALL_ACCESS}
            policy {POLICY_READ POLICY_WRITE POLICY_EXECUTE POLICY_ALL_ACCESS}
            registry {KEY_READ KEY_WRITE KEY_EXECUTE KEY_ALL_ACCESS}
            service {SERVICE_ALL_ACCESS}
            thread {THREAD_ALL_ACCESS}
            token {TOKEN_READ TOKEN_WRITE TOKEN_EXECUTE TOKEN_ALL_ACCESS}
            desktop {}
            winsta {WINSTA_ALL_ACCESS}
        }
        if {[dict exists $type_mask_map $type]} {
            foreach x [dict get $type_mask_map $type] {
                if {($security_defs($x) & $access_mask) == $security_defs($x)} {
                    lappend rights [string tolower $x]
                }
            }
        }

        #
        # OK, now map individual bits

        # First map the common bits
        foreach x {DELETE READ_CONTROL WRITE_DAC WRITE_OWNER SYNCHRONIZE} {
            if {$security_defs($x) & $access_mask} {
                lappend rights [string tolower $x]
                resetbits access_mask $security_defs($x)
            }
        }

        # Then the generic bits
        foreach x {GENERIC_READ GENERIC_WRITE GENERIC_EXECUTE GENERIC_ALL} {
            if {$security_defs($x) & $access_mask} {
                lappend rights [string tolower $x]
                resetbits access_mask $security_defs($x)
            }
        }

        # Then the type specific
        set type_mask_map {
            file { FILE_READ_DATA FILE_WRITE_DATA FILE_APPEND_DATA
                FILE_READ_EA FILE_WRITE_EA FILE_EXECUTE
                FILE_DELETE_CHILD FILE_READ_ATTRIBUTES
                FILE_WRITE_ATTRIBUTES }
            pipe { FILE_READ_DATA FILE_WRITE_DATA FILE_CREATE_PIPE_INSTANCE
                FILE_READ_ATTRIBUTES FILE_WRITE_ATTRIBUTES }
            service { SERVICE_QUERY_CONFIG SERVICE_CHANGE_CONFIG
                SERVICE_QUERY_STATUS SERVICE_ENUMERATE_DEPENDENTS
                SERVICE_START SERVICE_STOP SERVICE_PAUSE_CONTINUE
                SERVICE_INTERROGATE SERVICE_USER_DEFINED_CONTROL }
            registry { KEY_QUERY_VALUE KEY_SET_VALUE KEY_CREATE_SUB_KEY
                KEY_ENUMERATE_SUB_KEYS KEY_NOTIFY KEY_CREATE_LINK
                KEY_WOW64_32KEY KEY_WOW64_64KEY KEY_WOW64_RES }
            policy { POLICY_VIEW_LOCAL_INFORMATION POLICY_VIEW_AUDIT_INFORMATION
                POLICY_GET_PRIVATE_INFORMATION POLICY_TRUST_ADMIN
                POLICY_CREATE_ACCOUNT POLICY_CREATE_SECRET
                POLICY_CREATE_PRIVILEGE POLICY_SET_DEFAULT_QUOTA_LIMITS
                POLICY_SET_AUDIT_REQUIREMENTS POLICY_AUDIT_LOG_ADMIN
                POLICY_SERVER_ADMIN POLICY_LOOKUP_NAMES }
            process { PROCESS_TERMINATE PROCESS_CREATE_THREAD
                PROCESS_SET_SESSIONID PROCESS_VM_OPERATION
                PROCESS_VM_READ PROCESS_VM_WRITE PROCESS_DUP_HANDLE
                PROCESS_CREATE_PROCESS PROCESS_SET_QUOTA
                PROCESS_SET_INFORMATION PROCESS_QUERY_INFORMATION
                PROCESS_SUSPEND_RESUME} 
            thread { THREAD_TERMINATE THREAD_SUSPEND_RESUME
                THREAD_GET_CONTEXT THREAD_SET_CONTEXT
                THREAD_SET_INFORMATION THREAD_QUERY_INFORMATION
                THREAD_SET_THREAD_TOKEN THREAD_IMPERSONATE
                THREAD_DIRECT_IMPERSONATION
                THREAD_SET_LIMITED_INFORMATION
                THREAD_QUERY_LIMITED_INFORMATION }
            token { TOKEN_ASSIGN_PRIMARY TOKEN_DUPLICATE TOKEN_IMPERSONATE
                TOKEN_QUERY TOKEN_QUERY_SOURCE TOKEN_ADJUST_PRIVILEGES
                TOKEN_ADJUST_GROUPS TOKEN_ADJUST_DEFAULT TOKEN_ADJUST_SESSIONID }
            desktop { DESKTOP_READOBJECTS DESKTOP_CREATEWINDOW
                DESKTOP_CREATEMENU DESKTOP_HOOKCONTROL
                DESKTOP_JOURNALRECORD DESKTOP_JOURNALPLAYBACK
                DESKTOP_ENUMERATE DESKTOP_WRITEOBJECTS DESKTOP_SWITCHDESKTOP }
            windowstation -
            winsta { WINSTA_ENUMDESKTOPS WINSTA_READATTRIBUTES
                WINSTA_ACCESSCLIPBOARD WINSTA_CREATEDESKTOP
                WINSTA_WRITEATTRIBUTES WINSTA_ACCESSGLOBALATOMS
                WINSTA_EXITWINDOWS WINSTA_ENUMERATE WINSTA_READSCREEN }
        }

        if {[min_os_version 6]} {
            dict lappend type_mask_map process PROCESS_QUERY_LIMITED_INFORMATION
        }

        if {[dict exists $type_mask_map $type]} {
            foreach x [dict get $type_mask_map $type] {
                if {$security_defs($x) & $access_mask} {
                    lappend rights [string tolower $x]
                    # Reset the bit so is it not included in unknown bits below
                    resetbits access_mask $security_defs($x)
                }
            }
        }

        # Finally add left over bits if any
        for {set i 0} {$i < 32} {incr i} {
            set x [expr {1 << $i}]
            if {$access_mask & $x} {
                lappend rights [format 0x%.8X $x]
            }
        }

        return $rights
    }

    return [_access_mask_to_rights $access_mask $type]
}

# Map the symbolic CreateDisposition parameter of CreateFile to integer values
proc twapi::_create_disposition_to_code {sym} {
    if {[string is integer -strict $sym]} {
        return $sym
    }
    # CREATE_NEW          1
    # CREATE_ALWAYS       2
    # OPEN_EXISTING       3
    # OPEN_ALWAYS         4
    # TRUNCATE_EXISTING   5
    return [dict get {
        create_new 1
        create_always 2
        open_existing 3
        open_always 4
        truncate_existing 5} $sym]
}

# Wrapper around CreateFile
# TBD - Move documentation to base module doc
proc twapi::create_file {path args} {
    array set opts [parseargs args {
        {access.arg {generic_read}}
        {share.arg {read write delete}}
        {inherit.bool 0}
        {secd.arg ""}
        {createdisposition.arg open_always}
        {flags.int 0}
        {templatefile.arg NULL}
    } -maxleftover 0]

    set access_mode [_access_rights_to_mask $opts(access)]
    set share_mode [_share_mode_to_mask $opts(share)]
    set create_disposition [_create_disposition_to_code $opts(createdisposition)]
    return [CreateFile $path \
                $access_mode \
                $share_mode \
                [_make_secattr $opts(secd) $opts(inherit)] \
                $create_disposition \
                $opts(flags) \
                $opts(templatefile)]
}

# Map a set of share mode symbols to a flag. Concatenates
# all the arguments, and then OR's the individual elements. Each
# element may either be a integer or one of the share modes
proc twapi::_share_mode_to_mask {modelist} {
    # Values correspond to FILE_SHARE_* defines
    return [_parse_symbolic_bitmask $modelist {read 1 write 2 delete 4}]
}

# Construct a security attributes structure out of a security descriptor
# and inheritance. The command is here because we do not want to
# have to load the twapi_security package for the common case of
# null security attributes.
proc twapi::_make_secattr {secd inherit} {
    if {$inherit} {
        set sec_attr [list $secd 1]
    } else {
        if {[llength $secd] == 0} {
            # If a security descriptor not specified, keep
            # all security attributes as an empty list (ie. NULL)
            set sec_attr [list ]
        } else {
            set sec_attr [list $secd 0]
        }
    }
    return $sec_attr
}

# TBD - move the docs for the code below to base module

# Helper for lookup_account_name{sid,name}
# TBD - get rid of this common code - makes it slower than it need be
# when results are cached. Or move cache up one level
proc twapi::_lookup_account {func account args} {
    if {$func == "LookupAccountSid"} {
        set lookup name
        # If we are mapping a SID to a name, check if it is the logon SID
        # LookupAccountSid returns an error for this SID
        if {[is_valid_sid_syntax $account] &&
            [string match -nocase "S-1-5-5-*" $account]} {
            set name "Logon SID"
            set domain "NT AUTHORITY"
            set type "logonid"
        }
    } else {
        set lookup sid
    }
    array set opts [parseargs args \
                        [list all \
                             $lookup \
                             domain \
                             type \
                             [list system.arg ""]\
                            ]]


    # Lookup the info if have not already hardcoded results
    if {![info exists domain]} {
        # Use cache if possible
        variable _lookup_account_cache
        if {![info exists _lookup_account_cache($lookup,$opts(system),$account)]} {
            set _lookup_account_cache($lookup,$opts(system),$account) [$func $opts(system) $account]
        }
        lassign $_lookup_account_cache($lookup,$opts(system),$account) $lookup domain type
    }

    set result [list ]
    if {$opts(all) || $opts(domain)} {
        lappend result -domain $domain
    }
    if {$opts(all) || $opts(type)} {
        if {[info exists twapi::sid_type_names($type)]} {
            lappend result -type $twapi::sid_type_names($type)
        } else {
            # Could be the "logonid" dummy type we added above
            lappend result -type $type
        }
    }

    if {$opts(all) || $opts($lookup)} {
        lappend result -$lookup [set $lookup]
    }

    # If no options specified, only return the sid/name
    if {[llength $result] == 0} {
        return [set $lookup]
    }

    return $result
}

# Returns the sid, domain and type for an account
proc twapi::lookup_account_name {name args} {
    return [_lookup_account LookupAccountName $name {*}$args]
}


# Returns the name, domain and type for an account
proc twapi::lookup_account_sid {sid args} {
    return [_lookup_account LookupAccountSid $sid {*}$args]
}

# Returns the sid for a account - may be given as a SID or name
proc twapi::map_account_to_sid {account args} {
    array set opts [parseargs args {system.arg} -nulldefault]

    # Treat empty account as null SID (self)
    if {[string length $account] == ""} {
        return ""
    }

    if {[is_valid_sid_syntax $account]} {
        return $account
    } else {
        return [lookup_account_name $account -system $opts(system)]
    }
}


# Returns the name for a account - may be given as a SID or name
proc twapi::map_account_to_name {account args} {
    array set opts [parseargs args {system.arg} -nulldefault]

    if {[is_valid_sid_syntax $account]} {
        return [lookup_account_sid $account -system $opts(system)]
    } else {
        # Verify whether a valid account by mapping to an sid
        if {[catch {map_account_to_sid $account -system $opts(system)}]} {
            # As a special case, change LocalSystem to SYSTEM. Some Windows
            # API's (such as services) return LocalSystem which cannot be
            # resolved by the security functions. This name is really the
            # same a the built-in SYSTEM
            if {$account == "LocalSystem"} {
                return "SYSTEM"
            }
            error "Unknown account '$account'"
        } 
        return $account
    }
}

# Return the user account for the current process
proc twapi::get_current_user {{format -samcompatible}} {

    set return_sid false
    switch -exact -- $format {
        -fullyqualifieddn {set format 1}
        -samcompatible {set format 2}
        -display {set format 3}
        -uniqueid {set format 6}
        -canonical {set format 7}
        -userprincipal {set format 8}
        -canonicalex {set format 9}
        -serviceprincipal {set format 10}
        -dnsdomain {set format 12}
        -sid {set format 2 ; set return_sid true}
        default {
            error "Unknown user name format '$format'"
        }
    }

    set user [GetUserNameEx $format]

    if {$return_sid} {
        return [map_account_to_sid $user]
    } else {
        return $user
    }
}

# Get a new uuid
proc twapi::new_uuid {{opt ""}} {
    if {[string length $opt]} {
        if {[string equal $opt "-localok"]} {
            set local_ok 1
        } else {
            error "Invalid or unknown argument '$opt'"
        }
    } else {
        set local_ok 0
    }
    return [UuidCreate $local_ok] 
}
proc twapi::nil_uuid {} {
    return [UuidCreateNil]
}

# Get a handle to a LSA policy. TBD - document
proc twapi::get_lsa_policy_handle {args} {
    array set opts [parseargs args {
        {system.arg ""}
        {access.arg policy_read}
    } -maxleftover 0]

    set access [_access_rights_to_mask $opts(access)]
    return [Twapi_LsaOpenPolicy $opts(system) $access]
}

# Close a LSA policy handle
proc twapi::close_lsa_policy_handle {h} {
    LsaClose $h
    return
}
