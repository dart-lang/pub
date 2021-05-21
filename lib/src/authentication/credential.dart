import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'bearer.dart';

typedef CredentialDeserializer = Credential Function(Map<String, dynamic>);

final Map<String, CredentialDeserializer> _supportedMethods = {
  'Bearer': BearerCredential.fromMap,
};

abstract class Credential {
  static Credential? fromJson(Map<String, dynamic> map) {
    final authMethod = map['method'] as String?;
    final credentials = map['credentials'] as Map<String, dynamic>?;

    if (credentials != null &&
        authMethod?.isNotEmpty == true &&
        _supportedMethods.containsKey(authMethod)) {
      return _supportedMethods[authMethod]!(credentials);
    }

    return null;
  }

  /// Converts this instance into Json map.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'method': authenticationType,
      'credentials': toMapInternal(),
    };
  }

  /// Authentication type of this credential.
  @protected
  String get authenticationType;

  /// Add required details for authentication to [request].
  Future<void> beforeRequest(http.BaseRequest request);

  /// Converts credential data into [Map<String, dynamic>].
  @protected
  Map<String, dynamic> toMapInternal();
}
