# This script must be invoked by the Tcl shell from the Tcl distribution
# for which the MSI (Microsoft Installer) package is to be built.

# Make sure we are not picking up anything outside our installation
# even if TCLLIBPATH etc. is set
if {0 && [llength [array names env TCL*]] || [llength [array names env tcl*]]} {
    error "[array names env TCL*] environment variables must not be set"
}

package require fileutil

namespace eval msibuild {
    variable script_dir
    set script_dir [file attributes [file dirname [info script]] -shortname]

    # Strings and values used in the MSI to identify the product.
    # Dictionary keyed by platform x86 or x64
    variable architecture [expr {$::tcl_platform(pointerSize) == 8 ? "x64" : "x86"}]
    variable msi_strings
    array set msi_strings {
        ProductName        "Tcl/Tk for Windows"
        ProgramMenuDir     ProgramMenuDir
    }
    if {$architecture eq "x86"} {
        array set msi_strings {
            UpgradeCode        9888EC4F-7EB8-40EF-8506-7230E811AFE9
            ProgramFilesFolder ProgramFilesFolder
            Win64              no
            ArchString         32-bit
        }
    } else {
        array set msi_strings {
            UpgradeCode        1AE719B3-0895-4913-B8BF-1117944A7046
            ProgramFilesFolder ProgramFiles64Folder
            Win64              yes
            ArchString         64-bit
        }
    }
    
    # Define included features. A dictionary keyed by the MSI feature Id
    # The dictionary values are themselves
    # dictionaries with the keys below:
    #
    # TclPackages - list of Tcl packages to include in this MSI package (optional)
    # Name - The Title to be shown in the MSI feature tree
    # Description - Description to be shown in the Installer (optional)
    # Documentation - link to the documentation (optional)
    # Paths - List of glob paths for  files belonging to the package.
    #   Optional. If not specified, the script will try figuring it out.
    #   Directories will include all files under that directory. Paths must
    #   be relative to the root of the Tcl installation.
    # Mandatory - if 2, the package must be installed. 1 User selectable
    #   defaulting to yes. 0 User selectable defaulting to no.  Optional.
    #   If unspecified, defaults to 1
    #
    # The following additional keys are computed from the above as we
    # go along
    # Files - list of *normalized* file paths
    # Version - version of the package if available
    variable feature_definitions

    # This should be read from a config file. Oh well. Later ...
    set feature_definitions {
        core {
            Name {Tcl/Tk Core}
            TclPackages { Tcl Tk }
            Description {Includes Tcl and Tk core, Windows registry and DDE extensions.}
            Paths {bin lib/tcl8 lib/tcl8.* lib/dde* lib/reg* lib/tk8.*}
            Mandatory 2
        }
        itcl {
            Name {Incr Tcl}
            TclPackages Itcl
            Description {Incr Tcl object oriented extension}
        }
        tdbc {
            Name TDBC
            TclPackages tdbc
            Description {Tcl Database Connectivity extension}
            Paths {lib/tdbc* lib/sqlite*}
        }
        twapi {
            Name {Tcl Windows API}
            TclPackages twapi
            Description {Extension for accessing the Windows API}
        }
        threads {
            Name Threads
            TclPackages Thread
            Description {Extension for script-level access to Tcl threads}
        }
        clibs {
            {C libraries} 
            Description {C libraries for building your own binary extensions}
            Paths {include lib/*.lib}
            Mandatory 0
        }
    }        

    # selected_features contains the actual selected features from the above.
    variable selected_features
    
    # Root of the Tcl installation.
    # Must be normalized else fileutil::relative etc. will not work
    # because they do not handle case differences correctly
    variable tcl_root [file normalize [file dirname [file dirname [info nameofexecutable]]]]

    # Contains a dictionary of all directory paths mapping them to an id
    # Again normalized for same reason as above.
    variable directories {}

    # Used for keeping track of tags in xml generation
    variable xml_tags {}
}

# Generates a unique id
proc msibuild::id {{path {}}} {
    variable id_counter
    variable tcl_root
    if {$path eq ""} {
        return "ID[incr id_counter]"
    } else {
        set path [fileutil::relative $tcl_root $path]
        return "ID[incr id_counter]_[string map {/ _ : _ - _ + _} $path]"
    }
}

# Returns the id of the Tcl bin directory
proc msibuild::bin_dir_id {} {
    variable directories
    variable tcl_root
    return [dict get $directories [file join $tcl_root bin]]
}

# Build a file path list for a MSI package. Returned value is a nested
# list consisting of file paths only (no directories)
proc msibuild::build_file_paths_for_feature {feature} {
    variable selected_features
    variable tcl_root

    log Building file paths for $feature
    
    set files {}
    set dirs {}
    dict with selected_features $feature {
        if {[info exists Paths]} {
            foreach glob $Paths {
                foreach path [glob [file join $tcl_root $glob]] {
                    if {[file isfile $path]} {
                        lappend files [file normalize $path]
                    } else {
                        lappend dirs $path
                    }
                }                    
            }
        } else {
            # If no Paths dictionary entry, build it based on the package name
            # and version number.
            if {![info exists TclPackages] || [llength TclPackages] == 0} {
                error "No TclPackages or Paths entry for \"$feature\""
            }
            foreach pack $TclPackages {
                lappend dirs {*}[glob [file join $tcl_root lib ${pack}*]]
            }
        }
    }

    foreach dir $dirs {
        lappend files {*}[lmap path [fileutil::find $dir {file isfile}] {
            file normalize $path
        }]
    }
    dict set selected_features $feature Files [lsort -unique $files]
}

proc msibuild::add_parent_directory {path} {
    variable directories
    variable tcl_root
    
    if {[file pathtype $path] ne "absolute"} {
        error "Internal error: $path is not a absolute normalized path"
    }
    set parent [file normalize [file dirname $path]]
    if {$parent eq $tcl_root} {
        return; # Top level
    }
    if {![dict exists $directories $parent]} {
        add_parent_directory $parent
        dict set directories $parent [id $parent]
    }
}

# Builds the file paths for all files contained in all MSI package
proc msibuild::build_file_paths {} {
    variable selected_features

    dict set directory_tree . Subdirs {}
    foreach feature [dict keys $selected_features] {
        build_file_paths_for_feature $feature
        foreach path [dict get $selected_features $feature Files] {
            add_parent_directory $path
        }
    }                             
}

# Generate the Directory nodes
proc msibuild::generate_directory_tree {dir} {
    variable directories
    variable tcl_root

    if {[file pathtype $dir] ne "absolute"} {
        error "Path \"$dir\" is not an absolute path"
    }

    # Note assumes no links

    set dir [file normalize $dir]

    set reldir [fileutil::relative $tcl_root $dir]
    set subdirs [glob -nocomplain -types d -dir $dir -- *]

    # To get indentation right, we have to generate the outer tags
    # before inner tags
    if {$reldir eq "."} {
        # These exact values to allow user to choose folder based
        # on WixUI_Advanced dialog
        set id   APPLICATIONFOLDER
        set name Tcl
    } else {
        if {![dict exists $directories $dir]} {
            puts stderr "Directory \"$dir\" not in a package. Skipping..."
            return
        }
        set name [file tail $dir]
        set id   [dict get $directories $dir]
    }
    if {[llength $subdirs] == 0} {
        return [tag/ Directory Name $name Id $id]
    }
    set xml [tag Directory Name $name Id $id]
    foreach subdir $subdirs {
        append xml [generate_directory_tree $subdir]
    }
    append xml [tag_close Directory]
    return $xml
}

# Generates the <Directory> entries for installation.
proc msibuild::generate_directory {} {
    variable tcl_root
    variable msi_strings

    # Use of the WixUI_Advanced dialogs requires the following
    # Directory element structures.
    append xml [tag Directory Id TARGETDIR Name SourceDir]
    
    append xml [tag Directory Id $msi_strings(ProgramFilesFolder) Name PFiles]
    append xml [generate_directory_tree $tcl_root]
    append xml [tag_close];     # ProgramFilesFolder

    # NOTE: We use ProgramMenuFolder because StartMenuFolder is not available
    # on XP Windows installer
    append xml [tag Directory Id ProgramMenuFolder]
    append xml [tag Directory Id TclStartMenuFolder Name Tcl[info tclversion]]
    append xml [tag_close Directory Directory]; # TclStartMenuFolder ProgramMenuFolder

    append xml [tag_close Directory];     # TARGETDIR

    return $xml
}

proc msibuild::generate_file {path {file_id {}} {name {}}} {
    variable directories

    if {[file pathtype $path] ne "absolute"} {
        error "generate_file passed a non-absolute path"
    }
    set dir [file dirname $path]
    if {![dict exists $directories $dir]} {
        error "Could not find directory \"$dir\" in directories dictionary"
    }
    set dir_id [dict get $directories $dir]
    if {$file_id eq ""} {
        set file_id [id $path]
    }
    if {$name ne ""} {
        set name_attr [list Name $name]
    } else {
        set name_attr {}
    }
    # Every FILE must be enclosed in a Component and a Component should
    # have only one file.
    set xml [tag Component \
                 Id CMP_$file_id \
                 Guid * \
                 Directory $dir_id]
    append xml [tag/ File \
                    Id $file_id \
                    {*}$name_attr \
                    Source $path \
                    KeyPath yes]
    append xml [tag_close Component]
                
}

proc msibuild::generate_features {} {
    variable selected_features
    variable tcl_root

    set xml ""
    dict for {fid feature} $selected_features {
        set absent allow
        if {[dict exists $feature Mandatory]} {
            switch -exact -- [dict get $feature Mandatory] {
                2 { set absent disallow }
                1 { set absent allow }
                0 {
                    # TBD - how to set the default state to NOT INSTALL ?
                    set absent allow
                }
                default {
                    error "Unknown value [dict get $feature Mandatory] for Mandatory feature definition key."
                }
            }
        }
        if {[dict exists $feature Version]} {
            set version " Version [dict get $feature Version]"
        } else {
            set version ""
        }
        if {[dict exists $feature Description]} {
            set description "[dict get $feature Description]$version"
        } else {
            set description $version
        }

        append xml [tag Feature \
                        Id $fid \
                        Level 1 \
                        Title [dict get $feature Name] \
                        Description $description \
                        Absent $absent]
        foreach path [dict get $feature Files] {
            append xml [generate_file $path]
        }

        # TBD - For the core feature, we want to create new exes with predefined
        # ids for shortcuts etc. I hate this hardcoding but can't figure
        # out the magic required to be able to define these outside of
        # the Feature element. Using FeatureRef generates a multiple
        # primary reference error. Using a Fragment is something to be tried.
        # 
        if {$fid eq "core"} {
            append xml [generate_file [file join $tcl_root bin tclsh86t.exe] TCLSHEXE tclsh.exe]
            append xml [generate_file [file join $tcl_root bin wish86t.exe] WISHEXE wish.exe]
        }

        append xml [tag_close Feature]
                        
    }
    return $xml
}

# Generate the UI elements
proc msibuild::generate_ui {} {
    variable script_dir
    
    append xml [tag/ UIRef Id WixUI_Advanced]
    # Following property provides the default dir name for install
    # when using WixUI_Advanced dialog.
    append xml [tag/ Property Id ApplicationFolderName Value "Tcl"]
    
    # Set the default when showing the per-user/per-machine dialog
    # Note that if per-user is chosen, the user cannot choose
    # location of install
    append xml [tag/ Property Id WixAppFolder Value WixPerUserFolder]

    # License file
    append xml [tag/ WixVariable Id WixUILicenseRtf Value [file join $script_dir license.rtf]]
    
    # The background for Install dialogs
    append xml [tag/ WixVariable Id WixUIDialogBmp Value [file join $script_dir msidialog.bmp]]
    
    # The horizontal banner for Install dialogs
    append xml [tag/ WixVariable Id WixUIBannerBmp Value [file join $script_dir msibanner.bmp]]
    
    return $xml
}

# Generate pre-launch conditions in terms of platform requirements.
proc msibuild::generate_launch_conditions {} {
    append xml [tag Condition \
                    Message "This program is only supported on Windows XP and later versions of Windows."]
    append xml {<![CDATA[VersionNT >= 501]]>}
    append xml [tag_close Condition]

    append xml [tag Condition \
                    Message "This program is requires at least Service Pack 3 on Windows XP."]
    append xml {<![CDATA[VersionNT > 501 OR ServicePackLevel >= 3]]>}
    append xml [tag_close Condition]

    return $xml
}

# Generate the Add/Remove program properties
proc msibuild::generate_arp {} {
    variable script_dir
    string cat \
        [tag/ Property Id ARPURLINFOABOUT Value http://www.tcl.tk] \
        [tag/ Property Id ARPHELPLINK Value http://www.tcl.tk/man/tcl[info tclversion]] \
        [tag/ Property Id ARPCOMMENTS Value "The Tcl programming language and Tk graphical toolkit"] \
        [tag/ Property Id ARPPRODUCTICON Value [file join $script_dir tcl.ico]]
}

# Allow user to modify path.
proc msibuild::generate_path_feature {} {
    variable directories
    variable tcl_root

    append xml [tag Feature \
                    Id [id] \
                    Level 1 \
                    Title {Modify Paths} \
                    Description {Modify PATH environment variable to include the Tcl/Tk directory}]

    append xml [tag Component Id [id] Guid 5C4574A9-ECE5-4565-BA0D-38AC38755C4E KeyPath yes Directory [bin_dir_id]]
    # TBD - Should System be set to "yes" for machine installs?
    append xml [tag/ Environment \
                    Action set \
                    Id [id] \
                    Name Path \
                    Value {[APPLICATIONFOLDER]bin} \
                    System no \
                    Permanent no \
                    Part last \
                    Separator ";"]
                
    append xml [tag_close Component Feature]

    return $xml
}

proc msibuild::generate_start_menu_feature {} {
    append xml [tag Feature \
                    Id [id] \
                    Level 1 \
                    Title {Start menu} \
                    Description {Install Start menu shortcuts}]

    append xml [tag Component Id [id] Guid * Directory TclStartMenuFolder] 
    # TBD - can we change Target to [#TCLSHEXE]?
    append xml [tag/ Shortcut Id [id] \
                    Name "tclsh" \
                    Description "Tcl console shell" \
                    Target {[APPLICATIONFOLDER]bin\tclsh.exe}]

    # Arrange for the folder to be removed on an uninstall
    # We only include this for one shortcut component
    append xml [tag/ RemoveFolder Id RemoveTclStartMenuFolder \
                    Directory TclStartMenuFolder \
                    On uninstall]
    append xml [tag/ RegistryValue Root HKCU \
                    Key "Software\\Tcl\\[info tclversion]" \
                    Name installed \
                    Type integer \
                    Value 1 \
                    KeyPath yes]
    # APN append xml [tag_close Component]

    # APN append xml [tag Component Id [id] Guid 57009BF7-3E8D-49C8-A557-26F86943233F Directory TclStartMenuFolder]
    append xml [tag/ util:InternetShortcut \
                    Id TclManPage \
                    Name Tcl \
                    Target http://tcl.tk/man/tcl[info tclversion]/contents.htm \
                    Type url]
    if {0} {
    append xml [tag/ RemoveFolder Id RemoveTclDocMenuFolder \
                    Directory TclDocMenuFolder \
                    On uninstall]
    }
    if {0} {
    append xml [tag/ RegistryValue Root HKCU \
                    Key "Software\\Tcl\\[info tclversion]\\Doc" \
                    Name installed \
                    Type integer \
                    Value 1 \
                    KeyPath yes]
    }
    append xml [tag_close Component]

    if {0} {
    append xml [tag Component Id [id] Guid *]
    # TBD - can we change Target to WISHEXE?
    append xml [tag/ Shortcut Id [id] \
                    Name "wish" \
                    Description "Tcl/Tk graphical shell" \
                    Directory TclStartMenuFolder \
                    Target {[APPLICATIONFOLDER]bin\wish.exe}]
    append xml [tag_close Component]

    # TBD - should be tied to tkcon feature
    append xml [tag Component Id [id] Guid *]
    append xml [tag/ Shortcut Id [id] \
                    Name "tkcon" \
                    Description "TkCon enhanced graphical console" \
                    Directory TclStartMenuFolder \
                    Target {[APPLICATIONFOLDER]bin\wish.exe} \
                    Arguments {[APPLICATIONFOLDER]bin\tkcon.tcl}]
    append xml [tag_close Component]
    }
    
    # TBD - icons on shortcuts? See Wix Tools book

    # Comment out desktop shortcut for now. Not really warranted
    if {0} {
        append xml [tag Component Id [id] Guid *]
        append xml [tag/ Shortcut Id [id] \
                        Name "tkcon" \
                        Description "TkCon enhanced graphical console" \
                        Directory DesktopFolder \
                        Target {[APPLICATIONFOLDER]bin\wish.exe} \
                        Arguments {[APPLICATIONFOLDER]bin\tkcon.tcl}]
        # TBD - need a registry keypath here too?
        append xml [tag_close Component]
    }
    
    append xml [tag_close Feature]
}

# Option to associate .tcl and .tk files with tclsh and tk
proc msibuild::generate_file_assoc_feature {} {
    append xml [tag Feature \
                    Id TclFileAssoc \
                    Level 1 \
                    Title {File associations} \
                    Description {Associate .tcl and .tk files with tclsh and wish}]
    append xml [tag Component Id [id] Directory APPLICATIONFOLDER]

    # To associate a file, create a ProgId for Tcl. Then associate an
    # extension with it. HKMU -> HKCU for per-user and HKLM for per-machine
    set tcl_prog_id "Tcl.Application"
    append xml [tag/ RegistryValue \
                    Root HKMU \
                    Key "SOFTWARE\\Classes\\$tcl_prog_id" \
                    Name "FriendlyTypeName" \
                    Value "Tcl application" \
                    Type "string"]
    # TBD - Icon attribute for ProgId
    # TBD - Not sure of value for Advertise
    append xml [tag ProgId \
                    Id $tcl_prog_id \
                    Description "Tcl application" \
                    Advertise no]
    append xml [tag Extension Id "tcl"]
    append xml [tag/ Verb \
                    Id open \
                    TargetFile {[APPLICATIONFOLDER]bin\tclsh.exe} \
                    Command "Run as a Tcl application" \
                    Argument "&quot;%1&quot;"]
    append xml [tag_close Extension ProgId]
    append xml [tag_close Component Feature]

    return $xml
}

proc msibuild::generate {} {
    variable tcl_root
    variable msi_strings
    
    log Generating Wix XML
    
    set xml "<?xml version='1.0' encoding='windows-1252'?>\n"

    append xml [tag Wix \
                    xmlns http://schemas.microsoft.com/wix/2006/wi \
                    xmlns:util "http://schemas.microsoft.com/wix/UtilExtension"]

    # Product - info about Tcl itself
    # Name - Tcl/Tk for Windows
    # Id - "*" -> always generate a new one on every run. Makes upgrades
    #    much easier
    # UpgradeCode - must never change between releases else upgrades won't work.
    # Language, Codepage - Currently only English
    # Version - picked up from Tcl
    # Manufacturer - TCT? Tcl Community?
    append xml [tag Product \
                    Name        "Tcl/Tk for Windows ($msi_strings(ArchString))" \
                    Id          * \
                    UpgradeCode "413F733E-BBB8-47C7-AD49-D9E4B039438C" \
                    Language    1033 \
                    Codepage    1252 \
                    Version     [info patchlevel].0 \
                    Manufacturer "Tcl Community"]

    # Package - describes the MSI package itself
    # Compressed - always set to "yes".
    # InstallerVersion - version of Windows Installer required. Not sure
    #     the minimum required here but XP SP3 has 301 (I think)
    # NOTE: we do not set the following because it does not then allow
    #     per-machine installs
    # InstallPrivileges - "limited" if no elevation required, "elevated"
    #     if elevation required.
    # TBD - change installer version to be xp compatible
    append xml [tag/ Package \
                    Compressed       yes \
                    Id               * \
                    InstallerVersion 500 \
                    Description      "Installer for Tcl/Tk ($msi_strings(ArchString))"]

    # Checks for platforms
    append xml [generate_launch_conditions]
    
    # Upgrade behaviour. There is probably no reason to disallow downgrades
    # but I don't want to do the additional testing...
    append xml [tag/ MajorUpgrade \
                    AllowDowngrades no \
                    DowngradeErrorMessage "A later version of \[ProductName\] is already installed. Setup will now exit." \
                    AllowSameVersionUpgrades yes]
                
    # Media - does not really matter. We don't have multiple media.
    # EmbedCab - yes because the files will be embedded inside the MSI,
    #   and not stored separately
    append xml [tag/ Media \
                    Id       1 \
                    Cabinet  media1.cab \
                    EmbedCab yes]

    append xml [generate_arp];  # Information that shows in Add/Remove Programs
    
    # NOTE:Despite what the Wix reference says that it can be placed anywhere,
    # UIRef can't be the first child of Product element. So dump it here.
    append xml [generate_ui];   # Installation dialogs

    # The MSIINSTALLPERUSER only has effect on Win 7 and later using
    # Windows Installer 5.0 and is only effective if ALLUSERS=2
    # See https://msdn.microsoft.com/en-us/library/aa371865.aspx
    # The ALLUSERS property will be set based on the WixUI_Advanced dialog
    # user selection so I'm not quite sure if this is needed.
    append xml [tag/ Property Id MSIINSTALLPERUSER Secure yes Value 1]
    
    append xml [generate_directory]; # Directory structure
    append xml [generate_features];  # Feature tree

    append xml [generate_start_menu_feature]; # Option to add to Start menu
    append xml [generate_path_feature];       # Option to modify PATH
    if {0} {
        # Can't get file assoc to compile
        append xml [generate_file_assoc_feature]; # Option to associate .tcl etc. with tclsh/wish
    }
    
    append xml [tag_close_all]

    return $xml
}

# Buggy XML generator (does not encode special chars)
proc msibuild::tag {tag args} {
    variable xml_tags

    set indent [string repeat {  } [llength $xml_tags]]
    append xml "${indent}<$tag"
    set prefix " "
    dict for {attr val} $args {
        append xml "$prefix$attr='$val'"
        set prefix "\n${indent}[string repeat { }  [string length $tag]]  "
    }
    append xml ">\n"
    lappend xml_tags $tag
    
    return $xml
}

# Like tag but closes it as well
proc msibuild::tag/ {tag args} {
    variable xml_tags

    set indent [string repeat {  } [llength $xml_tags]]
    append xml "${indent}<$tag"
    set prefix " "
    dict for {attr val} $args {
        append xml "$prefix$attr='$val'"
        set prefix "\n${indent}[string repeat { }  [string length $tag]]  "
    }
    append xml "/>\n"
    return $xml
}

# Close xml tag(s). For each argument n,
# if n is an integer, the last that many tags are popped
# off the tag stack. Otherwise, n must be the name of the topmost tag
# and that tag is popped (this is to catch tag matching errors early)
proc msibuild::tag_close {args} {
    variable xml_tags
    if {[llength $args] == 0} {
        set args [list 1]
    }
    set xml {}
    foreach n $args {
        if {![string is integer -strict $n]} {
            set n 1
            set expected_tag [lindex $xml_tags end]
        }

        # Pop n tags
        if {[llength $xml_tags] < $n} {
            error "XML tag stack empty"
        }
        while {$n > 0} {
            set tag [lindex $xml_tags end]
            if {[info exists expected_tag] && $tag ne $expected_tag} {
                error "Tag nesting error. Attempt to terminate $expected_tag but innermost tag is $tag"
            }
            set xml_tags [lrange $xml_tags 0 end-1]
            append xml "[string repeat {  } [llength $xml_tags]]</$tag>\n"
            incr n -1
        }
    }
    return $xml
}

proc msibuild::tag_close_all {} {
    variable xml_tags
    return [tag_close [llength $xml_tags]]
}

# Gets the next arg from ::argv and raises error if no more arguments
# argv is modified accordingly.
proc msibuild::nextarg {} {
    global argv
    if {[llength $argv] == 0} {
        error "Missing argument"
    }
    set argv [lassign $argv arg]
    return $arg
}

proc msibuild::parse_command_line {} {
    global argv
    variable feature_definitions
    variable selected_features
    variable options
    variable architecture

    array set options {
        silent 0
    }
    
    while {[llength $argv]} {
        set arg [nextarg]
        if {$arg eq "--"} {
            break;   # Rest are all passed to subcommand as component names
        }
        switch -glob -- $arg {
            -silent { set options(silent) 1 }
            -outdir {
                set options([string range $arg 1 end]) [nextarg]
            }
            -* {
                error "Unknown option \"$arg\""
            }
            default {
                lappend options(features) $arg
            }
        }
    }

    if {![info exists options(features)] || [llength $options(features)] == 0} {
        set selected_features $feature_definitions
    } else {
        set selected_features [dict filter $feature_definitions key {*}$options(features)]
    }
    if {![info exists options(outdir)]} {
        set options(outdir) $architecture
    }
    set options(outdir) [file normalize $options(outdir)]
}

proc msibuild::log {args} {
    variable options
    if {!$options(silent)} {
        puts [join $args { }]
    }
}

proc msibuild::main {} {
    variable selected_features
    variable feature_definitions
    variable tcl_root
    variable options
    variable architecture
    variable msi_strings
    
    parse_command_line
    log Building $architecture MSI for [join [dict keys $selected_features] {, }]
    build_file_paths 
    set xml [generate]

    file mkdir $options(outdir)

    set wxs [file join $options(outdir) tcl$architecture.wxs]
    log Writing Wix XML file $wxs
    set fd [open $wxs w]
    fconfigure $fd -encoding utf-8
    puts $fd $xml
    close $fd

    if {[info exists ::env(WIX)]} {
        set candle [file join $::env(WIX) bin candle.exe]
        set light  [file join $::env(WIX) bin light.exe]
    } else {
        # Assume on the path
        set candle candle.exe
        set light  light.exe
    }

    set outdir [file attributes $options(outdir) -shortname]
    set wixobj [file join $outdir tcl$architecture.wixobj]
    log Generating Wix object file $wixobj
    if {$architecture eq "x86"} {
        set arch {}
    } else {
        set arch [list -arch x64]
    }
    exec $candle -nologo {*}$arch -ext WixUIExtension.dll -ext WixUtilExtension.dll -out $wixobj $wxs
    
    set msi [file join $outdir "Tcl Installer ($msi_strings(ArchString)).msi"]
    log Generating MSI file $msi
    exec $light -out $msi -ext WixUIExtension.dll -ext WixUtilExtension.dll $wixobj

    log MSI file $msi created.
}


# If we are the command line script run as main program.
# The ... is to ensure last path component gets normalized if it is a link
if {[info exists argv0] && 
    [file dirname [file normalize [info script]/...]] eq [file dirname [file normalize $argv0/...]]} {
    msibuild::main
}
