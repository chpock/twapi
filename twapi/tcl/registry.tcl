#
# Copyright (c) 2020 Ashok P. Nadkarni
# All rights reserved.
#
# See the file LICENSE for license

namespace eval twapi {}


proc twapi::reg_key_create {hkey subkey args} {
    parseargs args {
        {access.arg generic_read}
        {inherit.bool 0}
        {secd.arg ""}
        {volatile.bool 0 0x1}
        {link.bool 0 0x2}
        {backup.bool 0 0x4}
        32bit
        64bit
        disposition.arg
    } -maxleftover 0 -setvars

    set access [_access_rights_to_mask $access]
    # Note: Following might be set via -access as well. The -32bit and -64bit
    # options just make it a little more convenient for caller
    if {$32bit} {
        set access [expr {$access | 0x200}]
    }
    if {$64bit} {
        set access [expr {$access | 0x100}]
    }
    lassign [RegCreateKeyEx \
                 $hkey \
                 $subkey \
                 0 \
                 "" \
                 [expr {$volatile | $backup}] \
                 $access \
                 [_make_secattr $opts(secd) $inherit] \
                ] hkey disposition_value
    if {[info exists disposition]} {
        upvar 1 $disposition created_or_existed
        if {$disposition_value == 1} {
            set created_or_existed created
        } else {
            # disposition_value == 2
            set created_or_existed existed
        }
    }
    return $hkey
}

proc twapi::reg_key_delete {hkey subkey args} {
    parseargs args {
        32bit
        64bit
    } -maxleftover 0 -setvars

    # TBD - document options after adding tests
    set access 0
    if {$32bit} {
        set access [expr {$access | 0x200}]
    }
    if {$64bit} {
        set access [expr {$access | 0x100}]
    }

    RegDeleteKeyEx $hkey $subkey $access
}

proc twapi::reg_keys {hkey {pattern {}}} {
    if {$pattern eq ""} {
        lmap keyrec [RegEnumKeyEx $hkey] {
            lindex $keyrec 0
        }
    } else {
        lmap keyrec [RegEnumKeyEx $hkey] {
            if {![string match -nocase $pattern [lindex $keyrec 0]]} {
                continue
            }
            lindex $keyrec 0
        }
    }
}

proc twapi::reg_key_open {hkey subkey args} {
    parseargs args {
        {link.bool 0}
        {access.arg generic_read}
        32bit
        64bit
    } -maxleftover 0 -setvars

    set access [_access_rights_to_mask $access]
    # Note: Following might be set via -access as well. The -32bit and -64bit
    # options just make it a little more convenient for caller
    if {$32bit} {
        set access [expr {$access | 0x200}]
    }
    if {$64bit} {
        set access [expr {$access | 0x100}]
    }
    return [RegOpenKeyEx $hkey $subkey $link $access]
}

proc twapi::reg_value_delete {hkey args} {
    if {[llength $args] == 1} {
        RegDeleteValue $hkey [lindex $args 0]
    } elseif {[llength $args] == 2} {
        RegDeleteKeyValue $hkey {*}$args
    } else {
        error "Wrong # args: should be \"reg_value_delete ?SUBKEY? VALUENAME\""
    }
}

proc twapi::reg_key_current_user {args} {
    parseargs args {
        {access.arg generic_read}
        32bit
        64bit
    } -maxleftover 0 -setvars

    set access [_access_rights_to_mask $access]
    # Note: Following might be set via -access as well. The -32bit and -64bit
    # options just make it a little more convenient for caller
    if {$32bit} {
        set access [expr {$access | 0x200}]
    }
    if {$64bit} {
        set access [expr {$access | 0x100}]
    }
    return [RegOpenCurrentUser $access]
}

proc twapi::reg_key_user_classes_root {usertoken args} {
    parseargs args {
        {access.arg generic_read}
        32bit
        64bit
    } -maxleftover 0 -setvars

    set access [_access_rights_to_mask $access]
    # Note: Following might be set via -access as well. The -32bit and -64bit
    # options just make it a little more convenient for caller
    if {$32bit} {
        set access [expr {$access | 0x200}]
    }
    if {$64bit} {
        set access [expr {$access | 0x100}]
    }
    return [RegOpenUserClassesRoot 0 $access]
}

proc twapi::reg_key_export {hkey filepath args} {
    parseargs args {
        {secd.arg {}}
        {format.arg xp {win2k xp}}
        {compress.bool 0}
    } -setvars

    set format [dict get {win2k 1 xp 2} $format]
    if {! $compress} {
        set format [expr {$format | 4}]
    }
    RegSaveKeyEx $hkey $filepath [_make_secattr $secd 0] $format
}

proc twapi::reg_key_import {hkey filepath args} {
    parseargs args {
        {volatile.bool 0 0x1}
        {force.bool 0 0x8}
    } -setvars
    RegRestoreKey $hkey $filepath [expr {$force | $volatile}]
}

proc twapi::reg_key_monitor {hkey args} {
    parseargs arg {
        {keys.bool 0 0x1}
        {attr.bool 0 0x2}
        {values.bool 0 0x4}
        {secd.bool 0 0x8}
        {subtree.bool 0}
        hevent.arg
    } -setvars

    set filter [expr {$keys | $attr | $values | $secd}]
    if {$filter == 0} {
        set filter $0xf
    }

    if {[info exists hevent]} {
        set async 1
    } else {
        set async 0
        set hevent $::twapi::nullptr
    }
    RegNotifyChangeKeyValue $hkey $subtree $filter $hevent $async
}

proc twapi::reg_value_names {hkey {pattern {}}} {
    # 0 - value names only
    return [RegEnumValue $hkey 0]
}

proc twapi::reg_values {hkey} {
    #  3 -> 0x1 - return data values, 0x2 - cooked data
    return [RegEnumValue $hkey 3]
}

proc twapi::reg_values_raw {hkey} {
    #  0x1 - return data values
    return [RegEnumValue $hkey 1]
}

proc twapi::reg_value_raw {hkey args} {
    if {[llength $args] == 1} {
        return [RegQueryValueEx $hkey [lindex $args 0] false]
    } elseif {[llength $args] == 2} {
        return [RegGetValue $hkey {*}$args 0x1000ffff false]
    } else {
        error "wrong # args: should be \"reg_value_get HKEY ?SUBKEY? VALUENAME\""
    }
}

proc twapi::reg_value {hkey args} {
    if {[llength $args] == 1} {
        return [RegQueryValueEx $hkey [lindex $args 0] true]
    } elseif {[llength $args] == 2} {
        return [RegGetValue $hkey {*}$args 0x1000ffff true]
    } else {
        error "wrong # args: should be \"reg_value_get HKEY ?SUBKEY? VALUENAME\""
    }
}

if {[twapi::min_os_version 6]} {
    proc twapi::reg_value_set {hkey args} {
        if {[llength $args] == 3} {
            return [RegSetValueEx $hkey {*}$args]
        } elseif {[llength $args] == 4} {
            return [RegSetKeyValue $hkey {*}$args]
        } else {
            error "wrong # args: should be \"reg_value_set HKEY ?SUBKEY? VALUENAME TYPE VALUE\""
        }
    }
} else {
    proc twapi::reg_value_set {hkey args} {
        if {[llength $args] == 3} {
            lassign $args value_name value_type value
        } elseif {[llength $args] == 4} {
            lassign $args subkey value_name value_type value
            set hkey [reg_key_open $hkey $subkey -access key_set_value]
        } else {
            error "wrong # args: should be \"reg_value_set HKEY ?SUBKEY? VALUENAME TYPE VALUE\""
        }
    }

    try {
        RegSetValueEx $hkey $value_name $value_type $value
    } finally {
        if {[info exists subkey]} {
            # We opened hkey
            reg_close_key $hkey
        }
    }
}

proc twapi::reg_key_override_undo {hkey} {
    RegOverridePredefKey $hkey 0
}