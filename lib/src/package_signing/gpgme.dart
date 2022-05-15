import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'gpgme.g.dart';

class GpgmeBindings {
  final NativeLibrary _library;

  final NativeFinalizer _releaseContext;
  final NativeFinalizer _releaseData;

  final String version;

  GpgmeBindings._(
      this._library, this._releaseContext, this._releaseData, this.version);

  factory GpgmeBindings(DynamicLibrary library) {
    final natives = NativeLibrary(library);

    return GpgmeBindings._(
      natives,
      NativeFinalizer(natives.addresses.gpgme_release.cast()),
      NativeFinalizer(natives.addresses.gpgme_data_release.cast()),
      natives.gpgme_check_version(_nullptr()).cast<Utf8>().toDartString(),
    );
  }

  void _handleError(int resultCode) {
    if (resultCode != 0) {
      final msg = _library.gpgme_strerror(resultCode).toDartString();
      final source = _library.gpgme_strsource(resultCode).toDartString();
      throw GpgmeException(msg, source, resultCode);
    }
  }

  GpgmeContext newContext() {
    final ptr = malloc<gpgme_ctx_t>();
    try {
      _handleError(_library.gpgme_new(ptr));
      final context = GpgmeContext._(ptr.value, this);
      _releaseContext.attach(context, context._context.cast());

      return context;
    } finally {
      malloc.free(ptr);
    }
  }

  GpgmeData dataFromBytes(Uint8List source) {
    final ptr = malloc<gpgme_data_t>();
    final buffer = malloc.allocate<Uint8>(source.length);
    buffer.asTypedList(source.length).setAll(0, source);
    try {
      _handleError(_library.gpgme_data_new_from_mem(
          ptr, buffer.cast(), source.length, 1));
      final data = GpgmeData._(ptr.value);
      _releaseData.attach(data, data._data.cast());

      return data;
    } finally {
      malloc
        ..free(ptr)
        ..free(buffer);
    }
  }
}

class GpgmeContext implements Finalizable {
  final gpgme_ctx_t _context;
  final GpgmeBindings _bindings;

  GpgmeContext._(this._context, this._bindings);

  List<Signature> verifyDetached(GpgmeData plaintext, GpgmeData signature) {
    _bindings._handleError(_bindings._library.gpgme_op_verify(
        _context, signature._data, plaintext._data, _nullptr()));

    final result = _bindings._library.gpgme_op_verify_result(_context).ref;
    final signatures = <Signature>[];

    void addSignature(gpgme_signature_t signature) {
      if (signature.address == 0) return;

      final ref = signature.ref;
      final isValid = ref.summary & gpgme_sigsum_t.GPGME_SIGSUM_VALID ==
          gpgme_sigsum_t.GPGME_SIGSUM_VALID;
      final status =
          _bindings._library.gpgme_strerror(ref.status).toDartString();

      signatures.add(Signature._(isValid, status, ref.fpr.toDartString()));

      addSignature(ref.next);
    }

    addSignature(result.signatures);
    return signatures;
  }
}

class GpgmeData implements Finalizable {
  final gpgme_data_t _data;

  GpgmeData._(this._data);
}

class Signature {
  /// Whether this signature is fully valid, meaning that:
  ///
  /// - the key with the given [fingerprint] is available in the local key
  ///   chain.
  /// - the signature matches the actual contents of the checked file.
  final bool isValid;

  /// The PGP fingerprint of the key used to sign the contents.
  final String fingerprint;

  /// A human-readable description of this signature's status.
  ///
  /// Pub will show this status as an explanation if [isValid] is `false`.
  final String status;

  Signature._(this.isValid, this.status, this.fingerprint);

  @override
  String toString() {
    return 'Signature($fingerprint), valid = $isValid, status = $status';
  }
}

class GpgmeException implements Exception {
  final String _message;
  final String _source;
  final int _errorCode;

  GpgmeException(this._message, this._source, this._errorCode);

  @override
  String toString() {
    return 'GpgmeException($_errorCode in $_source): $_message';
  }
}

Pointer<T> _nullptr<T extends NativeType>() => Pointer.fromAddress(0);
