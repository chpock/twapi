# Common file defining build rules
# This is split off from common.inc because we want to give the parent
# makefile a chance to define $(OBJS)

#
# Rule for linking the module. This depends heavily on whether we
# are building the single dll version or multiple dll or a static lib
# and whether scripts are embedded. 
#
# Basic DLL building/linking :
#
# [1] All sources are compiled to objects in $(OBJDIR) based on an 
#     inference rule.
#
# [2] Then if building multiple DLL's these objects are linked into a DLL
#     when the module is built. Each module's resource definition file
#     is compiled and linked into the DLL (more on this below).
#     The initialization functions for each module are automatically
#     called by Tcl when the module is loaded.
#
# [3] If building a single DLL, TWAPI_SINGLE_MODULE is defined. In
#     this case,
#	[a] the rule for linking to a DLL is only defined for the
#           twapi_base module.  
#       [b] For others, the objects built but not linked into a module DLL.
#           Instead, a *.link file is created in the twapi_base dir 
#           by each module that lists its objects and libs.
#       [c] The link command for the twapi_base module includes the
#           additional objects and libraries by combining all *.link
#           files into one and passing to the linker.
#       [d] The resource compiler is run only for the twapi_base module
#           and its output is linked to the DLL (more on this below
#           in the embedding section).
#       [e] Since Tcl does not explicitly call module initialization
#           functions (except for the twapi_base DLL which is explicitly
#           loaded), each module needs to provide a way for its
#           initialization function to be called. These initialization
#           fragments and associated prototypes are contained in the
#           files twapi_module_static_{init,proto}.h. These files
#           used to be automatically generated but that is no longer
#           true, partly to support MinGW builds.
#
# Embedding of scripts:
#
#  [4] If scripts are not to be embedded in the DLL, the resource
#      TWAPI_SCRIPT_RESOURCE_PATH is not defined and the DLL resource
#      definition file is compiled as is as described above in the building
#      of the DLL. THIS CASE IS NOT CURRENTLY USED - EVEN IF THE TCL
#      SCRIPT ITSELF IS NOT EMBEDDED, A STUB IS EMBEDDED THAT SOURCES THE
#      TCL script.
#  [5] If the module Tcl script is to be embedded in the DLL,
#      TWAPI_SCRIPT_RESOURCE_PATH is defined and all Tcl files for a
#      module are combined into a single (optionally compressed) file
#      that will be bound to the resource.
#      [a] If building separate DLL's, each module build writes the resource
#          def line to a .rcfrag in its own directory. Exception is for
#          Tcl-only modules which always write to the twapi_base dir
#      [b] If building a single DLL, each module writes the resource
#          definition line to a *.rcfrag file in the twapi_base directory
#          in much the same fashion as the *.link files described above.
#      [c] In both above cases, the rcfrag files are then appended to the
#          module or twapi_base resource file so scripts are bound to the DLL.
#

# If building a lib, default to lzma 
!if defined(TWAPI_STATIC_BUILD) && ! defined(EMBED_SCRIPT)
EMBED_SCRIPT=lzma
!endif

!if defined(TWAPI_SINGLE_MODULE) || "$(OBJS)" == ""
TWAPI_SCRIPT_RESOURCE_DIR=$(OBJDIR)\..\twapi_base\script_resources
!else
TWAPI_SCRIPT_RESOURCE_DIR=$(OBJDIR)\script_resources
!endif
!if "$(EMBED_SCRIPT)" == "" || "$(EMBED_SCRIPT)" == "none"

# Not embedding the scripts themselves. Embed a stub that will source the files
TWAPI_SCRIPT_RESOURCE_TYPE=tclscript
TWAPI_SCRIPT_RESOURCE=$(MODULENAME)_source_stub

# Undefine to indicate actual scripts are not embedded
!  undef EMBED_SCRIPT

!elseif "$(EMBED_SCRIPT)" == "lzma"

TWAPI_SCRIPT_RESOURCE_TYPE=tclscriptlzma
TWAPI_SCRIPT_RESOURCE=combined_$(MODULENAME)_script.lzma

!  elseif "$(EMBED_SCRIPT)" == "plain"

TWAPI_SCRIPT_RESOURCE_TYPE=tclscript
TWAPI_SCRIPT_RESOURCE=combined_$(MODULENAME)_script

!  else

!    error EMBED_SCRIPT must be undefined, "none", "lzma" or "plain"

!  endif

# Note: Do NOT enclose TWAPI_SCRIPT_RESOURCE_PATH in quotes even though
# it is a file name, not a path because when passed to the rc compiler
# as an include, it should not have quotes
TWAPI_SCRIPT_RESOURCE_PATH=$(TWAPI_SCRIPT_RESOURCE_DIR)\$(TWAPI_SCRIPT_RESOURCE)

# See [3d], [5] - building resource files
!if defined(TWAPI_SINGLE_MODULE) || "$(OBJS)" == ""
# See [5b]
RCFRAGDIR=$(OBJDIR)\..\twapi_base
!else
# See [5a]
RCFRAGDIR=$(OBJDIR)
!endif
RCFRAG="$(RCFRAGDIR)\$(MODULENAME).rcfrag"

all: build distribution

!ifdef OBJS
# Binary module
build: $(OBJDIR)\$(MODULE)
# Static library
lib: $(OBJDIR)\$(MODULELIB)
!else
# Tcl only module
build lib: $(RCFRAG) $(TWAPI_SCRIPT_RESOURCE_PATH)
!endif

distribution: build "$(PACKAGEDIR)"
!if "$(TCLFILES)" != "" && !defined(EMBED_SCRIPT)
	for %f in ($(TCLFILES)) do @xcopy /i/q/y %f "$(PACKAGEDIR)" >NUL
!endif
!if defined(OBJS)
	echo $(MODULENAME) load $(PREREQUISITES) >> "$(PACKAGEDIR)\pkgindex.modules"
! if "$(MODULENAME)" == "twapi_base" || ! defined(TWAPI_SINGLE_MODULE)
        $(COPY) "$(OBJDIR)\$(MODULE)" "$(PACKAGEDIR)"
! endif
!else
	echo $(MODULENAME) source $(PREREQUISITES) >> "$(PACKAGEDIR)\pkgindex.modules"
!endif
!  if defined(TWAPI_STATIC_BUILD) && "$(MODULENAME)" == "twapi_base" 
	$(COPY) "$(TWAPI_SCRIPT_RESOURCE_DIR)\*.*" "$(PACKAGEDIR)"
	$(COPY) "$(OBJDIR)\*.rcfrag" "$(PACKAGEDIR)\$(MODULENAME).rcfrag"
!  endif

"$(OBJDIR)" "$(PACKAGEDIR)":
	@if not exist $@ mkdir $@

!if defined(TWAPI_SINGLE_MODULE)
#  See [3] - Single combined DLL or static lib build
!  if  "$(MODULENAME)" == "twapi_base"
#    See [3a,c,e] - build twapi_base DLL with included other modules
"$(OBJDIR)\$(MODULE)": "$(OBJDIR)\$(MODULENAME).res" $(OBJS) "$(OBJDIR)\*.link"
	$(COPY) "$(OBJDIR)\*.link" "$(OBJDIR)\linkmodules"
!    if defined(TWAPI_STATIC_BUILD)
        $(LIBTOOL) -nologo -out:$@ "@$(OBJDIR)\linkmodules" $(OBJS)
!    else
        $(LD) $(LOPT) -out:$@ $(LIBS) "@$(OBJDIR)\linkmodules" "$(OBJDIR)\$(MODULENAME).res" $(OBJS)
#      See http://kb.froglogic.com/display/KB/Manifests. VC 9 *requires*
#      manifests for DLL's as well. Newer compilers do not seem to care
!      if $(VCVER) == 9
	cd $(OBJDIR) && $(MT) -manifest $(MODULE).manifest -outputresource:$(MODULE);2
!      endif $(VCVER) == 9
!    endif  TWAPI_STATIC_BUILD
!  else
#    See [3b] - building a module other than twapi_base in single DLL mode
"$(OBJDIR)\$(MODULE)": "$(OBJDIR)\..\twapi_base\$(MODULENAME).link" $(TWAPI_SCRIPT_RESOURCE_PATH) $(RCFRAG)

#    See [3b] - create link inputs for modules other than twapi_base
"$(OBJDIR)\..\twapi_base\$(MODULENAME).link" : $(OBJS)
	-@if not exist $(@D) mkdir $(@D)
!    if defined(TWAPI_STATIC_BUILD)
	echo $(OBJS) > $@
!    else
	echo $(EXTRALIBS) $(OBJS) > $@
!    endif
!  endif MODULENAME == twapi_base

!else

#  ! defined(TWAPI_SINGLE_MODULE)

#  See [2] - building multiple modules (! defined(TWAPI_SINGLE_MODULE))
#  Note we do not use $** in this rule as we do not want to include the
#  dependencies in other rules defined for $(OBJDIR)\$(MODULE)
$(OBJDIR)\$(MODULE): $(OBJDIR)\$(MODULENAME).res $(OBJS)
        $(LD) $(LOPT) -out:$@ $(LIBS) "$(OBJDIR)\$(MODULENAME).res" $(OBJS)
#  See http://kb.froglogic.com/display/KB/Manifests. VC 9 *requires*
#  manifests for DLL's as well. Newer compilers do not seem to care
!  if $(VCVER) == 9
	cd $(OBJDIR) && $(MT) -manifest $(MODULE).manifest -outputresource:$(MODULE);2
!  endif VCVER == 9

!endif defined(TWAPI_SINGLE_MODULE)

#      See [5b] - write a resource def fragment to include Tcl script
$(RCFRAG):
	-@if not exist "$(RCFRAGDIR)" mkdir "$(RCFRAGDIR)"
	echo set fn [file tail {$(TWAPI_SCRIPT_RESOURCE_PATH)}] ; puts "$(MODULENAME) $(TWAPI_SCRIPT_RESOURCE_TYPE) [set fn]" | $(TCLSH) > $(RCFRAG)
#	echo set fpath [file nativename [file normalize {$(TWAPI_SCRIPT_RESOURCE_PATH)}]] ; puts "$(MODULENAME) $(TWAPI_SCRIPT_RESOURCE_TYPE) [set fpath]" | $(TCLSH) > $(RCFRAG)

$(OBJDIR)\$(MODULENAME).res: $(OBJDIR) $(RCFRAG) $(RC_FILE_PATH) makefile $(TWAPI_SCRIPT_RESOURCE_PATH)
#      See [5a,b] - write a resource def fragment to include Tcl script
!if "$(MODULENAME)" == "twapi_base" || ! defined(TWAPI_SINGLE_MODULE)
#       See [5c] - append script resource def to rc file
	$(COPY) $(RC_FILE_PATH)+"$(RCFRAGDIR)\*.rcfrag" "$(OBJDIR)\$(MODULENAME).rc"
        rc $(INCFLAGS) $(RCFLAGS) -i "$(TWAPI_SCRIPT_RESOURCE_DIR)" -fo $@ "$(OBJDIR)\$(MODULENAME).rc"
!else
#       See [4]
        rc $(INCFLAGS) $(RCFLAGS)  -i "$(TWAPI_SCRIPT_RESOURCE_DIR)" -fo $@ $(RC_FILE_PATH)
!endif

!ifdef OBJS
$(OBJS): $(CINCLUDES) makefile
!endif

!if defined(EMBED_SCRIPT)

$(TWAPI_SCRIPT_RESOURCE_PATH): $(TCLFILES)
	-@if not exist "$(OBJDIR)\tcl" mkdir "$(OBJDIR)\tcl"
	-@if not exist "$(TWAPI_SCRIPT_RESOURCE_DIR)" mkdir "$(TWAPI_SCRIPT_RESOURCE_DIR)"
	@echo namespace eval twapi { variable $(PACKAGE)_rc_sourced 1 } > "$(OBJDIR)\tcl\rc_hdr.tmp"
	for %f in ($(TCLFILES)) do @xcopy /q/y/i %f "$(OBJDIR)\tcl" >NUL
! if "$(TWAPI_SCRIPT_RESOURCE_TYPE)" == "tclscript"
	cd "$(OBJDIR)\tcl" && $(TCLSH) "$(TOOLDIR)\createtmfile.tcl" -force -outfile "$(TWAPI_SCRIPT_RESOURCE_PATH)" -compact $(PACKAGE) $(MODULEVERSION) rc_hdr.tmp $$**
! else
	cd "$(OBJDIR)\tcl" && $(TCLSH) "$(TOOLDIR)\createtmfile.tcl" -force -outfile "$(TWAPI_SCRIPT_RESOURCE_PATH).raw" -compact $(PACKAGE) $(MODULEVERSION) rc_hdr.tmp $**
	"$(TOOLDIR)\lzma.exe" e "$(TWAPI_SCRIPT_RESOURCE_PATH).raw" "$(TWAPI_SCRIPT_RESOURCE_PATH)" 2> NUL:
	del "$(TWAPI_SCRIPT_RESOURCE_PATH).raw"
! endif

!else

# Not embedding the script. Embed a command to source the first file instead
$(TWAPI_SCRIPT_RESOURCE_PATH): $(TCLFILES)
	-@if not exist "$(OBJDIR)\tcl" mkdir "$(OBJDIR)\tcl"
	-@if not exist "$(TWAPI_SCRIPT_RESOURCE_DIR)" mkdir "$(TWAPI_SCRIPT_RESOURCE_DIR)"
	echo set fn [file join [lindex [split {$(TCLFILES)}] 0]] ; puts "source \[file join \[twapi::Twapi_GetInstallDir] [file tail $$fn]\]" | $(TCLSH) > $(TWAPI_SCRIPT_RESOURCE_PATH)

!endif defined(EMBED_SCRIPT)

$(OBJDIR)\$(MODULELIB): $(OBJDIR) $(OBJS) $(TWAPI_SCRIPT_RESOURCE_PATH) $(RCFRAG)
!if "$(MODULENAME)" == "twapi_base"
	$(COPY) "$(OBJDIR)\*.link" "$(OBJDIR)\linkmodules"
        $(LIBTOOL) -nologo -out:$@ "@$(OBJDIR)\linkmodules" $(OBJS)
!else
$(OBJDIR)\$(MODULELIB): "$(OBJDIR)\..\twapi_base\$(MODULENAME).link"
!endif


makefile: $(SRCROOT)\include\common.inc $(SRCROOT)\include\rules.inc

$(SRCROOT)\include\common.inc: $(SRCROOT)\include\version.inc

clean:
        -$(RMDIR) "$(OBJDIR)"

# Inference rules
# Compile a file
.c{$(OBJDIR)}.obj::
	$(CC) $(CFLAGS) -Fo$(OBJDIR)\ $<
