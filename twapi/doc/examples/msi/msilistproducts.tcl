# Windows Installer
# List product versions that are installed through Windows Installer

# Note this is a sample script for illustrative purposes. There is no
# error handling as such.

# Tested with TWAPI 3.2. Earlier version may need some modification.

package require twapi 3.2

# Array to map product state codes to display strings
array set product_state_map {
    -7  "Not used"
    -6  "Misconfigured"
    -5  "Incomplete"
    -4  "Source absent"
    -1  "Unknown"
    0   "Broken"
    1   "Advertised"
    2   "Absent"
    3   "Local"
    4   "Source"
    5   "Installed"
}

# Create a new Installer object
set msiobj [twapi::comobj WindowsInstaller.Installer]

# The Installer objects do not come with their own type library containing
# method definitions so we need to manually load the definitions
# for every object we create
twapi::cast_msi_object $msiobj Installer

# Get the product id list
set prodids    [list ]
set prodidsobj [$msiobj -get Products]

if {![$prodidsobj -isnull]} {
    twapi::cast_msi_object $prodidsobj StringList
    set count [$prodidsobj -get Count]
    for {set i 0} {$i < $count} {incr i} {
        lappend prodids [$prodidsobj -get Item $i]
    }
}
$prodidsobj -destroy

# Now we have a list of product id's. Print the product name, version and publisher
foreach prodid $prodids {
    set encoded_version [$msiobj -get ProductInfo $prodid Version]
    set version [expr {0xff & ($encoded_version >> 24)}].[expr {0xff & ($encoded_version >> 16)}].[expr {0xffff & $encoded_version}]
    set state [$msiobj -get ProductState $prodid]
    if {[info exists product_state_map($state)]} {
        set state $product_state_map($state)
    }
    puts "[$msiobj -get ProductInfo $prodid ProductName]: $state\n    Version: $version    Publisher: [$msiobj -get ProductInfo $prodid Publisher] "
}

# Get rid of objects we created
$msiobj -destroy
