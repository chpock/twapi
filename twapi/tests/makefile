TWAPI_SRCROOT = $(MAKEDIR)\..
!include ..\common.inc

!ifndef PACKAGE
!error Macro PACKAGE is not defined.
!endif

!ifndef PACKAGEDIR
PACKAGEDIR=$(TWAPI_SRCROOT)\dist
!endif

TESTFILES=all.tcl \
	echoservice.tcl \
	npecho.tcl \
	testutil.tcl \
	base.test \
	clipboard.test \
	com.test \
	console.test \
	crypto.test \
	desktop.test \
	device.test \
	disk.test \
	eventlog.test \
	handle.test \
	misc.test \
	msi.test \
	mstask.test \
	namedpipe.test \
	network.test \
	nls.test \
	osinfo.test \
	parseargs.test \
	pdh.test \
	power.test \
	printer.test \
	process.test \
	resource.test \
	security.test \
	services.test \
	share.test \
	shell.test \
	synch.test \
	trap.test \
	ui.test \
	client_share.vbs \
	disk.vbs \
	osinfo.vbs \
	process.vbs \
	services.vbs \
	share.vbs \
	thread.vbs \
	rctest.dll \
	rctest64.dll \
	rctest\bitmap.bmp

distribution: $(TESTFILES)
	-mkdir "$(PACKAGEDIR)\tests\rctest"
	!copy $** "$(PACKAGEDIR)\tests"

clean:
	-del *.*~
