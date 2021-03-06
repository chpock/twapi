#ifndef TWAPI_BASE_H
# define TWAPI_BASE_H

extern OSVERSIONINFOW gTwapiOSVersionInfo;

typedef struct _TwapiBaseSettings {
    unsigned int use_unicode_obj; /* Whether to use utf8 or wide chars when
                                     creating strings */
} TwapiBaseSettings;
extern TwapiBaseSettings gBaseSettings;

/* Contains per-interp context specific to the base module. Hangs off
 * the module.pval field in a TwapiInterpContext.
 */
typedef struct _TwapiBaseSpecificContext {
    /*
     * We keep a stash of commonly used Tcl_Objs so as to not recreate
     * them every time. Example of intended use is as keys in a keyed list or
     * dictionary when large numbers of objects are involved.
     *
     * Should be accessed only from the Tcl interp thread.
     */
    Tcl_HashTable atoms;

    /*
     * We keep track of pointers returned to scripts to prevent double frees,
     * invalid pointers etc.
     *
     * Should be accessed only from the Tcl interp thread.
     */
    Tcl_HashTable pointers;

    Tcl_Obj *trapstack;         /* ListObj containing stack used by trap
                                   command */

} TwapiBaseSpecificContext;
#define BASE_CONTEXT(ticP_) ((TwapiBaseSpecificContext *)((ticP_)->module.data.pval))

/* Stuff common to base module but not exported */
TwapiInterpContext *TwapiGetBaseContext(Tcl_Interp *interp);
int Twapi_GetVersionEx(Tcl_Interp *interp);
Tcl_Obj *Twapi_GetAtomStats(TwapiInterpContext *ticP) ;
Tcl_Obj *Twapi_GetAtoms(TwapiInterpContext *ticP) ;
TCL_RESULT TwapiCStructDefDump(Tcl_Interp *interp, Tcl_Obj *csObj);
void TwapiFfiInit(Tcl_Interp *interp);

TwapiTclObjCmd Twapi_ParseargsObjCmd;
TwapiTclObjCmd Twapi_TrapObjCmd;
TwapiTclObjCmd Twapi_KlGetObjCmd;
TwapiTclObjCmd Twapi_TwineObjCmd;
TwapiTclObjCmd Twapi_RecordArrayHelperObjCmd;
TwapiTclObjCmd Twapi_RecordObjCmd;
TwapiTclObjCmd Twapi_GetTwapiBuildInfo;
TwapiTclObjCmd Twapi_InternalCastObjCmd;
TwapiTclObjCmd Twapi_GetTclTypeObjCmd;
TwapiTclObjCmd Twapi_EnumPrintersLevel4ObjCmd;
TwapiTclObjCmd Twapi_FfiCallObjCmd;
#ifdef OBSOLETE
TwapiTclObjCmd Twapi_FfiLoadObjCmd;
TwapiTclObjCmd Twapi_Ffi0ObjCmd;
TwapiTclObjCmd Twapi_FfiHObjCmd;
#endif


#endif
