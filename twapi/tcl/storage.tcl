#
# Copyright (c) 2003, 2008 Ashok P. Nadkarni
# All rights reserved.
#
# See the file LICENSE for license

# TBD - convert file spec to drive root path

# Get info associated with a drive
proc twapi::get_volume_info {drive args} {

    set drive [_drive_rootpath $drive]

    array set opts [parseargs args {
        all size freespace used useravail type serialnum label maxcomponentlen fstype attr device extents
    } -maxleftover 0]

    if {$opts(all)} {
        # -all option does not cover -type, -extents and -device
        foreach opt {
            all size freespace used useravail serialnum label maxcomponentlen fstype attr
        } {
            set opts($opt) 1
        }
    }

    set result [list ]
    if {$opts(size) || $opts(freespace) || $opts(used) || $opts(useravail)} {
        lassign  [GetDiskFreeSpaceEx $drive] useravail size freespace
        foreach opt {size freespace useravail}  {
            if {$opts($opt)} {
                lappend result -$opt [set $opt]
            }
        }
        if {$opts(used)} {
            lappend result -used [expr {$size - $freespace}]
        }
    }

    if {$opts(type)} {
        set drive_type [get_drive_type $drive]
        lappend result -type $drive_type
    }
    if {$opts(device)} {
        if {[_is_unc $drive]} {
            # UNC paths cannot be used with QueryDosDevice
            lappend result -device ""
        } else {
            lappend result -device [QueryDosDevice [string range $drive 0 1]]
        }
    }

    if {$opts(extents)} {
        set extents {}
        if {! [_is_unc $drive]} {
            trap {
                set device_handle [create_file "\\\\.\\[string range $drive 0 1]" -createdisposition open_existing]
                set bin [device_ioctl $device_handle 0x560000 -outputcount 32]
                if {[binary scan $bin i nextents] != 1} {
                    error "Truncated information returned from ioctl 0x560000"
                }
                set off 8
                for {set i 0} {$i < $nextents} {incr i} {
                    if {[binary scan $bin "@$off i x4 w w" extent(-disknumber) extent(-startingoffset) extent(-extentlength)] != 3} {
                        error "Truncated information returned from ioctl 0x560000"
                    }
                    lappend extents [array get extent]
                    incr off 24; # Size of one extent element
                }
            } onerror {} {
                # Do nothing, device does not support extents or access denied
                # Empty list is returned
            } finally {
                if {[info exists device_handle]} {
                    CloseHandle $device_handle
                }
            }
        }

        lappend result -extents $extents
    }

    if {$opts(serialnum) || $opts(label) || $opts(maxcomponentlen)
        || $opts(fstype) || $opts(attr)} {
        foreach {label serialnum maxcomponentlen attr fstype} \
            [GetVolumeInformation $drive] { break }
        foreach opt {label maxcomponentlen fstype}  {
            if {$opts($opt)} {
                lappend result -$opt [set $opt]
            }
        }
        if {$opts(serialnum)} {
            set low [expr {$serialnum & 0x0000ffff}]
            set high [expr {($serialnum >> 16) & 0x0000ffff}]
            lappend result -serialnum [format "%.4X-%.4X" $high $low]
        }
        if {$opts(attr)} {
            set attrs [list ]
            foreach {sym val} {
                case_preserved_names 2
                unicode_on_disk 4
                persistent_acls 8
                file_compression 16
                volume_quotas 32
                supports_sparse_files 64
                supports_reparse_points 128
                supports_remote_storage 256
                volume_is_compressed 0x8000
                supports_object_ids 0x10000
                supports_encryption 0x20000
                named_streams 0x40000
                read_only_volume 0x80000
                sequential_write_once          0x00100000  
                supports_transactions          0x00200000  
                supports_hard_links            0x00400000  
                supports_extended_attributes   0x00800000  
                supports_open_by_file_id       0x01000000  
                supports_usn_journal           0x02000000  
            } {
                if {$attr & $val} {
                    lappend attrs $sym
                }
            }
            lappend result -attr $attrs
        }
    }

    return $result
}
interp alias {} twapi::get_drive_info {} twapi::get_volume_info


# Check if disk has at least n bytes available for the user (NOT total free)
proc twapi::user_drive_space_available {drv space} {
    return [expr {$space <= [lindex [get_drive_info $drv -useravail] 1]}]
}

# Get the drive type
proc twapi::get_drive_type {drive} {
    # set type [GetDriveType "[string trimright $drive :/\\]:\\"]
    set type [GetDriveType [_drive_rootpath $drive]]
    switch -exact -- $type {
        0 { return unknown}
        1 { return invalid}
        2 { return removable}
        3 { return fixed}
        4 { return remote}
        5 { return cdrom}
        6 { return ramdisk}
    }
}

# Get list of drives
proc twapi::find_logical_drives {args} {
    array set opts [parseargs args {type.arg}]

    set drives [list ]
    foreach drive [_drivemask_to_drivelist [GetLogicalDrives]] {
        if {(![info exists opts(type)]) ||
            [lsearch -exact $opts(type) [get_drive_type $drive]] >= 0} {
            lappend drives $drive
        }
    }
    return $drives
}

twapi::proc* twapi::drive_ready {drive} {
    uplevel #0 package require twapi_device
} {
    set drive [string trimright $drive "/\\"]
    if {[string length $drive] != 2 || [string index $drive 1] ne ":"} {
        error "Invalid drive specification"
    }
    set drive "\\\\.\\$drive"

    # Do our best to avoid the Windows "Drive not ready" dialog
    # 1 -> SEM_FAILCRITICALERRORS
    if {[min_os_version 6]} {
        set old_mode [SetErrorMode 1]
    }
    trap {

        # We will first try using IOCTL_STORAGE_CHECK_VERIFY2 as that is
        # much faster and only needs FILE_READ_ATTRIBUTES access.
        set error [catch {
            set h [create_file $drive -access file_read_attributes \
                   -createdisposition open_existing -share {read write}]
            device_ioctl $h 0x2d0800; # IOCTL_STORAGE_CHECK_VERIFY2
        }]
        if {[info exists h]} {
            close_handle $h
        }
        if {! $error} {
            return 1;               # Device is ready
        }

        # On error, try the older slower method. Note we now need
        # GENERIC_READ access. (NOTE: FILE_READ_DATA will not work with some
        # volume types)
        unset -nocomplain h
        set error [catch {
            set h [create_file $drive -access generic_read \
                       -createdisposition open_existing -share {read write}]
            device_ioctl $h 0x2d4800; # IOCTL_STORAGE_CHECK_VERIFY
        }]
        if {[info exists h]} {
            close_handle $h
        }
        if {! $error} {
            return 1;           # Device is ready
        }

        # Remote shares sometimes return access denied with the above
        # even when actually available. Try with good old file exists
        # on root directory
        return [file exists "[string range $drive end-1 end]\\"]
    } finally {
        if {[min_os_version 6]} {
            SetErrorMode $old_mode
        }
    }
}


# Set the drive label
proc twapi::set_drive_label {drive label} {
    SetVolumeLabel [_drive_rootpath $drive] $label
}

# Maps a drive letter to the given path
proc twapi::map_drive_local {drive path args} {
    array set opts [parseargs args {raw}]

    set drive [string range [_drive_rootpath $drive] 0 1]
    DefineDosDevice $opts(raw) $drive [file nativename $path]
}


# Unmaps a drive letter
proc twapi::unmap_drive_local {drive args} {
    array set opts [parseargs args {
        path.arg
        raw
    } -nulldefault]

    set drive [string range [_drive_rootpath $drive] 0 1]

    set flags $opts(raw)
    setbits flags 0x2;                  # DDD_REMOVE_DEFINITION
    if {$opts(path) ne ""} {
        setbits flags 0x4;              # DDD_EXACT_MATCH_ON_REMOVE
    }
    DefineDosDevice $flags $drive [file nativename $opts(path)]
}


# Callback from C code
proc twapi::_filesystem_monitor_handler {id changes} {
    variable _filesystem_monitor_scripts
    if {[info exists _filesystem_monitor_scripts($id)]} {
        return [uplevel #0 [linsert $_filesystem_monitor_scripts($id) end $id $changes]]
    } else {
        # Callback queued after close. Ignore
    }
}

# Monitor file changes
proc twapi::begin_filesystem_monitor {path script args} {
    variable _filesystem_monitor_scripts

    array set opts [parseargs args {
        {subtree.bool  0}
        {filename.bool 0 0x1}
        {dirname.bool  0 0x2}
        {attr.bool     0 0x4}
        {size.bool     0 0x8}
        {write.bool    0 0x10}
        {access.bool   0 0x20}
        {create.bool   0 0x40}
        {secd.bool     0 0x100}
        {pattern.arg ""}
        {patterns.arg ""}
    } -maxleftover 0]

    if {[string length $opts(pattern)] &&
        [llength $opts(patterns)]} {
        error "Options -pattern and -patterns are mutually exclusive. Note option -pattern is deprecated."
    }

    if {[string length $opts(pattern)]} {
        # Old style single pattern. Convert to new -patterns
        set opts(patterns) [list "+$opts(pattern)"]
    }

    # Change to use \ style path separator as that is what the file monitoring functions return
    if {[llength $opts(patterns)]} {
        foreach pat $opts(patterns) {
            # Note / is replaced by \\ within the pattern
            # since \ needs to be escaped with another \ within
            # string match patterns
            lappend pats [string map [list / \\\\] $pat]
        }
        set opts(patterns) $pats
    }

    set flags [expr { $opts(filename) | $opts(dirname) | $opts(attr) |
                      $opts(size) | $opts(write) | $opts(access) |
                      $opts(create) | $opts(secd)}]

    if {! $flags} {
        # If no options specified, default to all
        set flags 0x17f
    }

    set id [Twapi_RegisterDirectoryMonitor $path $opts(subtree) $flags $opts(patterns)]
    set _filesystem_monitor_scripts($id) $script
    return $id
}

# Stop monitoring of files
proc twapi::cancel_filesystem_monitor {id} {
    variable _filesystem_monitor_scripts
    if {[info exists _filesystem_monitor_scripts($id)]} {
        Twapi_UnregisterDirectoryMonitor $id
        unset _filesystem_monitor_scripts($id)
    }
}


# Get list of volumes
proc twapi::find_volumes {} {
    set vols [list ]
    set found 1
    # Assumes there has to be at least one volume
    lassign [FindFirstVolume] handle vol
    while {$found} {
        lappend vols $vol
        lassign [FindNextVolume $handle] found vol
    }
    FindVolumeClose $handle
    return $vols
}

# Get list of volume mount points
proc twapi::find_volume_mount_points {vol} {
    set mntpts [list ]
    set found 1
    trap {
        lassign  [FindFirstVolumeMountPoint $vol] handle mntpt
    } onerror {TWAPI_WIN32 18} {
        # ERROR_NO_MORE_FILES
        # No volume mount points
        return [list ]
    } onerror {TWAPI_WIN32 3} {
        # Volume does not support them
        return [list ]
    }

    # At least one volume found
    while {$found} {
        lappend mntpts $mntpt
        lassign  [FindNextVolumeMountPoint $handle] found mntpt
    }
    FindVolumeMountPointClose $handle
    return $mntpts
}

# Set volume mount point
proc twapi::mount_volume {volpt volname} {
    # Note we don't use _drive_rootpath for trimming since may not be root path
    SetVolumeMountPoint "[string trimright $volpt /\\]\\" "[string trimright $volname /\\]\\"
}

# Delete volume mount point
proc twapi::unmount_volume {volpt} {
    # Note we don't use _drive_rootpath for trimming since may not be root path
    DeleteVolumeMountPoint "[string trimright $volpt /\\]\\"
}

# Get the volume mounted at a volume mount point
proc twapi::get_mounted_volume_name {volpt} {
    # Note we don't use _drive_rootpath for trimming since may not be root path
    return [GetVolumeNameForVolumeMountPoint "[string trimright $volpt /\\]\\"]
}

# Get the mount point corresponding to a given path
proc twapi::get_volume_mount_point_for_path {path} {
    return [GetVolumePathName [file nativename $path]]
}


# Return the times associated with a file
proc twapi::get_file_times {fd args} {
    array set opts [parseargs args {
        all
        mtime
        ctime
        atime
    } -maxleftover 0]

    # Figure out if fd is a file path, Tcl channel or a handle
    set close_handle false
    if {[file exists $fd]} {
        # It's a file name
        # 0x02000000 -> FILE_FLAG_BACKUP_SEMANTICS, always required in case 
        # opening a directory (even if SeBackupPrivilege is not held
        set h [create_file $fd -createdisposition open_existing -flags 0x02000000]
        set close_handle true
    } elseif {[catch {fconfigure $fd}]} {
        # Not a Tcl channel, See if handle
        if {[pointer? $fd]} {
            set h $fd
        } else {
            error "$fd is not an existing file, handle or Tcl channel."
        }
    } else {
        # Tcl channel
        set h [get_tcl_channel_handle $fd read]
    }

    set result [list ]

    foreach opt {ctime atime mtime} time [GetFileTime $h] {
        if {$opts(all) || $opts($opt)} {
            lappend result -$opt $time
        }
    }

    if {$close_handle} {
        CloseHandle $h
    }

    return $result
}


# Set the times associated with a file
proc twapi::set_file_times {fd args} {

    array set opts [parseargs args {
        mtime.arg
        ctime.arg
        atime.arg
        preserveatime
    } -maxleftover 0 -nulldefault]

    if {$opts(atime) ne "" && $opts(preserveatime)} {
        win32_error 87 "Cannot specify -atime and -preserveatime at the same time."
    }
    if {$opts(preserveatime)} {
        set opts(atime) -1;             # Meaning preserve access to original
    }

    # Figure out if fd is a file path, Tcl channel or a handle
    set close_handle false
    if {[file exists $fd]} {
        if {$opts(preserveatime)} {
            win32_error 87 "Cannot specify -preserveatime unless file is specified as a Tcl channel or a Win32 handle."
        }

        # It's a file name
        # 0x02000000 -> FILE_FLAG_BACKUP_SEMANTICS, always required in case 
        # opening a directory (even if SeBackupPrivilege is not held
        set h [create_file $fd -access {generic_write} -createdisposition open_existing -flags 0x02000000]
        set close_handle true
    } elseif {[catch {fconfigure $fd}]} {
        # Not a Tcl channel, assume a handle
        set h $fd
    } else {
        # Tcl channel
        set h [get_tcl_channel_handle $fd read]
    }

    SetFileTime $h $opts(ctime) $opts(atime) $opts(mtime)

    if {$close_handle} {
        CloseHandle $h
    }

    return
}

# Convert a device based path to a normalized Win32 path with drive letters
proc twapi::normalize_device_rooted_path {path args} {
    # TBD - keep a cache ?
    # For example, we need to map \Device\HarddiskVolume1 to C:
    # Can only do that by enumerating logical drives
    set npath [file nativename $path]
    if {![string match -nocase {\\Device\\*} $npath]} {
        error "$path is not a valid device based path."
    }
    array set device_map {}
    foreach drive [find_logical_drives] {
        set device_path [lindex [lindex [get_volume_info $drive -device] 1] 0]
        if {$device_path ne ""} {
            set len [string length $device_path]
            if {[string equal -nocase -length $len $path $device_path]} {
                # Prefix matches, must be terminated by end or path separator
                set ch [string index $npath $len]
                if {$ch eq "" || $ch eq "\\"} {
                    set path ${drive}[string range $npath $len end]
                    if {[llength $args]} {
                        upvar [lindex $args 0] retvar
                        set retvar $path
                        return 1
                    } else {
                        return $path
                    }
                }
            }
        }
    }

    if {[llength $args]} {
        return 0
    } else {
        error "Could not map device based path '$path'"
    }
}

proc twapi::flush_channel {chan} {
    flush $chan
    FlushFileBuffers [get_tcl_channel_handle $chan write]
}

proc twapi::find_file_open {path args} {
    variable _find_tokens
    variable _find_counter
    parseargs args {
        {detail.arg basic {basic full}}
    } -setvars -maxleftover 0

    set detail_level [expr {$detail eq "basic" ? 1 : 0}]
    if {[min_os_version 6 1]} {
        set flags 2;            # FIND_FIRST_EX_LARGE_FETCH - Win 7
    } else {
        set flags 0
    }
    # 0 -> search op. Could be specified as 1 to limit search to
    # directories but that is only advisory and does not seem to work
    # in many cases. So don't bother making it an option.
    lassign [FindFirstFileEx $path $detail_level 0 "" $flags] handle entry
    set token ff#[incr _find_counter]
    set _find_tokens($token) [list Handle $handle Entry $entry]
    return $token
}

proc twapi::find_file_close {token} {
    variable _find_tokens
    if {[info exists _find_tokens($token)]} {
        FindClose [dict get $_find_tokens($token) Handle]
        unset _find_tokens($token)
    }
    return
}

proc twapi::decode_file_attributes {attrs} {
    return [_make_symbolic_bitmask $attrs {
        archive               0x20
        compressed            0x800
        device                0x40
        directory             0x10
        encrypted             0x4000
        hidden                0x2
        integrity_stream      0x8000
        normal                0x80
        not_content_indexed   0x2000
        no_scrub_data         0x20000
        offline               0x1000
        readonly              0x1
        recall_on_data_access 0x400000
        recall_on_open        0x40000
        reparse_point         0x400
        sparse_file           0x200
        system                0x4
        temporary             0x100
        virtual               0x10000
    }]
}

proc twapi::find_file_next {token varname} {
    variable _find_tokens
    if {![info exists _find_tokens($token)]} {
        return false
    }
    if {[dict exists $_find_tokens($token) Entry]} {
        set entry [dict get $_find_tokens($token) Entry]
        dict unset _find_tokens($token) Entry
    } else {
        set entry [FindNextFile [dict get $_find_tokens($token) Handle]]
    }
    if {[llength $entry]} {
        upvar 1 $varname result
        set result [twine {attrs ctime atime mtime size reserve0 reserve1 name altname} $entry]
        return true
    } else {
        return false
    }
}

# Utility functions

proc twapi::_drive_rootpath {drive} {
    if {[_is_unc $drive]} {
        # UNC
        return "[string trimright $drive ]\\"
    } else {
        return "[string trimright $drive :/\\]:\\"
    }
}

proc twapi::_is_unc {path} {
    return [expr {[string match {\\\\*} $path] || [string match //* $path]}]
}


