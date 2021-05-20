import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'bearer.dart';

typedef CredentialDeserializer = Credential Function(Map<String, dynamic>);

final Map<String, CredentialDeserializer> _supportedMethods = {
  'Bearer': BearerCredential.fromMap,
};

abstract class Credential {
  static Credential? fromMap(Map<String, dynamic> map) {
    final authMethod = map['method'] as String?;
    final credentials = map['credentials'] as Map<String, dynamic>?;

    if (credentials != null &&
        authMethod?.isNotEmpty == true &&
        _supportedMethods.containsKey(authMethod)) {
      return _supportedMethods[authMethod]!(credentials);
    }

    return null;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'method': authenticationType,
      'credentials': toMapInternal(),
    };
  }

  /// Authentication type of this credential.
  String get authenticationType;

  /// Creates authenticated client using this credential.
  Future<http.BaseClient> createClient();

  /// Converts credential data into [Map<String, dynamic>].
  @protected
  Map<String, dynamic> toMapInternal();
}
