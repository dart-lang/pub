// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by `package:ffigen`.
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkg_ffi;

class NativeLibrary {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  NativeLibrary(ffi.DynamicLibrary dynamicLibrary)
      : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  NativeLibrary.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
          lookup)
      : _lookup = lookup;

  ffi.Pointer<pkg_ffi.Utf8> gpgme_strerror(
    int err,
  ) {
    return _gpgme_strerror(
      err,
    );
  }

  late final _gpgme_strerrorPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<pkg_ffi.Utf8> Function(gpgme_error_t)>>('gpgme_strerror');
  late final _gpgme_strerror =
      _gpgme_strerrorPtr.asFunction<ffi.Pointer<pkg_ffi.Utf8> Function(int)>();

  ffi.Pointer<pkg_ffi.Utf8> gpgme_strsource(
    int err,
  ) {
    return _gpgme_strsource(
      err,
    );
  }

  late final _gpgme_strsourcePtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<pkg_ffi.Utf8> Function(
              gpgme_error_t)>>('gpgme_strsource');
  late final _gpgme_strsource =
      _gpgme_strsourcePtr.asFunction<ffi.Pointer<pkg_ffi.Utf8> Function(int)>();

  ffi.Pointer<pkg_ffi.Utf8> gpgme_check_version(
    ffi.Pointer<pkg_ffi.Utf8> req_version,
  ) {
    return _gpgme_check_version(
      req_version,
    );
  }

  late final _gpgme_check_versionPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<pkg_ffi.Utf8> Function(
              ffi.Pointer<pkg_ffi.Utf8>)>>('gpgme_check_version');
  late final _gpgme_check_version = _gpgme_check_versionPtr.asFunction<
      ffi.Pointer<pkg_ffi.Utf8> Function(ffi.Pointer<pkg_ffi.Utf8>)>();

  int gpgme_new(
    ffi.Pointer<gpgme_ctx_t> ctx,
  ) {
    return _gpgme_new(
      ctx,
    );
  }

  late final _gpgme_newPtr = _lookup<
          ffi.NativeFunction<gpgme_error_t Function(ffi.Pointer<gpgme_ctx_t>)>>(
      'gpgme_new');
  late final _gpgme_new =
      _gpgme_newPtr.asFunction<int Function(ffi.Pointer<gpgme_ctx_t>)>();

  void gpgme_release(
    gpgme_ctx_t ctx,
  ) {
    return _gpgme_release(
      ctx,
    );
  }

  late final _gpgme_releasePtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(gpgme_ctx_t)>>(
          'gpgme_release');
  late final _gpgme_release =
      _gpgme_releasePtr.asFunction<void Function(gpgme_ctx_t)>();

  int gpgme_data_new_from_mem(
    ffi.Pointer<gpgme_data_t> r_dh,
    ffi.Pointer<pkg_ffi.Utf8> buffer,
    int size,
    int copy,
  ) {
    return _gpgme_data_new_from_mem(
      r_dh,
      buffer,
      size,
      copy,
    );
  }

  late final _gpgme_data_new_from_memPtr = _lookup<
      ffi.NativeFunction<
          gpgme_error_t Function(
              ffi.Pointer<gpgme_data_t>,
              ffi.Pointer<pkg_ffi.Utf8>,
              ffi.Size,
              ffi.Int)>>('gpgme_data_new_from_mem');
  late final _gpgme_data_new_from_mem = _gpgme_data_new_from_memPtr.asFunction<
      int Function(
          ffi.Pointer<gpgme_data_t>, ffi.Pointer<pkg_ffi.Utf8>, int, int)>();

  int gpgme_data_new_from_file(
    ffi.Pointer<gpgme_data_t> r_dh,
    ffi.Pointer<pkg_ffi.Utf8> fname,
    int copy,
  ) {
    return _gpgme_data_new_from_file(
      r_dh,
      fname,
      copy,
    );
  }

  late final _gpgme_data_new_from_filePtr = _lookup<
      ffi.NativeFunction<
          gpgme_error_t Function(ffi.Pointer<gpgme_data_t>,
              ffi.Pointer<pkg_ffi.Utf8>, ffi.Int)>>('gpgme_data_new_from_file');
  late final _gpgme_data_new_from_file =
      _gpgme_data_new_from_filePtr.asFunction<
          int Function(
              ffi.Pointer<gpgme_data_t>, ffi.Pointer<pkg_ffi.Utf8>, int)>();

  void gpgme_data_release(
    gpgme_data_t dh,
  ) {
    return _gpgme_data_release(
      dh,
    );
  }

  late final _gpgme_data_releasePtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(gpgme_data_t)>>(
          'gpgme_data_release');
  late final _gpgme_data_release =
      _gpgme_data_releasePtr.asFunction<void Function(gpgme_data_t)>();

  int gpgme_op_verify(
    gpgme_ctx_t ctx,
    gpgme_data_t sig,
    gpgme_data_t signed_text,
    gpgme_data_t plaintext,
  ) {
    return _gpgme_op_verify(
      ctx,
      sig,
      signed_text,
      plaintext,
    );
  }

  late final _gpgme_op_verifyPtr = _lookup<
      ffi.NativeFunction<
          gpgme_error_t Function(gpgme_ctx_t, gpgme_data_t, gpgme_data_t,
              gpgme_data_t)>>('gpgme_op_verify');
  late final _gpgme_op_verify = _gpgme_op_verifyPtr.asFunction<
      int Function(gpgme_ctx_t, gpgme_data_t, gpgme_data_t, gpgme_data_t)>();

  gpgme_verify_result_t gpgme_op_verify_result(
    gpgme_ctx_t ctx,
  ) {
    return _gpgme_op_verify_result(
      ctx,
    );
  }

  late final _gpgme_op_verify_resultPtr =
      _lookup<ffi.NativeFunction<gpgme_verify_result_t Function(gpgme_ctx_t)>>(
          'gpgme_op_verify_result');
  late final _gpgme_op_verify_result = _gpgme_op_verify_resultPtr
      .asFunction<gpgme_verify_result_t Function(gpgme_ctx_t)>();

  late final addresses = _SymbolAddresses(this);
}

class _SymbolAddresses {
  final NativeLibrary _library;
  _SymbolAddresses(this._library);
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(gpgme_ctx_t)>>
      get gpgme_release => _library._gpgme_releasePtr;
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(gpgme_data_t)>>
      get gpgme_data_release => _library._gpgme_data_releasePtr;
}

class gpgme_context extends ffi.Opaque {}

class gpgme_data extends ffi.Opaque {}

typedef gpgme_error_t = ffi.Int;
typedef gpgme_ctx_t = ffi.Pointer<gpgme_context>;
typedef gpgme_data_t = ffi.Pointer<gpgme_data>;

abstract class gpgme_sigsum_t {
  static const int GPGME_SIGSUM_VALID = 1;
  static const int GPGME_SIGSUM_GREEN = 2;
  static const int GPGME_SIGSUM_RED = 4;
  static const int GPGME_SIGSUM_KEY_REVOKED = 16;
  static const int GPGME_SIGSUM_KEY_EXPIRED = 32;
  static const int GPGME_SIGSUM_SIG_EXPIRED = 64;
  static const int GPGME_SIGSUM_KEY_MISSING = 128;
  static const int GPGME_SIGSUM_CRL_MISSING = 256;
  static const int GPGME_SIGSUM_CRL_TOO_OLD = 512;
  static const int GPGME_SIGSUM_BAD_POLICY = 1024;
  static const int GPGME_SIGSUM_SYS_ERROR = 2048;
  static const int GPGME_SIGSUM_TOFU_CONFLICT = 4096;
}

abstract class gpgme_validity_t {
  static const int GPGME_VALIDITY_UNKNOWN = 0;
  static const int GPGME_VALIDITY_UNDEFINED = 1;
  static const int GPGME_VALIDITY_NEVER = 2;
  static const int GPGME_VALIDITY_MARGINAL = 3;
  static const int GPGME_VALIDITY_FULL = 4;
  static const int GPGME_VALIDITY_ULTIMATE = 5;
}

class gpgme_signature extends ffi.Struct {
  external ffi.Pointer<gpgme_signature> next;

  @ffi.Int32()
  external int summary;

  external ffi.Pointer<pkg_ffi.Utf8> fpr;

  @gpgme_error_t()
  external int status;

  external ffi.Pointer<ffi.Void> _ignored1;

  @ffi.UnsignedLong()
  external int timestamp;

  @ffi.UnsignedLong()
  external int exp_timestamp;

  @ffi.Int32()
  external int _ignored2;

  @ffi.Int32()
  external int validity;

  @gpgme_error_t()
  external int validity_reason;
}

class gpgme_op_verify_result_ extends ffi.Struct {
  external gpgme_signature_t signatures;

  external ffi.Pointer<pkg_ffi.Utf8> file_name;
}

typedef gpgme_signature_t = ffi.Pointer<gpgme_signature>;
typedef gpgme_verify_result_t = ffi.Pointer<gpgme_op_verify_result_>;
