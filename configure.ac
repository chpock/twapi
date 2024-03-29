#!/bin/bash -norc
dnl	This file is an input file used by the GNU "autoconf" program to
dnl	generate the file "configure", which is run during Tcl installation
dnl	to configure the system for the local environment.

#-----------------------------------------------------------------------
# Sample configure.in for Tcl Extensions.  The only places you should
# need to modify this file are marked by the string __CHANGE__
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
# This initializes the environment with PACKAGE_NAME and PACKAGE_VERSION
# set as provided.  These will also be added as -D defs in your Makefile
# so you can encode the package version directly into the source files.
# This will also define a special symbol for Windows (BUILD_sample in
# this case) so that we create the export library with the dll.
#-----------------------------------------------------------------------

AC_INIT([twapi],[4.7.2])

#--------------------------------------------------------------------
# Call TEA_INIT as the first TEA_ macro to set up initial vars.
# This will define a ${TEA_PLATFORM} variable == "unix" or "windows"
# as well as PKG_LIB_FILE and PKG_STUB_LIB_FILE.
# --------------------------------------------------------------------

TEA_INIT([3.9])

AC_CONFIG_AUX_DIR(tclconfig)

#--------------------------------------------------------------------
# Load the tclConfig.sh file
#--------------------------------------------------------------------

TEA_PATH_TCLCONFIG
TEA_LOAD_TCLCONFIG

#--------------------------------------------------------------------
# Load the tkConfig.sh file if necessary (Tk extension)
#--------------------------------------------------------------------

#TEA_PATH_TKCONFIG
#TEA_LOAD_TKCONFIG

#-----------------------------------------------------------------------
# Handle the --prefix=... option by defaulting to what Tcl gave.
# Must be called after TEA_LOAD_TCLCONFIG and before TEA_SETUP_COMPILER.
#-----------------------------------------------------------------------

TEA_PREFIX

#-----------------------------------------------------------------------
# Standard compiler checks.
# This sets up CC by using the CC env var, or looks for gcc otherwise.
# This also calls AC_PROG_CC, AC_PROG_INSTALL and a few others to create
# the basic setup necessary to compile executables.
#-----------------------------------------------------------------------

TEA_SETUP_COMPILER

#-----------------------------------------------------------------------
# __CHANGE__
# Specify the C source files to compile in TEA_ADD_SOURCES,
# public headers that need to be installed in TEA_ADD_HEADERS,
# stub library C source files to compile in TEA_ADD_STUB_SOURCES,
# and runtime Tcl library files in TEA_ADD_TCL_SOURCES.
# This defines PKG(_STUB)_SOURCES, PKG(_STUB)_OBJECTS, PKG_HEADERS
# and PKG_TCL_SOURCES.
#-----------------------------------------------------------------------

TEA_ADD_LIBS([])
TEA_ADD_STUB_SOURCES([])

#--------------------------------------------------------------------
# You can add more files to clean if your extension creates any extra
# files by extending CLEANFILES.
# Add pkgIndex.tcl if it is generated in the Makefile instead of ./configure
# and change Makefile.in to move it from CONFIG_CLEAN_FILES to BINARIES var.
#
# A few miscellaneous platform-specific items:
# TEA_ADD_* any platform specific compiler/build info here.
#--------------------------------------------------------------------

CLEANFILES="$CLEANFILES twapi_entry.tcl"
if test "${TEA_PLATFORM}" = "windows" ; then

    AC_CHECK_MEMBER([struct _SYSTEM_POWER_STATUS.SystemStatusFlag], [
        AC_DEFINE(HAVE_SYSTEM_STATUS_FLAG)
    ], [], [[#include <windows.h>]])

    TEA_ADD_INCLUDES([-I. -I\"$(${CYGPATH} ${srcdir}/twapi/include)\" -I\"${srcdir}/dyncall/dyncall-0.9/include\"])

    TEA_ADD_CFLAGS([-DUNICODE -D_UNICODE -DWINVER=0x0501 -D_WIN32_WINNT=0x0501 -DPSAPI_VERSION=1])

    TEA_ADD_SOURCES([
	    twapi/base/adsi.c
	    twapi/base/async.c
	    twapi/base/calls.c
	    twapi/base/errors.c
	    twapi/base/ffi.c
	    twapi/base/keylist.c
	    twapi/base/lzmadec.c
	    twapi/base/lzmainterface.c
	    twapi/base/memlifo.c
	    twapi/base/mycrt.c
	    twapi/base/parseargs.c
	    twapi/base/printer.c
	    twapi/base/recordarray.c
	    twapi/base/tclobjs.c
	    twapi/base/threadpool.c
	    twapi/base/trap.c
	    twapi/base/twapi.c
	    twapi/base/twine.c
	    twapi/base/util.c
	    twapi/base/win.c
	    twapi/base/winchars.c

	    twapi/account/account.c

	    twapi/apputil/apputil.c

	    twapi/clipboard/clipboard.c

	    twapi/com/com.c
	    twapi/com/comserver.c

	    twapi/console/console.c

	    twapi/crypto/crypto.c
	    twapi/crypto/sspi.c
	    twapi/crypto/pbkdf2.c

	    twapi/device/device.c

	    twapi/etw/etw.c

	    twapi/eventlog/eventlog.c
	    twapi/eventlog/evt.c

	    twapi/input/input.c

	    twapi/mstask/mstask.c

	    twapi/multimedia/multimedia.c

	    twapi/namedpipe/namedpipe.c

	    twapi/network/network.c

	    twapi/nls/nls.c

	    twapi/os/os.c

	    twapi/pdh/pdh.c

	    twapi/process/process.c

	    twapi/rds/rds.c

            twapi/registry/registry.c

	    twapi/resource/resource.c

	    twapi/security/security.c

	    twapi/service/service.c
	    twapi/service/scm.c

	    twapi/share/share.c

	    twapi/shell/shell.c

	    twapi/storage/storage.c
	    twapi/storage/dirmonitor.c

	    twapi/ui/ui.c
	    twapi/ui/gdi.c

	    twapi/winsta/winsta.c

	    twapi/wmi/wmi.c
    ])

    TEA_ADD_HEADERS([
	    twapi/include/twapi.h
	    twapi/include/twapi_ddkdefs.h
	    twapi/include/twapi_sdkdefs.h
	    twapi/include/zlist.h
	    twapi/include/memlifo.h
    ])

    TEA_ADD_LIBS([
		    kernel32.lib advapi32.lib user32.lib
		    rpcrt4.lib gdi32.lib psapi.lib netapi32.lib
		    pdh.lib winmm.lib mpr.lib ws2_32.lib uuid.lib
		    ole32.lib oleaut32.lib shell32.lib
		    winspool.lib version.lib iphlpapi.lib
		    powrprof.lib secur32.lib userenv.lib
		    wtsapi32.lib setupapi.lib uxtheme.lib
		    credui.lib crypt32.lib wintrust.lib
		])

    TEA_ADD_TCL_SOURCES([
	    twapi/tcl/twapi.tcl
	    twapi/tcl/base.tcl
	    twapi/tcl/handle.tcl
	    twapi/tcl/win.tcl
	    twapi/tcl/adsi.tcl

	    twapi/tcl/account.tcl

	    twapi/tcl/apputil.tcl

	    twapi/tcl/clipboard.tcl

	    twapi/tcl/com.tcl

	    twapi/tcl/console.tcl

	    twapi/tcl/crypto.tcl
	    twapi/tcl/sspi.tcl
	    twapi/tcl/tls.tcl

	    twapi/tcl/device.tcl

	    twapi/tcl/etw.tcl

	    twapi/tcl/eventlog.tcl
	    twapi/tcl/evt.tcl
	    twapi/tcl/winlog.tcl

	    twapi/tcl/input.tcl

	    twapi/tcl/metoo.tcl

	    twapi/tcl/msi.tcl

	    twapi/tcl/mstask.tcl

	    twapi/tcl/multimedia.tcl

	    twapi/tcl/namedpipe.tcl

	    twapi/tcl/network.tcl

	    twapi/tcl/nls.tcl

	    twapi/tcl/os.tcl

	    twapi/tcl/pdh.tcl

	    twapi/tcl/power.tcl

	    twapi/tcl/printer.tcl

	    twapi/tcl/process.tcl

	    twapi/tcl/rds.tcl

	    twapi/tcl/registry.tcl

	    twapi/tcl/resource.tcl

	    twapi/tcl/security.tcl

	    twapi/tcl/service.tcl

	    twapi/tcl/share.tcl

	    twapi/tcl/shell.tcl

	    twapi/tcl/storage.tcl

	    twapi/tcl/synch.tcl

	    twapi/tcl/ui.tcl

	    twapi/tcl/winsta.tcl

	    twapi/tcl/wmi.tcl

	    twapi/LICENSE
    ])

else
    # Ensure no empty else clauses
    :
    #TEA_ADD_SOURCES([unix/unixFile.c])
    #TEA_ADD_LIBS([-lsuperfly])
fi

#--------------------------------------------------------------------
# Choose which headers you need.  Extension authors should try very
# hard to only rely on the Tcl public header files.  Internal headers
# contain private data structures and are subject to change without
# notice.
# This MUST be called after TEA_LOAD_TCLCONFIG / TEA_LOAD_TKCONFIG
#--------------------------------------------------------------------

TEA_PUBLIC_TCL_HEADERS
#TEA_PRIVATE_TCL_HEADERS

#TEA_PUBLIC_TK_HEADERS
#TEA_PRIVATE_TK_HEADERS
#TEA_PATH_X

#--------------------------------------------------------------------
# Check whether --enable-threads or --disable-threads was given.
# This auto-enables if Tcl was compiled threaded.
#--------------------------------------------------------------------

TEA_ENABLE_THREADS

#--------------------------------------------------------------------
# The statement below defines a collection of symbols related to
# building as a shared library instead of a static library.
#--------------------------------------------------------------------

TEA_ENABLE_SHARED

#--------------------------------------------------------------------
# This macro figures out what flags to use with the compiler/linker
# when building shared/static debug/optimized objects.  This information
# can be taken from the tclConfig.sh file, but this figures it all out.
#--------------------------------------------------------------------

TEA_CONFIG_CFLAGS

# Link to either the 64- or 32-bit dyncall libs. This check has to happen
# after TEA_CONFIG_CFLAGS because that sets the do64bit variable
AS_IF([test "$do64bit" = "yes"], [
	  AC_SUBST(DYNCALL_LIBS, "${srcdir}/dyncall/dyncall-0.9/lib/release_amd64/libdyncall_s.lib")
      ], [
	  AC_SUBST(DYNCALL_LIBS, "${srcdir}/dyncall/dyncall-0.9/lib/release_x86/libdyncall_s.lib")
      ])

#--------------------------------------------------------------------
# Set the default compiler switches based on the --enable-symbols option.
#--------------------------------------------------------------------

TEA_ENABLE_SYMBOLS

#--------------------------------------------------------------------
# Everyone should be linking against the Tcl stub library.  If you
# can't for some reason, remove this definition.  If you aren't using
# stubs, you also need to modify the SHLIB_LD_LIBS setting below to
# link against the non-stubbed Tcl library.  Add Tk too if necessary.
#--------------------------------------------------------------------

AC_DEFINE(USE_TCL_STUBS, 1, [Use Tcl stubs])
#AC_DEFINE(USE_TK_STUBS, 1, [Use Tk stubs])

#--------------------------------------------------------------------
# This macro generates a line to use when building a library.  It
# depends on values set by the TEA_ENABLE_SHARED, TEA_ENABLE_SYMBOLS,
# and TEA_LOAD_TCLCONFIG macros above.
#--------------------------------------------------------------------

TEA_MAKE_LIB

#--------------------------------------------------------------------
# Determine the name of the tclsh and/or wish executables in the
# Tcl and Tk build directories or the location they were installed
# into. These paths are used to support running test cases only,
# the Makefile should not be making use of these paths to generate
# a pkgIndex.tcl file or anything else at extension build time.
#--------------------------------------------------------------------

TEA_PROG_TCLSH
#TEA_PROG_WISH

#--------------------------------------------------------------------
# Finally, substitute all of the various values into the Makefile.
# You may alternatively have a special pkgIndex.tcl.in or other files
# which require substituting th AC variables in.  Include these here.
#--------------------------------------------------------------------

AC_CONFIG_FILES([Makefile pkgIndex.tcl twapi_entry.tcl])
AC_OUTPUT
