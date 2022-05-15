/* gpgme.h - Public interface to GnuPG Made Easy.                   -*- c -*-
 * Copyright (C) 2000 Werner Koch (dd9jn)
 * Copyright (C) 2001-2018 g10 Code GmbH
 *
 * This file is part of GPGME.
 *
 * GPGME is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of
 * the License, or (at your option) any later version.
 *
 * GPGME is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; if not, see <https://gnu.org/licenses/>.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 *
 * Generated from gpgme.h.in for @GPGME_CONFIG_HOST@.
 */

#include <stddef.h>
#include <stdint.h>

typedef int gpgme_error_t;

/* The context holds some global state and configuration options, as
 * well as the results of a crypto operation.  */
struct gpgme_context;
typedef struct gpgme_context *gpgme_ctx_t;

/* The data object is used by GPGME to exchange arbitrary data.  */
struct gpgme_data;
typedef struct gpgme_data *gpgme_data_t;

/* Return a pointer to a string containing a description of the error
 * code in the error value ERR.  This function is not thread safe.  */
const char *gpgme_strerror (gpgme_error_t err);

/* Return a pointer to a string containing a description of the error
 * source in the error value ERR.  */
const char *gpgme_strsource (gpgme_error_t err);

/* Check that the library fulfills the version requirement.  Note:
 * This is here only for the case where a user takes a pointer from
 * the old version of this function.  The new version and macro for
 * run-time checks are below.  */
const char *gpgme_check_version (const char *req_version);

/* Create a new context and return it in CTX.  */
gpgme_error_t gpgme_new (gpgme_ctx_t *ctx);

/* Release the context CTX.  */
void gpgme_release (gpgme_ctx_t ctx);

/* Create a new data buffer filled with SIZE bytes starting from
 * BUFFER.  If COPY is zero, copying is delayed until necessary, and
 * the data is taken from the original location when needed.  */
gpgme_error_t gpgme_data_new_from_mem (gpgme_data_t *r_dh,
				       const char *buffer, size_t size,
				       int copy);

/* Create a new data buffer filled with the content of file FNAME.
 * COPY must be non-zero.  For delayed read, please use
 * gpgme_data_new_from_fd or gpgme_data_new_from_stream instead.  */
gpgme_error_t gpgme_data_new_from_file (gpgme_data_t *r_dh,
					const char *fname,
					int copy);

/* Destroy the data buffer DH.  */
void gpgme_data_release (gpgme_data_t dh);

gpgme_error_t gpgme_op_verify (gpgme_ctx_t ctx, gpgme_data_t sig,
			       gpgme_data_t signed_text,
			       gpgme_data_t plaintext);

/* Flags used for the SUMMARY field in a gpgme_signature_t.  */
typedef enum
  {
    GPGME_SIGSUM_VALID       = 0x0001,  /* The signature is fully valid.  */
    GPGME_SIGSUM_GREEN       = 0x0002,  /* The signature is good.  */
    GPGME_SIGSUM_RED         = 0x0004,  /* The signature is bad.  */
    GPGME_SIGSUM_KEY_REVOKED = 0x0010,  /* One key has been revoked.  */
    GPGME_SIGSUM_KEY_EXPIRED = 0x0020,  /* One key has expired.  */
    GPGME_SIGSUM_SIG_EXPIRED = 0x0040,  /* The signature has expired.  */
    GPGME_SIGSUM_KEY_MISSING = 0x0080,  /* Can't verify: key missing.  */
    GPGME_SIGSUM_CRL_MISSING = 0x0100,  /* CRL not available.  */
    GPGME_SIGSUM_CRL_TOO_OLD = 0x0200,  /* Available CRL is too old.  */
    GPGME_SIGSUM_BAD_POLICY  = 0x0400,  /* A policy was not met.  */
    GPGME_SIGSUM_SYS_ERROR   = 0x0800,  /* A system error occurred.  */
    GPGME_SIGSUM_TOFU_CONFLICT=0x1000   /* Tofu conflict detected.  */
  }
gpgme_sigsum_t;

/* The available validities for a key.  */
typedef enum
  {
    GPGME_VALIDITY_UNKNOWN   = 0,
    GPGME_VALIDITY_UNDEFINED = 1,
    GPGME_VALIDITY_NEVER     = 2,
    GPGME_VALIDITY_MARGINAL  = 3,
    GPGME_VALIDITY_FULL      = 4,
    GPGME_VALIDITY_ULTIMATE  = 5
  }
gpgme_validity_t;

/* An object to hold the verification status of a signature.
 * This structure shall be considered read-only and an application
 * must not allocate such a structure on its own.  */
struct gpgme_signature
{
  struct gpgme_signature *next;

  /* A summary of the signature status.  */
  gpgme_sigsum_t summary;

  /* The fingerprint of the signature.  This can be a subkey.  */
  char *fpr;

  /* The status of the signature.  */
  gpgme_error_t status;

  void* _ignored1; // notations

    /* Signature creation time.  */
  unsigned long timestamp;

  /* Signature expiration time or 0.  */
  unsigned long exp_timestamp;

  int32_t _ignored2; // wrong_key_usage, pka_trust, chain_model, is_de_vs, _unused

  gpgme_validity_t validity;
  gpgme_error_t validity_reason;
};
typedef struct gpgme_signature *gpgme_signature_t;

/* An object to return the results of a verify operation.
 * This structure shall be considered read-only and an application
 * must not allocate such a structure on its own.  */
struct gpgme_op_verify_result_
{
  gpgme_signature_t signatures;

  /* The original file name of the plaintext message, if available.
   * Warning: This information is not covered by the signature.  */
  char *file_name;
};
typedef struct gpgme_op_verify_result_ *gpgme_verify_result_t;

/* Retrieve a pointer to the result of the verify operation.  */
gpgme_verify_result_t gpgme_op_verify_result (gpgme_ctx_t ctx);
