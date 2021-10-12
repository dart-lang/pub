// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: prefer_single_quotes

// This code is copied from an older version of package:package_config - and
// kept here until we completely abandon the old .packages file.
// See: https://github.com/dart-lang/package_config/blob/04b9abec2627dfaf9b7ec39c31a3b03f06ed9be7/lib/packages_file.dart

/// Parses a `.packages` file into a map from package name to base URI.
///
/// The [source] is the byte content of a `.packages` file, assumed to be
/// UTF-8 encoded. In practice, all significant parts of the file must be ASCII,
/// so Latin-1 or Windows-1252 encoding will also work fine.
///
/// If the file content is available as a string, its [String.codeUnits] can
/// be used as the `source` argument of this function.
///
/// The [baseLocation] is used as a base URI to resolve all relative
/// URI references against.
/// If the content was read from a file, `baseLocation` should be the
/// location of that file.
///
/// If [allowDefaultPackage] is set to true, an entry with an empty package name
/// is accepted. This entry does not correspond to a package, but instead
/// represents a *default package* which non-package libraries may be considered
/// part of in some cases. The value of that entry must be a valid package name.
///
/// Returns a simple mapping from package name to package location.
/// If default package is allowed, the map maps the empty string to the default package's name.
Map<String, Uri> parse(List<int> source, Uri baseLocation,
    {bool allowDefaultPackage = false}) {
  var index = 0;
  var result = <String, Uri>{};
  while (index < source.length) {
    var isComment = false;
    var start = index;
    var separatorIndex = -1;
    var end = source.length;
    var char = source[index++];
    if (char == $cr || char == $lf) {
      continue;
    }
    if (char == $colon) {
      if (!allowDefaultPackage) {
        throw FormatException("Missing package name", source, index - 1);
      }
      separatorIndex = index - 1;
    }
    isComment = char == $hash;
    while (index < source.length) {
      char = source[index++];
      if (char == $colon && separatorIndex < 0) {
        separatorIndex = index - 1;
      } else if (char == $cr || char == $lf) {
        end = index - 1;
        break;
      }
    }
    if (isComment) continue;
    if (separatorIndex < 0) {
      throw FormatException("No ':' on line", source, index - 1);
    }
    var packageName = String.fromCharCodes(source, start, separatorIndex);
    if (packageName.isEmpty
        ? !allowDefaultPackage
        : !isValidPackageName(packageName)) {
      throw FormatException("Not a valid package name", packageName, 0);
    }
    var packageValue = String.fromCharCodes(source, separatorIndex + 1, end);
    Uri packageLocation;
    if (packageName.isEmpty) {
      if (!isValidPackageName(packageValue)) {
        throw FormatException(
            "Default package entry value is not a valid package name");
      }
      packageLocation = Uri(path: packageValue);
    } else {
      packageLocation = baseLocation.resolve(packageValue);
      if (!packageLocation.path.endsWith('/')) {
        packageLocation =
            packageLocation.replace(path: packageLocation.path + "/");
      }
    }
    if (result.containsKey(packageName)) {
      if (packageName.isEmpty) {
        throw FormatException(
            "More than one default package entry", source, start);
      }
      throw FormatException("Same package name occured twice", source, start);
    }
    result[packageName] = packageLocation;
  }
  return result;
}

/// Writes the mapping to a [StringSink].
///
/// If [comment] is provided, the output will contain this comment
/// with `# ` in front of each line.
/// Lines are defined as ending in line feed (`'\n'`). If the final
/// line of the comment doesn't end in a line feed, one will be added.
///
/// If [baseUri] is provided, package locations will be made relative
/// to the base URI, if possible, before writing.
///
/// If [allowDefaultPackage] is `true`, the [packageMapping] may contain an
/// empty string mapping to the _default package name_.
///
/// All the keys of [packageMapping] must be valid package names,
/// and the values must be URIs that do not have the `package:` scheme.
void write(StringSink output, Map<String, Uri> packageMapping,
    {Uri? baseUri, String? comment, bool allowDefaultPackage = false}) {
  ArgumentError.checkNotNull(allowDefaultPackage, 'allowDefaultPackage');

  if (baseUri != null && !baseUri.isAbsolute) {
    throw ArgumentError.value(baseUri, "baseUri", "Must be absolute");
  }

  if (comment != null) {
    var lines = comment.split('\n');
    if (lines.last.isEmpty) lines.removeLast();
    for (var commentLine in lines) {
      output.write('# ');
      output.writeln(commentLine);
    }
  } else {
    output.write("# generated by package:package_config at ");
    output.write(DateTime.now());
    output.writeln();
  }

  packageMapping.forEach((String packageName, Uri uri) {
    // If [packageName] is empty then [uri] is the _default package name_.
    if (allowDefaultPackage && packageName.isEmpty) {
      final defaultPackageName = uri.toString();
      if (!isValidPackageName(defaultPackageName)) {
        throw ArgumentError.value(
          defaultPackageName,
          'defaultPackageName',
          '"$defaultPackageName" is not a valid package name',
        );
      }
      output.write(':');
      output.write(defaultPackageName);
      output.writeln();
      return;
    }
    // Validate packageName.
    if (!isValidPackageName(packageName)) {
      throw ArgumentError('"$packageName" is not a valid package name');
    }
    if (uri.scheme == "package") {
      throw ArgumentError.value(
          "Package location must not be a package: URI", uri.toString());
    }
    output.write(packageName);
    output.write(':');
    // If baseUri provided, make uri relative.
    if (baseUri != null) {
      uri = _relativize(uri, baseUri);
    }
    if (!uri.path.endsWith('/')) {
      uri = uri.replace(path: uri.path + '/');
    }
    output.write(uri);
    output.writeln();
  });
}

// All ASCII characters that are valid in a package name, with space
// for all the invalid ones (including space).
const String _validPackageNameCharacters =
    r"                                 !  $ &'()*+,-. 0123456789 ; =  "
    r"@ABCDEFGHIJKLMNOPQRSTUVWXYZ    _ abcdefghijklmnopqrstuvwxyz   ~ ";

/// Tests whether something is a valid Dart package name.
bool isValidPackageName(String string) {
  return checkPackageName(string) < 0;
}

/// Check if a string is a valid package name.
///
/// Valid package names contain only characters in [_validPackageNameCharacters]
/// and must contain at least one non-'.' character.
///
/// Returns `-1` if the string is valid.
/// Otherwise returns the index of the first invalid character,
/// or `string.length` if the string contains no non-'.' character.
int checkPackageName(String string) {
  // Becomes non-zero if any non-'.' character is encountered.
  var nonDot = 0;
  for (var i = 0; i < string.length; i++) {
    var c = string.codeUnitAt(i);
    if (c > 0x7f || _validPackageNameCharacters.codeUnitAt(c) <= $space) {
      return i;
    }
    nonDot += c ^ $dot;
  }
  if (nonDot == 0) return string.length;
  return -1;
}

/// Validate that a [Uri] is a valid `package:` URI.
///
/// Used to validate user input.
///
/// Returns the package name extracted from the package URI,
/// which is the path segment between `package:` and the first `/`.
String checkValidPackageUri(Uri packageUri, String name) {
  if (packageUri.scheme != "package") {
    throw PackageConfigArgumentError(packageUri, name, "Not a package: URI");
  }
  if (packageUri.hasAuthority) {
    throw PackageConfigArgumentError(
        packageUri, name, "Package URIs must not have a host part");
  }
  if (packageUri.hasQuery) {
    // A query makes no sense if resolved to a file: URI.
    throw PackageConfigArgumentError(
        packageUri, name, "Package URIs must not have a query part");
  }
  if (packageUri.hasFragment) {
    // We could leave the fragment after the URL when resolving,
    // but it would be odd if "package:foo/foo.dart#1" and
    // "package:foo/foo.dart#2" were considered different libraries.
    // Keep the syntax open in case we ever get multiple libraries in one file.
    throw PackageConfigArgumentError(
        packageUri, name, "Package URIs must not have a fragment part");
  }
  if (packageUri.path.startsWith('/')) {
    throw PackageConfigArgumentError(
        packageUri, name, "Package URIs must not start with a '/'");
  }
  var firstSlash = packageUri.path.indexOf('/');
  if (firstSlash == -1) {
    throw PackageConfigArgumentError(packageUri, name,
        "Package URIs must start with the package name followed by a '/'");
  }
  var packageName = packageUri.path.substring(0, firstSlash);
  var badIndex = checkPackageName(packageName);
  if (badIndex >= 0) {
    if (packageName.isEmpty) {
      throw PackageConfigArgumentError(
          packageUri, name, "Package names mus be non-empty");
    }
    if (badIndex == packageName.length) {
      throw PackageConfigArgumentError(packageUri, name,
          "Package names must contain at least one non-'.' character");
    }
    assert(badIndex < packageName.length);
    var badCharCode = packageName.codeUnitAt(badIndex);
    var badChar = "U+" + badCharCode.toRadixString(16).padLeft(4, '0');
    if (badCharCode >= 0x20 && badCharCode <= 0x7e) {
      // Printable character.
      badChar = "'${packageName[badIndex]}' ($badChar)";
    }
    throw PackageConfigArgumentError(
        packageUri, name, "Package names must not contain $badChar");
  }
  return packageName;
}

/// Checks whether URI is just an absolute directory.
///
/// * It must have a scheme.
/// * It must not have a query or fragment.
/// * The path must end with `/`.
bool isAbsoluteDirectoryUri(Uri uri) {
  if (uri.hasQuery) return false;
  if (uri.hasFragment) return false;
  if (!uri.hasScheme) return false;
  var path = uri.path;
  if (!path.endsWith("/")) return false;
  return true;
}

/// Whether the former URI is a prefix of the latter.
bool isUriPrefix(Uri prefix, Uri path) {
  assert(!prefix.hasFragment);
  assert(!prefix.hasQuery);
  assert(!path.hasQuery);
  assert(!path.hasFragment);
  assert(prefix.path.endsWith('/'));
  return path.toString().startsWith(prefix.toString());
}

/// Finds the first non-JSON-whitespace character in a file.
///
/// Used to heuristically detect whether a file is a JSON file or an .ini file.
int firstNonWhitespaceChar(List<int> bytes) {
  for (var i = 0; i < bytes.length; i++) {
    var char = bytes[i];
    if (char != 0x20 && char != 0x09 && char != 0x0a && char != 0x0d) {
      return char;
    }
  }
  return -1;
}

/// Attempts to return a relative path-only URI for [uri].
///
/// First removes any query or fragment part from [uri].
///
/// If [uri] is already relative (has no scheme), it's returned as-is.
/// If that is not desired, the caller can pass `baseUri.resolveUri(uri)`
/// as the [uri] instead.
///
/// If the [uri] has a scheme or authority part which differs from
/// the [baseUri], or if there is no overlap in the paths of the
/// two URIs at all, the [uri] is returned as-is.
///
/// Otherwise the result is a path-only URI which satsifies
/// `baseUri.resolveUri(result) == uri`,
///
/// The `baseUri` must be absolute.
Uri relativizeUri(Uri uri, Uri? baseUri) {
  if (baseUri == null) return uri;
  assert(baseUri.isAbsolute);
  if (uri.hasQuery || uri.hasFragment) {
    uri = Uri(
        scheme: uri.scheme,
        userInfo: uri.hasAuthority ? uri.userInfo : null,
        host: uri.hasAuthority ? uri.host : null,
        port: uri.hasAuthority ? uri.port : null,
        path: uri.path);
  }

  // Already relative. We assume the caller knows what they are doing.
  if (!uri.isAbsolute) return uri;

  if (baseUri.scheme != uri.scheme) {
    return uri;
  }

  // If authority differs, we could remove the scheme, but it's not worth it.
  if (uri.hasAuthority != baseUri.hasAuthority) return uri;
  if (uri.hasAuthority) {
    if (uri.userInfo != baseUri.userInfo ||
        uri.host.toLowerCase() != baseUri.host.toLowerCase() ||
        uri.port != baseUri.port) {
      return uri;
    }
  }

  baseUri = baseUri.normalizePath();
  var base = [...baseUri.pathSegments];
  if (base.isNotEmpty) base.removeLast();
  uri = uri.normalizePath();
  var target = [...uri.pathSegments];
  if (target.isNotEmpty && target.last.isEmpty) target.removeLast();
  var index = 0;
  while (index < base.length && index < target.length) {
    if (base[index] != target[index]) {
      break;
    }
    index++;
  }
  if (index == base.length) {
    if (index == target.length) {
      return Uri(path: "./");
    }
    return Uri(path: target.skip(index).join('/'));
  } else if (index > 0) {
    var buffer = StringBuffer();
    for (var n = base.length - index; n > 0; --n) {
      buffer.write("../");
    }
    buffer.writeAll(target.skip(index), "/");
    return Uri(path: buffer.toString());
  } else {
    return uri;
  }
}

/// Attempts to return a relative URI for [uri].
///
/// The result URI satisfies `baseUri.resolveUri(result) == uri`,
/// but may be relative.
/// The `baseUri` must be absolute.
Uri _relativize(Uri uri, Uri baseUri) {
  assert(baseUri.isAbsolute);
  if (uri.hasQuery || uri.hasFragment) {
    uri = Uri(
        scheme: uri.scheme,
        userInfo: uri.hasAuthority ? uri.userInfo : null,
        host: uri.hasAuthority ? uri.host : null,
        port: uri.hasAuthority ? uri.port : null,
        path: uri.path);
  }

  // Already relative. We assume the caller knows what they are doing.
  if (!uri.isAbsolute) return uri;

  if (baseUri.scheme != uri.scheme) {
    return uri;
  }

  // If authority differs, we could remove the scheme, but it's not worth it.
  if (uri.hasAuthority != baseUri.hasAuthority) return uri;
  if (uri.hasAuthority) {
    if (uri.userInfo != baseUri.userInfo ||
        uri.host.toLowerCase() != baseUri.host.toLowerCase() ||
        uri.port != baseUri.port) {
      return uri;
    }
  }

  baseUri = baseUri.normalizePath();
  var base = baseUri.pathSegments.toList();
  if (base.isNotEmpty) {
    base = List<String>.from(base)..removeLast();
  }
  uri = uri.normalizePath();
  var target = uri.pathSegments.toList();
  if (target.isNotEmpty && target.last.isEmpty) target.removeLast();
  var index = 0;
  while (index < base.length && index < target.length) {
    if (base[index] != target[index]) {
      break;
    }
    index++;
  }
  if (index == base.length) {
    if (index == target.length) {
      return Uri(path: "./");
    }
    return Uri(path: target.skip(index).join('/'));
  } else if (index > 0) {
    return Uri(
        path: '../' * (base.length - index) + target.skip(index).join('/'));
  } else {
    return uri;
  }
}

// Character constants used by this package.
/// "Line feed" control character.
const int $lf = 0x0a;

/// "Carriage return" control character.
const int $cr = 0x0d;

/// Space character.
const int $space = 0x20;

/// Character `#`.
const int $hash = 0x23;

/// Character `.`.
const int $dot = 0x2e;

/// Character `:`.
const int $colon = 0x3a;

/// Character `?`.
const int $question = 0x3f;

/// Character `{`.
const int $lbrace = 0x7b;

/// General superclass of most errors and exceptions thrown by this package.
///
/// Only covers errors thrown while parsing package configuration files.
/// Programming errors and I/O exceptions are not covered.
abstract class PackageConfigError {
  PackageConfigError._();
}

class PackageConfigArgumentError extends ArgumentError
    implements PackageConfigError {
  PackageConfigArgumentError(Object? value, String name, String message)
      : super.value(value, name, message);

  PackageConfigArgumentError.from(ArgumentError error)
      : super.value(error.invalidValue, error.name, error.message);
}

class PackageConfigFormatException extends FormatException
    implements PackageConfigError {
  PackageConfigFormatException(String message, Object? source, [int? offset])
      : super(message, source, offset);

  PackageConfigFormatException.from(FormatException exception)
      : super(exception.message, exception.source, exception.offset);
}
