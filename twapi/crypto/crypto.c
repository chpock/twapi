/* 
 * Copyright (c) 2007-2009 Ashok P. Nadkarni
 * All rights reserved.
 *
 * See the file LICENSE for license
 */

/* Interface to CryptoAPI */

#include "twapi.h"
#include "twapi_crypto.h"

#ifndef TWAPI_SINGLE_MODULE
HMODULE gModuleHandle;     /* DLL handle to ourselves */
#endif


static int Twapi_CertCreateSelfSignCertificate(TwapiInterpContext *ticP, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[]);
static TCL_RESULT TwapiCryptEncodeObject(Tcl_Interp *interp, MemLifo *lifoP,
                                         Tcl_Obj *oidObj, Tcl_Obj *valObj,
                                         CRYPT_OBJID_BLOB *blobP);
static TwapiCertGetNameString(
    Tcl_Interp *interp,
    PCCERT_CONTEXT certP,
    DWORD type,
    DWORD flags,
    Tcl_Obj *owhat);


#ifdef NOTNEEDED
/* RtlGenRandom in base provides this */
int Twapi_CryptGenRandom(Tcl_Interp *interp, HCRYPTPROV provH, DWORD len)
{
    BYTE buf[256];

    if (len > sizeof(buf)) {
        Tcl_SetObjErrorCode(interp,
                            Twapi_MakeTwapiErrorCodeObj(TWAPI_INTERNAL_LIMIT));
        Tcl_SetResult(interp, "Too many random bytes requested.", TCL_STATIC);
        return TCL_ERROR;
    }

    if (CryptGenRandom(provH, len, buf)) {
        TwapiSetObjResult(interp, ObjFromByteArray(buf, len));
        return TCL_OK;
    } else {
        return TwapiReturnSystemError(interp);
    }
}
#endif

static TCL_RESULT TwapiCryptDecodeObject(Tcl_Interp *interp, LPCSTR oid, void *penc, DWORD nenc, Tcl_Obj **objPP)
{
    Tcl_Obj *objP;
    void *pv;
    DWORD n;

    /* We handle only DWORD OIDs. These are passed as LPSTR due to the
       CryptDecodeObjectEx accepting either type as parameters */

    if (! CryptDecodeObjectEx(
            X509_ASN_ENCODING|PKCS_7_ASN_ENCODING,
            oid, penc, nenc,
            CRYPT_DECODE_ALLOC_FLAG | CRYPT_DECODE_NOCOPY_FLAG | CRYPT_DECODE_SHARE_OID_STRING_FLAG,
            NULL,
            &pv,
            &n))
        return TwapiReturnSystemError(interp);
    
    switch ((DWORD_PTR) oid) {
    case (DWORD_PTR) X509_ENHANCED_KEY_USAGE:
        objP = ObjFromArgvA(((CERT_ENHKEY_USAGE*)pv)->cUsageIdentifier,
                            ((CERT_ENHKEY_USAGE*)pv)->rgpszUsageIdentifier);
        break;
    default:
        LocalFree(pv);
        return TwapiReturnError(interp, TWAPI_UNSUPPORTED_TYPE);
    }

    LocalFree(pv);
    *objPP = objP;
    return TCL_OK;
}
    
                                         
/*
 * Note: Allocates memory for blobP from lifoP. Note structure internal
 * pointers may point to Tcl_Obj areas within valObj so
 *  TREAT RETURNED STRUCTURES AS VOLATILE.
 *
 * We use MemLifo instead of letting CryptEncodeObjectEx do its own
 * memory allocation because it greatly simplifies freeing memory in
 * caller when multiple allocations are made.
 */
static TCL_RESULT TwapiCryptEncodeObject(Tcl_Interp *interp, MemLifo *lifoP,
                                  Tcl_Obj *oidObj, Tcl_Obj *valObj,
                                  CRYPT_OBJID_BLOB *blobP)
{
    LPCSTR    soid;
    DWORD     dw;
    Tcl_Obj **objs;
    int       nobjs;
    int       status;
    void     *penc;
    int       nenc;
    union {
        void *pv;
        CERT_ALT_NAME_ENTRY  *altnameP;
    } p;

    /* Note: X509_ALTERNATE_NAME etc. are integer values cast as LPSTR in
       headers. Hence all the casting around soid. Ugh and Yuck */

    /* The oidobj may be specified as either a string or an integer */
    if (ObjToDWORD(NULL, oidObj, &dw) == TCL_OK && dw < 65536) {
        soid = (LPSTR) (DWORD_PTR) dw;
    } else {
        soid = ObjToString(oidObj);
        if (STREQ(soid, szOID_SUBJECT_ALT_NAME) ||
            STREQ(soid, szOID_ISSUER_ALT_NAME)) {
            soid = X509_ALTERNATE_NAME; /* soid NOW A DWORD!!! */
        } else {
            Tcl_SetObjResult(interp, Tcl_ObjPrintf("Unsupported OID \"%s\"",soid));
            return TCL_ERROR;
        }
    }

    switch ((DWORD_PTR)soid) {
    case (DWORD_PTR) X509_ALTERNATE_NAME:
        p.altnameP = MemLifoAlloc(lifoP, sizeof(*p.altnameP), NULL);
        if ((status = ObjGetElements(interp, valObj, &nobjs, &objs)) != TCL_OK)
            return status;
        if (nobjs != 2 ||
            ObjToDWORD(NULL, objs[0], &p.altnameP->dwAltNameChoice) != TCL_OK)
            goto invalid_name_error;
        switch (p.altnameP->dwAltNameChoice) {
        case CERT_ALT_NAME_RFC822_NAME: /* FALLTHROUGH */
        case CERT_ALT_NAME_DNS_NAME: /* FALLTHROUGH */
        case CERT_ALT_NAME_URL:
            p.altnameP->pwszRfc822Name = ObjToUnicode(objs[1]);
            break;
        case CERT_ALT_NAME_REGISTERED_ID:
            p.altnameP->pszRegisteredID = ObjToString(objs[1]);
            break;
        case CERT_ALT_NAME_OTHER_NAME: /* FALLTHRU */
        case CERT_ALT_NAME_DIRECTORY_NAME: /* FALLTHRU */
        case CERT_ALT_NAME_IP_ADDRESS: /* FALLTHRU */
        default:
            goto invalid_name_error;
        }
        break;

    default:
        Tcl_SetObjResult(interp, Tcl_ObjPrintf("Unsupported OID constant \"%d\"", (DWORD_PTR) soid));
        return TCL_ERROR;
    }

    /* Assume 256 bytes enough but get as much as we can */
    penc = MemLifoAlloc(lifoP, 256, &nenc);
    if (CryptEncodeObjectEx(PKCS_7_ASN_ENCODING|X509_ASN_ENCODING,
                            soid, /* Yuck */
                            p.pv, 0, NULL, penc, &nenc) == 0) {
        if (GetLastError() != ERROR_MORE_DATA)
            return TwapiReturnSystemError(interp);
        /* Retry with specified buffer size */
        penc = MemLifoAlloc(lifoP, nenc, &nenc);
        if (CryptEncodeObjectEx(PKCS_7_ASN_ENCODING|X509_ASN_ENCODING,
                                soid, /* Yuck */
                                p.pv, 0, NULL, penc, &nenc) == 0)
            return TwapiReturnSystemError(interp);
    }
    
    blobP->cbData = nenc;
    blobP->pbData = penc;

    /* Note caller has to MemLifoPopFrame to release lifo memory */
    return TCL_OK;

invalid_name_error:
    Tcl_SetObjResult(interp,
                     Tcl_ObjPrintf("Invalid or unsupported name format \"%s\"", ObjToString(valObj)));
    return TCL_ERROR;
}

static int Twapi_CertCreateSelfSignCertificate(TwapiInterpContext *ticP, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    void *pv;
    HCRYPTPROV hprov;
    DWORD flags;
    int status;
    CERT_NAME_BLOB name_blob;
    CRYPT_KEY_PROV_INFO ki, *kiP;
    CRYPT_ALGORITHM_IDENTIFIER algid, *algidP;
    Tcl_Obj **objs;
    int       nobjs;
    SYSTEMTIME start, end, *startP, *endP;
    PCERT_CONTEXT certP;
    CERT_EXTENSIONS exts, *extsP;
    MemLifoMarkHandle mark;

    mark = MemLifoPushMark(&ticP->memlifo);

    if ((status = TwapiGetArgsEx(ticP, objc-1, objv+1,
                                 GETHANDLET(pv, HCRYPTPROV),
                                 GETBA(name_blob.pbData, name_blob.cbData),
                                 GETINT(flags),
                                 ARGSKIP, // CRYPT_KEY_PROV_INFO
                                 ARGSKIP, // CRYPT_ALGORITHM_IDENTIFIER
                                 ARGSKIP, // STARTTIME
                                 ARGSKIP, // ENDTIME
                                 ARGSKIP, // EXTENSIONS
                                 ARGEND)) != TCL_OK)
        goto vamoose;
    

    if (pv && (status = TwapiVerifyPointer(interp, pv, CryptReleaseContext)) != TCL_OK)
        goto vamoose;

    hprov = (HCRYPTPROV) pv;
 
    /* Parse CRYPT_KEY_PROV_INFO */
    if ((status = ObjGetElements(interp, objv[4], &nobjs, &objs)) != TCL_OK)
        goto vamoose;

    if (nobjs == 0)
        kiP = NULL;
    else {
        if (TwapiGetArgsEx(ticP, nobjs, objs,
                           GETSTRW(ki.pwszContainerName),
                           GETSTRW(ki.pwszProvName),
                           GETINT(ki.dwProvType),
                           GETINT(ki.dwFlags),
                           GETINT(ki.cProvParam),
                           ARGSKIP,
                           GETINT(ki.dwKeySpec),
                           ARGEND) != TCL_OK
            ||
            ki.cProvParam != 0) {
            Tcl_SetResult(interp, "Invalid or unimplemented provider parameters", TCL_STATIC);
            status = TCL_ERROR;
            goto vamoose;
        }
        ki.rgProvParam = NULL;
        kiP = &ki;
    }

    /* Parse CRYPT_ALGORITHM_IDENTIFIER */
    if ((status = ObjGetElements(interp, objv[5], &nobjs, &objs)) != TCL_OK)
        goto vamoose;
    if (nobjs == 0)
        algidP = NULL;
    else {
        if (nobjs >= 2) {
            Tcl_SetResult(interp, "Invalid algorithm identifier format or unsupported parameters", TCL_STATIC);
            status = TCL_ERROR;
            goto vamoose;
        }
        algid.pszObjId = ObjToString(objs[0]);
        algid.Parameters.cbData = 0;
        algid.Parameters.pbData = 0;
        algidP = &algid;
    }

    if ((status = ObjGetElements(interp, objv[6], &nobjs, &objs)) != TCL_OK)
        goto vamoose;
    if (nobjs == 0)
        startP = NULL;
    else {
        if ((status = ObjToSYSTEMTIME(interp, objv[6], &start)) != TCL_OK)
            goto vamoose;
        startP = &start;
    }

    if ((status = ObjGetElements(interp, objv[7], &nobjs, &objs)) != TCL_OK)
        goto vamoose;
    if (nobjs == 0)
        endP = NULL;
    else {
        if ((status = ObjToSYSTEMTIME(interp, objv[7], &end)) != TCL_OK)
            goto vamoose;
        endP = &end;
    }

    if ((status = ObjGetElements(interp, objv[8], &nobjs, &objs)) != TCL_OK)
        goto vamoose;
    if (nobjs == 0)
        extsP = NULL;
    else {
        DWORD i;

        exts.rgExtension = MemLifoAlloc(
            &ticP->memlifo, nobjs * sizeof(CERT_EXTENSION), NULL);
        exts.cExtension = nobjs;

        for (i = 0; i < exts.cExtension; ++i) {
            Tcl_Obj **extobjs;
            int       nextobjs;
            int       bval;
            PCERT_EXTENSION extP = &exts.rgExtension[i];

            status = ObjGetElements(interp, objs[i], &nextobjs, &extobjs);
            if (status == TCL_OK) {
                if (nextobjs == 2 || nextobjs == 3) {
                    status = ObjToBoolean(interp, extobjs[1], &bval);
                    if (status == TCL_OK) {
                        extP->pszObjId = ObjToString(extobjs[0]);
                        extP->fCritical = (BOOL) bval;
                        if (nextobjs == 3) {
                            status = TwapiCryptEncodeObject(
                                interp, &ticP->memlifo,
                                extobjs[0], extobjs[2],
                                &extP->Value);
                        } else {
                            extP->Value.cbData = 0;
                            extP->Value.pbData = NULL;
                        }
                    }
                } else {
                    Tcl_SetResult(interp, "Certificate extension format invalid or not implemented", TCL_STATIC);
                    status = TCL_ERROR;
                }
            }

            if (status != TCL_OK)
                goto vamoose;
        }
    }

    certP = (PCERT_CONTEXT) CertCreateSelfSignCertificate(hprov, &name_blob, flags,
                                          kiP, algidP, startP, endP, extsP);

    if (certP) {
        if (TwapiRegisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
            Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
        Tcl_SetObjResult(interp, ObjFromOpaque(certP, "CERT_CONTEXT*"));
        status = TCL_OK;
    } else {
        status = TwapiReturnSystemError(interp);
    }

vamoose:
    MemLifoPopMark(mark);
    return status;
}

static int Twapi_CertGetCertificateContextProperty(Tcl_Interp *interp, PCCERT_CONTEXT certP, DWORD prop_id, int cooked)
{
    DWORD n = 0;
    TwapiResult result;
    void *pv;
    CERT_KEY_CONTEXT ckctx;
    char *s;
    DWORD_PTR dwp;
    TCL_RESULT res;

    result.type = TRT_BADFUNCTIONCODE;
    if (cooked) {
        switch (prop_id) {
        case CERT_ACCESS_STATE_PROP_ID:
        case CERT_KEY_SPEC_PROP_ID:
            result.type = TRT_DWORD; 
            n = sizeof(result.value.ival);
            result.type = CertGetCertificateContextProperty(certP, prop_id, &result.value.uval, &n) ? TRT_DWORD : TRT_GETLASTERROR;
            break;
        case CERT_DATE_STAMP_PROP_ID:
            n = sizeof(result.value.filetime);
            result.type = CertGetCertificateContextProperty(certP, prop_id,
                                                            &result.value.filetime, &n)
                ? TRT_FILETIME : TRT_GETLASTERROR;
            break;
        case CERT_ARCHIVED_PROP_ID:
            result.type = TRT_BOOL;
            if (! CertGetCertificateContextProperty(certP, prop_id, NULL, &n)) {
                if ((result.value.ival = GetLastError()) == CRYPT_E_NOT_FOUND)
                    result.value.bval = 0;
                else
                    result.type = TRT_EXCEPTION_ON_ERROR;
            } else
                result.value.bval = 1;
            break;

        case CERT_ENHKEY_USAGE_PROP_ID:
            if (! CertGetCertificateContextProperty(certP, prop_id, NULL, &n))
                return TwapiReturnSystemError(interp);
            pv = TwapiAlloc(n);
            if (! CertGetCertificateContextProperty(certP, prop_id, pv, &n)) {
                TwapiFree(pv);
                return TwapiReturnSystemError(interp);
            }        
            res = TwapiCryptDecodeObject(interp, X509_ENHANCED_KEY_USAGE, pv, n, &result.value.obj);
            TwapiFree(pv);
            if (res != TCL_OK)
                return res;
            result.type = TRT_OBJ;
            break;

        case CERT_KEY_CONTEXT_PROP_ID:
            n = ckctx.cbSize = sizeof(ckctx);
            if (CertGetCertificateContextProperty(certP, prop_id, &ckctx, &n)) {
                result.value.obj = ObjNewList(0, NULL);
                if (ckctx.dwKeySpec == AT_KEYEXCHANGE ||
                    ckctx.dwKeySpec == AT_SIGNATURE) 
                    s = "HCRYPTPROV";
                else
                    s = "NCRYPT_KEY_HANDLE";
                ObjAppendElement(NULL, result.value.obj, ObjFromOpaque((void*)ckctx.hCryptProv, s));
                ObjAppendElement(NULL, result.value.obj, ObjFromDWORD(ckctx.dwKeySpec));
            } else
                result.type = TRT_GETLASTERROR;
            break;
        
        case CERT_KEY_PROV_HANDLE_PROP_ID:
            n = sizeof(dwp);
            if (CertGetCertificateContextProperty(certP, prop_id, &dwp, &n)) {
                TwapiResult_SET_PTR(result, HCRYPTPROV, (void*)dwp);
            } else
                result.type = TRT_GETLASTERROR;
            break;

        case CERT_AUTO_ENROLL_PROP_ID:
        case CERT_EXTENDED_ERROR_INFO_PROP_ID:
        case CERT_FRIENDLY_NAME_PROP_ID:
        case CERT_PVK_FILE_PROP_ID:
            if (! CertGetCertificateContextProperty(certP, prop_id, NULL, &n))
                return TwapiReturnSystemError(interp);
            result.value.unicode.str = TwapiAlloc(n);
            if (CertGetCertificateContextProperty(certP, prop_id,
                                                  result.value.unicode.str, &n)) {
                result.value.unicode.len = -1;
                result.type = TRT_UNICODE_DYNAMIC; /* Will also free memory */
            } else {
                TwapiReturnSystemError(interp);
                TwapiFree(result.value.unicode.str);
                return TCL_ERROR;
            }
            break;
        }
    } 

    if (result.type == TRT_BADFUNCTIONCODE) {
        /* Either raw format wanted or binary data */

        /*        
         * The following are handled via defaults for now
         *  CERT_DESCRIPTION_PROP_ID: // TBD - is this unicode?
         *  CERT_HASH_PROP_ID:
         *  CERT_ISSUER_PUBLIC_KEY_MD5_HASH_PROP_ID:
         *  CERT_ISSUER_SERIAL_NUMBER_MD5_HASH_PROP_ID:
         *  CERT_ARCHIVED_KEY_HASH_PROP_ID:
         *  CERT_KEY_IDENTIFIER_PROP_ID:
         *  CERT_KEY_PROV_INFO_PROP_ID
         *  CERT_MD5_HASH_PROP_ID
         *  CERT_RENEWAL_PROP_ID
         *  CERT_SHA1_HASH_PROP_ID
         *  CERT_SIGNATURE_HASH_PROP_ID
         *  CERT_SUBJECT_PUBLIC_KEY_MD5_HASH_PROP_ID
         *  CERT_REQUEST_ORIGINATOR_PROP_ID:
         */

        if (! CertGetCertificateContextProperty(certP, prop_id, NULL, &n))
            return TwapiReturnSystemError(interp);
        result.type = TRT_OBJ;
        result.value.obj = ObjFromByteArray(NULL, n);
        if (! CertGetCertificateContextProperty(
                certP, prop_id,
                ObjToByteArray(result.value.obj, &n),
                &n)) {
            TwapiReturnSystemError(interp);
            Tcl_DecrRefCount(result.value.obj);
            return TCL_ERROR;
        }
        Tcl_SetByteArrayLength(result.value.obj, n);
    }

    return TwapiSetResult(interp, &result);
}

static TCL_RESULT Twapi_SetCertContextKeyProvInfo(Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    PCCERT_CONTEXT certP;
    CRYPT_KEY_PROV_INFO ckpi;
    Tcl_Obj **objs;
    int       nobjs;
    TCL_RESULT status;
    Tcl_Obj *connameObj, *provnameObj;

    /* Note - objc/objv have initial command name arg removed by caller */
    if ((status = TwapiGetArgs(interp, objc, objv,
                               GETVERIFIEDPTR(certP, CERT_CONTEXT*, CertFreeCertificateContext),
                               ARGSKIP, ARGEND)) != TCL_OK)
        return status;

    if ((status = ObjGetElements(interp, objv[1], &nobjs, &objs)) != TCL_OK)
        return status;

    /* As always, extract WSTR AFTER other args to avoid shimmering */
    if ((status = TwapiGetArgs(interp, nobjs, objs,
                               GETOBJ(connameObj),
                               GETOBJ(provnameObj),
                               GETINT(ckpi.dwProvType),
                               GETINT(ckpi.dwFlags),
                               ARGSKIP, // cProvParam+rgProvParam
                               GETINT(ckpi.dwKeySpec),
                               ARGEND)) != TCL_OK)
        return status;

    ckpi.cProvParam = 0;
    ckpi.rgProvParam = NULL;

    ckpi.pwszContainerName = ObjToUnicode(connameObj);
    ckpi.pwszProvName = ObjToUnicode(provnameObj);
    if (CertSetCertificateContextProperty(certP, CERT_KEY_PROV_INFO_PROP_ID,
                                          0, &ckpi))
        return TCL_OK;
    else
        return TwapiReturnSystemError(interp);
}

static TCL_RESULT TwapiCertGetNameString(
    Tcl_Interp *interp,
    PCCERT_CONTEXT certP,
    DWORD type,
    DWORD flags,
    Tcl_Obj *owhat)
{
    void *pv;
    DWORD dw, nchars;
    WCHAR buf[1024];

    switch (type) {
    case CERT_NAME_EMAIL_TYPE: // 1
    case CERT_NAME_SIMPLE_DISPLAY_TYPE: // 4
    case CERT_NAME_FRIENDLY_DISPLAY_TYPE: // 5
    case CERT_NAME_DNS_TYPE: // 6
    case CERT_NAME_URL_TYPE: // 7
    case CERT_NAME_UPN_TYPE: // 8
        pv = NULL;
        break;
    case CERT_NAME_RDN_TYPE: // 2
        if (ObjToInt(interp, owhat, &dw) != TCL_OK)
            return TCL_ERROR;
        pv = &dw;
        break;
    case CERT_NAME_ATTR_TYPE: // 3
        pv = ObjToString(owhat);
        break;
    default:
        Tcl_SetObjResult(interp, Tcl_ObjPrintf("CertGetNameString: unknown type %d", type));
        return TCL_ERROR;
    }

    // 1 -> CERT_NAME_ISSUER_FLAG 
    // 0x00010000 -> CERT_NAME_DISABLE_IE4_UTF8_FLAG 
    // are supported.
    // 2 -> CERT_NAME_SEARCH_ALL_NAMES_FLAG
    // 0x00200000 -> CERT_NAME_STR_ENABLE_PUNYCODE_FLAG 
    // are post Win8 AND they will change output encoding/format
    // Only support what we know
    if (flags & ~(0x00010001)) {
        Tcl_SetObjResult(interp, Tcl_ObjPrintf("CertGetNameString: unsupported flags %d", flags));
        return TCL_ERROR;
    }

    nchars = CertGetNameStringW(certP, type, flags, pv, buf, ARRAYSIZE(buf));
    /* Note nchars includes terminating NULL */
    if (nchars > 1) {
        if (nchars < ARRAYSIZE(buf)) {
            Tcl_SetObjResult(interp, ObjFromUnicodeN(buf, nchars-1));
        } else {
            /* Buffer might have been truncated. Explicitly get buffer size */
            WCHAR *bufP;
            nchars = CertGetNameStringW(certP, type, flags, pv, NULL, 0);
            bufP = TwapiAlloc(nchars*sizeof(WCHAR));
            nchars = CertGetNameStringW(certP, type, flags, pv, bufP, nchars);
            Tcl_SetObjResult(interp, ObjFromUnicodeN(bufP, nchars-1));
            TwapiFree(bufP);
        }
    }
    return TCL_OK;
}

static TCL_RESULT Twapi_CryptSetProvParam(Tcl_Interp *interp,
                                          HCRYPTPROV hprov, DWORD param,
                                          DWORD flags, Tcl_Obj *objP)
{
    TCL_RESULT res;
    void *pv;
    HWND hwnd;
    SECURITY_DESCRIPTOR *secdP;

    switch (param) {
    case PP_CLIENT_HWND:
        if ((res = ObjToHWND(interp, objP, &hwnd)) != TCL_OK)
            return res;
        pv = &hwnd;
        break;
    case PP_DELETEKEY:
        pv = NULL;
        break;
    case PP_KEYEXCHANGE_PIN: /* FALLTHRU */
    case PP_SIGNATURE_PIN:
        pv = ObjToString(objP);
        break;
    case PP_KEYSET_SEC_DESCR:
        if ((res = ObjToPSECURITY_DESCRIPTOR(interp, objP, &secdP)) != TCL_OK)
            return res;
        /* TBD - check what happens with NULL secdP (which is valid) */
        pv = secdP;
        break;
#ifdef PP_PIN_PROMPT_STRING
    case PP_PIN_PROMPT_STRING:
#else
    case 44:
#endif
        /* FALLTHRU */
    case PP_UI_PROMPT:
        pv = ObjToUnicode(objP);
        break;
    default:
        return TwapiReturnErrorEx(interp, TWAPI_INVALID_ARGS, Tcl_ObjPrintf("Provider parameter %d not implemented", param));
    }

    if (CryptSetProvParam(hprov, param, pv, flags)) {
        res = TCL_OK;
    } else {
        res = TwapiReturnSystemError(interp);
    }

    TwapiFreeSECURITY_DESCRIPTOR(secdP); /* OK if NULL */
    
    return res;
}


static TCL_RESULT Twapi_CryptGetProvParam(Tcl_Interp *interp,
                                          HCRYPTPROV hprov,
                                          DWORD param, DWORD flags)
{
    Tcl_Obj *objP;
    DWORD n;
    void *pv;

    n = 0;
    /* Special case PP_ENUMCONTAINERS because of how the iteration
       works. We return ALL containers as opposed to one at a time */
    if (param == PP_ENUMCONTAINERS) {
        if (! CryptGetProvParam(hprov, param, NULL, &n, CRYPT_FIRST))
            return TwapiReturnSystemError(interp);
        /* n is now the max size buffer. Subsequent calls will not change that value */
        pv = TwapiAlloc(n * sizeof(char));
        objP = Tcl_NewListObj(0, NULL);
        flags = CRYPT_FIRST;
        while (CryptGetProvParam(hprov, param, pv, &n, flags)) {
            ObjAppendElement(NULL, objP, ObjFromString(pv));
            flags = CRYPT_NEXT;
        }
        n = GetLastError();
        TwapiFree(pv);
        if (n != ERROR_NO_MORE_ITEMS) {
            Tcl_DecrRefCount(objP);
            return Twapi_AppendSystemError(interp, n);
        }
        Tcl_SetObjResult(interp, objP);
        return TCL_OK;
    }
    
    if (! CryptGetProvParam(hprov, param, NULL, &n, flags))
        return TwapiReturnSystemError(interp);
    
    if (param == PP_KEYSET_SEC_DESCR) {
        objP = NULL;
        pv = TwapiAlloc(n);
    } else {
        objP = ObjFromByteArray(NULL, n);
        pv = ObjToByteArray(objP, &n);
    }

    if (! CryptGetProvParam(hprov, param, pv, &n, flags)) {
        if (objP)
            Tcl_DecrRefCount(objP);
        TwapiReturnSystemError(interp);
        return TCL_ERROR;
    }

    if (param == PP_KEYSET_SEC_DESCR) {
        if (n == 0)
            objP = ObjFromEmptyString();
        else
            objP = ObjFromSECURITY_DESCRIPTOR(interp, pv);
        TwapiFree(pv);
        if (objP == NULL)
            return TCL_ERROR;   /* interp already contains error */
    } else
        Tcl_SetByteArrayLength(objP, n);

    Tcl_SetObjResult(interp, objP);
    return TCL_OK;
}

static int Twapi_CertOpenStore(Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    DWORD store_provider, enc_type, flags;
    void *pv = NULL;
    HCERTSTORE hstore;
    HANDLE h;
    TCL_RESULT res;

    if (TwapiGetArgs(interp, objc, objv,
                     GETINT(store_provider), GETINT(enc_type), ARGUNUSED,
                     GETINT(flags), ARGSKIP, ARGEND) != TCL_OK)
        return TCL_ERROR;
    
    /* Using literals because the #defines are cast as LPCSTR */
    switch (store_provider) {
    case 2: // CERT_STORE_PROV_MEMORY
    case 11: // CERT_STORE_PROV_COLLECTION
        break;

    case 3: // CERT_STORE_PROV_FILE
        if ((res = ObjToOpaque(interp, objv[4], &h, "HANDLE")) != TCL_OK)
            return res;
        pv = &h;
        break;

    case 4: // CERT_STORE_PROV_REG
        /* Docs imply pv itself is the handle unlike the FILE case above */
        if ((res = ObjToOpaque(interp, objv[4], &pv, "HANDLE")) != TCL_OK)
            return res;
        break;

    case 8: // CERT_STORE_PROV_FILENAME_W
    case 14: // CERT_STORE_PROV_PHYSICAL_W
    case 10: // CERT_STORE_PROV_SYSTEM_W
    case 13: // CERT_STORE_PROV_SYSTEM_REGISTRY_W
        pv = ObjToUnicode(objv[4]);
        break;

    case 5: // CERT_STORE_PROV_PKCS7
    case 6: // CERT_STORE_PROV_SERIALIZED
    case 15: // CERT_STORE_PROV_SMART_CARD
    case 16: // CERT_STORE_PROV_LDAP
    case 1: // CERT_STORE_PROV_MSG
    default:
        Tcl_SetObjResult(interp,
                         Tcl_ObjPrintf("Invalid or unsupported store provider \"%d\"", store_provider));
        return TCL_ERROR;
    }

    hstore = CertOpenStore(IntToPtr(store_provider), enc_type, 0, flags, pv);
    if (hstore) {
        /* CertCloseStore does not check ponter validity! So do ourselves*/
        if (TwapiRegisterPointer(interp, h, CertCloseStore) != TCL_OK)
            Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
        Tcl_SetObjResult(interp, ObjFromOpaque(hstore, "HCERTSTORE"));
        return TCL_OK;
    } else {
        if (flags & CERT_STORE_DELETE_FLAG) {
            /* Return value can mean success as well */
            if (GetLastError() == 0)
                return TCL_OK;
        }
        return TwapiReturnSystemError(interp);
    }
}

static TCL_RESULT Twapi_PFXExportCertStoreEx(Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    HCERTSTORE hstore;
    LPWSTR password;
    int password_len;
    Tcl_Obj *objP;
    CRYPT_DATA_BLOB blob;
    BOOL status;
    int flags;
    
    if (TwapiGetArgs(interp, objc, objv,
                     GETVERIFIEDPTR(hstore, HCERTSTORE, CertCloseStore),
                     ARGSKIP, ARGUNUSED, 
                     GETINT(flags), ARGEND) != TCL_OK)
        return TCL_ERROR;
    
    if (ObjDecrypt(interp, objv[1], &objP) != TCL_OK)
        return TCL_ERROR;
    password = ObjToUnicodeN(objP, &password_len);
    
    blob.cbData = 0;
    blob.pbData = NULL;

    status = PFXExportCertStoreEx(hstore, &blob, password, NULL, flags);
    
    TWAPI_ASSERT(! Tcl_IsShared(objP));
    SecureZeroMemory(password, sizeof(WCHAR) * password_len);
    Tcl_DecrRefCount(objP);
    objP = NULL;
    password = NULL;            /* Since this pointed into objP */

    if (!status)
        return TwapiReturnSystemError(interp);

    if (blob.cbData == 0)
        return TCL_OK;        /* Nothing to export ? */

    objP = ObjFromByteArray(NULL, blob.cbData);
    blob.pbData = ObjToByteArray(objP, &blob.cbData);
    status = PFXExportCertStoreEx(hstore, &blob, password, NULL, flags);
    if (! status) {
        TwapiReturnSystemError(interp);
        Tcl_DecrRefCount(objP);
        return TCL_ERROR;
    }
    Tcl_SetObjResult(interp, objP);
    return TCL_OK;
}


static int Twapi_CryptoCallObjCmd(ClientData clientdata, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    TwapiResult result;
    DWORD dw, dw2, dw3;
    DWORD_PTR dwp;
    LPVOID pv;
    LPWSTR s1;
    LPSTR  cP;
    struct _CRYPTOAPI_BLOB blob;
    PCCERT_CONTEXT certP;
    void *bufP;
    DWORD buf_sz;
    Tcl_Obj *s1Obj, *s2Obj;
    int func = PtrToInt(clientdata);

    --objc;
    ++objv;

    TWAPI_ASSERT(sizeof(HCRYPTPROV) <= sizeof(pv));
    TWAPI_ASSERT(sizeof(HCRYPTKEY) <= sizeof(pv));
    TWAPI_ASSERT(sizeof(dwp) <= sizeof(void*));

    result.type = TRT_BADFUNCTIONCODE;
    switch (func) {
    case 10000: // CryptAcquireContext
        if (TwapiGetArgs(interp, objc, objv,
                         GETOBJ(s1Obj), GETOBJ(s2Obj), GETINT(dw), GETINT(dw2),
                         ARGEND) != TCL_OK)
            return TCL_ERROR;
        if (CryptAcquireContextW(&dwp,
                                 ObjToLPWSTR_NULL_IF_EMPTY(s1Obj),
                                 ObjToLPWSTR_NULL_IF_EMPTY(s2Obj),
                                 dw, dw2)) {
            if (dw2 & CRYPT_DELETEKEYSET)
                result.type = TRT_EMPTY;
            else {
                TwapiResult_SET_PTR(result, HCRYPTPROV, (void*)dwp);
            }
        } else {
            result.type = TRT_GETLASTERROR;
        }
        break;

    case 10001: // CryptReleaseContext
        if (TwapiGetArgs(interp, objc, objv,
                         GETHANDLET(pv, HCRYPTPROV),
                         ARGUSEDEFAULT, GETINT(dw), ARGEND) != TCL_OK)
            return TCL_ERROR;
        result.value.ival = CryptReleaseContext((HCRYPTPROV)pv, dw);
        result.type = TRT_EXCEPTION_ON_FALSE;
        break;

    case 10002: // CryptGetProvParam
        if (TwapiGetArgs(interp, objc, objv,
                         GETHANDLET(pv, HCRYPTPROV),
                         GETINT(dw), GETINT(dw2), ARGEND) != TCL_OK)
            return TCL_ERROR;
        return Twapi_CryptGetProvParam(interp, (HCRYPTPROV) pv, dw, dw2);

    case 10003: // CertOpenSystemStore
        if (objc != 1)
            return TwapiReturnError(interp, TWAPI_BAD_ARG_COUNT);
        pv = CertOpenSystemStoreW(0, ObjToUnicode(objv[0]));
        /* CertCloseStore does not check ponter validity! So do ourselves*/
        if (TwapiRegisterPointer(interp, pv, CertCloseStore) != TCL_OK)
            Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
        TwapiResult_SET_NONNULL_PTR(result, HCERTSTORE, pv);
        break;

    case 10004: // CertDeleteCertificateFromStore
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(certP, CERT_CONTEXT*, CertFreeCertificateContext), ARGEND) != TCL_OK)
            return TCL_ERROR;
        /* Unregister previous context since the next call will free it,
           EVEN ON FAILURES */
        if (TwapiUnregisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
            return TCL_ERROR;
        result.type = TRT_EXCEPTION_ON_FALSE;
        result.value.ival = CertDeleteCertificateFromStore(certP);
        break;

    case 10005: // Twapi_SetCertContextKeyProvInfo
        return Twapi_SetCertContextKeyProvInfo(interp, objc, objv);

    case 10006: // CertEnumCertificatesInStore
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(pv, HCERTSTORE, CertCloseStore),
                         GETPTR(certP, CERT_CONTEXT*), ARGEND) != TCL_OK)
            return TCL_ERROR;
        /* Unregister previous context since the next call will free it */
        if (certP &&
            TwapiUnregisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
            return TCL_ERROR;
        certP = CertEnumCertificatesInStore(pv, certP);
        if (certP) {
            if (TwapiRegisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
                Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
            TwapiResult_SET_NONNULL_PTR(result, CERT_CONTEXT*, (void*)certP);
        } else {
            result.value.ival = GetLastError();
            if (result.value.ival == CRYPT_E_NOT_FOUND ||
                result.value.ival == ERROR_NO_MORE_FILES)
                result.type = TRT_EMPTY;
            else
                result.type = TRT_GETLASTERROR;
        }
        break;
    case 10007: // CertEnumCertificateContextProperties
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(certP, CERT_CONTEXT*, CertFreeCertificateContext),
                         GETINT(dw), ARGEND) != TCL_OK)
            return TCL_ERROR;
        result.type = TRT_DWORD;
        result.value.ival = CertEnumCertificateContextProperties(certP, dw);
        break;

    case 10008: // CertGetCertificateContextProperty
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(certP, CERT_CONTEXT*, CertFreeCertificateContext),
                         GETINT(dw), ARGUSEDEFAULT, GETINT(dw2), ARGEND) != TCL_OK)
            return TCL_ERROR;
        return Twapi_CertGetCertificateContextProperty(interp, certP, dw, dw2);

    case 10009: // CryptDestroyKey
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(pv, HCRYPTKEY, CryptDestroyKey),
                         ARGEND) != TCL_OK)
            return TCL_ERROR;
        result.type = TRT_EXCEPTION_ON_FALSE;
        result.value.ival = CryptDestroyKey((HCRYPTKEY) pv);
        break;
            
    case 10010: // CryptGenKey
        if (TwapiGetArgs(interp, objc, objv,
                         GETHANDLET(pv, HCRYPTPROV),
                         GETINT(dw), GETINT(dw2), ARGEND) != TCL_OK)
            return TCL_ERROR;
        if (CryptGenKey((HCRYPTPROV) pv, dw, dw2, &dwp)) {
            if (TwapiRegisterPointer(interp, (void*)dwp, CryptDestroyKey) != TCL_OK)
                Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
            TwapiResult_SET_PTR(result, HCRYPTKEY, (void*)dwp);
        } else
            result.type = TRT_GETLASTERROR;
        break;

    case 10011: // CertStrToName
        if (TwapiGetArgs(interp, objc, objv, GETOBJ(s1Obj), ARGUSEDEFAULT,
                         GETINT(dw), ARGEND) != TCL_OK)
            return TCL_ERROR;
        result.type = TRT_GETLASTERROR;
        dw2 = 0;
        s1 = ObjToUnicode(s1Obj); /* Do AFTER extracting other args above */
        if (CertStrToNameW(X509_ASN_ENCODING, s1,
                           dw, NULL, NULL, &dw2, NULL)) {
            result.value.obj = ObjFromByteArray(NULL, dw2);
            if (CertStrToNameW(X509_ASN_ENCODING, s1, dw, NULL,
                               ObjToByteArray(result.value.obj, &dw2),
                               &dw2, NULL)) {
                Tcl_SetByteArrayLength(result.value.obj, dw2);
                result.type = TRT_OBJ;
            } else {
                Tcl_DecrRefCount(result.value.obj);
            }
        }
        break;

    case 10012: // CertNameToStr
        if (TwapiGetArgs(interp, objc, objv, ARGSKIP, GETINT(dw), ARGEND)
            != TCL_OK)
            return TCL_ERROR;
        blob.pbData = ObjToByteArray(objv[0], &blob.cbData);
        dw2 = CertNameToStrW(X509_ASN_ENCODING, &blob, dw, NULL, 0);
        result.value.unicode.str = TwapiAlloc(dw2*sizeof(WCHAR));
        result.value.unicode.len = CertNameToStrW(X509_ASN_ENCODING, &blob, dw, result.value.unicode.str, dw2) - 1;
        result.type = TRT_UNICODE_DYNAMIC;
        break;

    case 10013: // CertGetNameString
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(certP, CERT_CONTEXT*, CertFreeCertificateContext),
                         GETINT(dw), GETINT(dw2), ARGSKIP, ARGEND) != TCL_OK)
            return TCL_ERROR;
            
        return TwapiCertGetNameString(interp, certP, dw, dw2, objv[3]);

    case 10014: // CertFreeCertificateContext
        /* TBD -
           CertDuplicateCertificateContext will return the same pointer!
           However, our registration will barf when trying to release
           it the second time. Perhaps if the Cert API deals with bad
           pointer values, do not register it ourselves. Or do not
           implement the CertDuplicateCertificateContext call */
        if (TwapiGetArgs(interp, objc, objv,
                         GETPTR(certP, CERT_CONTEXT*), ARGEND) != TCL_OK ||
            TwapiUnregisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
            return TCL_ERROR;
        TWAPI_ASSERT(certP);
        result.type = TRT_EMPTY;
        CertFreeCertificateContext(certP);
        break;

    case 10015: // TwapiFindCertBySubjectName
        /* Supports tiny subset of CertFindCertificateInStore */
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(pv, HCERTSTORE, CertCloseStore),
                         GETOBJ(s1Obj), GETPTR(certP, CERT_CONTEXT*),
                         ARGEND) != TCL_OK)
            return TCL_ERROR;
        /* Unregister previous context since the next call will free it */
        if (certP &&
            TwapiUnregisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
            return TCL_ERROR;
        certP = CertFindCertificateInStore(
            pv,
            X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
            0,
            CERT_FIND_SUBJECT_STR_W,
            ObjToUnicode(s1Obj),
            certP);
        if (certP) {
            if (TwapiRegisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
                Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
            TwapiResult_SET_NONNULL_PTR(result, CERT_CONTEXT*, (void*)certP);
        } else {
            result.type = GetLastError() == CRYPT_E_NOT_FOUND ? TRT_EMPTY : TRT_GETLASTERROR;
        }
        break;
            
    case 10016: // CertUnregisterSystemStore
        /* This command is there to primarily clean up mistakes in testing */
        if (TwapiGetArgs(interp, objc, objv,
                         GETOBJ(s1Obj), GETINT(dw), ARGEND) != TCL_OK)
            return TCL_ERROR;
        result.type = TRT_EXCEPTION_ON_FALSE;
        result.value.ival = CertUnregisterSystemStore(ObjToUnicode(s1Obj), dw);
        break;
    case 10017:
        if (TwapiGetArgs(interp, objc, objv,
                         GETHANDLET(pv, HCERTSTORE), ARGUSEDEFAULT,
                         GETINT(dw), ARGEND) != TCL_OK ||
            TwapiUnregisterPointer(interp, pv, CertCloseStore) != TCL_OK)
            return TCL_ERROR;

        result.type = TRT_BOOL;
        result.value.bval = CertCloseStore(pv, dw);
        if (result.value.bval == FALSE) {
            if (GetLastError() != CRYPT_E_PENDING_CLOSE)
                result.type = TRT_GETLASTERROR;
        }
        break;

    case 10018: // CryptGetUserKey
        if (TwapiGetArgs(interp, objc, objv,
                         GETHANDLET(pv, HCRYPTPROV),
                         GETINT(dw), ARGEND) != TCL_OK)
            return TCL_ERROR;
        if (CryptGetUserKey((HCRYPTPROV) pv, dw, &dwp)) {
            if (TwapiRegisterPointer(interp, (void*)dwp, CryptDestroyKey) != TCL_OK)
                Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
            TwapiResult_SET_PTR(result, HCRYPTKEY, (void*)dwp);
        } else
            result.type = TRT_GETLASTERROR;
        break;

    case 10019: // CryptSetProvParam
        if (TwapiGetArgs(interp, objc, objv,
                         GETHANDLET(pv, HCRYPTPROV),
                         GETINT(dw), GETINT(dw2), ARGSKIP, ARGEND) != TCL_OK)
            return TCL_ERROR;
        return Twapi_CryptSetProvParam(interp, (HCRYPTPROV) pv, dw, dw2, objv[3]);

    case 10020: // CertOpenStore
        return Twapi_CertOpenStore(interp, objc, objv);

    case 10021: // PFXExportCertStoreEx
        return Twapi_PFXExportCertStoreEx(interp, objc, objv);

    case 10022: // CertAddCertificateContextToStore
        if (TwapiGetArgs(interp, objc, objv,
                         GETVERIFIEDPTR(pv, HCERTSTORE, CertCloseStore),
                         GETVERIFIEDPTR(certP, CERT_CONTEXT*, CertFreeCertificateContext),
                         GETINT(dw), ARGEND) != TCL_OK)
            return TCL_ERROR;
        if (!CertAddCertificateContextToStore(pv, certP, dw, &certP))
            result.type = TRT_GETLASTERROR;
        else {
            if (TwapiRegisterPointer(interp, certP, CertFreeCertificateContext) != TCL_OK)
                Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
            TwapiResult_SET_NONNULL_PTR(result, CERT_CONTEXT*, (void*)certP);
        }
        break;

    case 10023:  // CryptExportPublicKeyInfoEx
        if (TwapiGetArgs(interp, objc, objv,
                         GETHANDLET(pv, HCRYPTPROV),
                         GETINT(dw), // keyspec
                         GETINT(dw2), // enctype
                         GETASTR(cP), // publickeyobjid
                         GETINT(dw3), // flags
                         ARGEND) != TCL_OK)
            return TCL_ERROR;
        buf_sz = 0;
        if (!CryptExportPublicKeyInfoEx((HCRYPTPROV)pv, dw, dw2, cP, dw3, NULL, NULL, &buf_sz)) {
            result.type = TRT_GETLASTERROR;
            break;
        }
        bufP = TwapiAlloc(buf_sz);
        if (!CryptExportPublicKeyInfoEx((HCRYPTPROV)pv, dw, dw2, cP, dw3, NULL, bufP, &buf_sz)) {
            TwapiReturnSystemError(interp);
            TwapiFree(bufP);
            return TCL_ERROR;
        }
        if (TwapiRegisterPointer(interp, bufP, TwapiAlloc) != TCL_OK)
            Tcl_Panic("Failed to register pointer: %s", Tcl_GetStringResult(interp));
        TwapiResult_SET_NONNULL_PTR(result, CERT_PUBLIC_KEY_INFO*, bufP);
        break;
    }

    return TwapiSetResult(interp, &result);
}




static int TwapiCryptoInitCalls(Tcl_Interp *interp, TwapiInterpContext *ticP)
{
    static struct fncode_dispatch_s CryptoDispatch[] = {
        DEFINE_FNCODE_CMD(CryptAcquireContext, 10000),
        DEFINE_FNCODE_CMD(crypt_release_context, 10001),
        DEFINE_FNCODE_CMD(CryptGetProvParam, 10002),
        DEFINE_FNCODE_CMD(CertOpenSystemStore, 10003),
        DEFINE_FNCODE_CMD(cert_delete_from_store, 10004), // Doc TBD
        DEFINE_FNCODE_CMD(Twapi_SetCertContextKeyProvInfo, 10005),
        DEFINE_FNCODE_CMD(CertEnumCertificatesInStore, 10006),
        DEFINE_FNCODE_CMD(CertEnumCertificateContextProperties, 10007),
        DEFINE_FNCODE_CMD(CertGetCertificateContextProperty, 10008),
        DEFINE_FNCODE_CMD(crypt_destroy_key, 10009), // Doc TBD
        DEFINE_FNCODE_CMD(CryptGenKey, 10010),
        DEFINE_FNCODE_CMD(CertStrToName, 10011),
        DEFINE_FNCODE_CMD(CertNameToStr, 10012),
        DEFINE_FNCODE_CMD(CertGetNameString, 10013),
        DEFINE_FNCODE_CMD(cert_free, 10014), //CertFreeCertificateContext - doc
        DEFINE_FNCODE_CMD(TwapiFindCertBySubjectName, 10015),
        DEFINE_FNCODE_CMD(CertUnregisterSystemStore, 10016),
        DEFINE_FNCODE_CMD(CertCloseStore, 10017),
        DEFINE_FNCODE_CMD(CryptGetUserKey, 10018),
        DEFINE_FNCODE_CMD(CryptSetProvParam, 10019),
        DEFINE_FNCODE_CMD(CertOpenStore, 10020),
        DEFINE_FNCODE_CMD(PFXExportCertStoreEx, 10021),
        DEFINE_FNCODE_CMD(CertAddCertificateContextToStore, 10022),
        DEFINE_FNCODE_CMD(CryptExportPublicKeyInfoEx, 10023),
    };

    TwapiDefineFncodeCmds(interp, ARRAYSIZE(CryptoDispatch), CryptoDispatch, Twapi_CryptoCallObjCmd);
    Tcl_CreateObjCommand(interp, "twapi::CertCreateSelfSignCertificate", Twapi_CertCreateSelfSignCertificate, ticP, NULL);

    return TwapiSspiInitCalls(interp, ticP);
}


#ifndef TWAPI_SINGLE_MODULE
BOOL WINAPI DllMain(HINSTANCE hmod, DWORD reason, PVOID unused)
{
    if (reason == DLL_PROCESS_ATTACH)
        gModuleHandle = hmod;
    return TRUE;
}
#endif

/* Main entry point */
#ifndef TWAPI_SINGLE_MODULE
__declspec(dllexport) 
#endif
int Twapi_crypto_Init(Tcl_Interp *interp)
{
    static TwapiModuleDef gModuleDef = {
        MODULENAME,
        TwapiCryptoInitCalls,
        NULL
    };

    /* IMPORTANT */
    /* MUST BE FIRST CALL as it initializes Tcl stubs */
    if (Tcl_InitStubs(interp, TCL_VERSION, 0) == NULL) {
        return TCL_ERROR;
    }

    return TwapiRegisterModule(interp, MODULE_HANDLE, &gModuleDef, DEFAULT_TIC) ? TCL_OK : TCL_ERROR;
}

