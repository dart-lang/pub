import 'package:path/path.dart' as path;

path.Context context = path.context;

/// A default context for manipulating POSIX paths.
final posix = path.posix;

/// A default context for manipulating Windows paths.
final windows = path.windows;

/// A default context for manipulating URLs.
///
/// URL path equality is undefined for paths that differ only in their
/// percent-encoding or only in the case of their host segment.
final url = path.url;

/// Returns the [Style] of the current context.
///
/// This is the style that all top-level path functions will use.
path.Style get style => context.style;

String get current => context.current;

/// Gets the path separator for the current platform. This is `\` on Windows
/// and `/` on other platforms (including the browser).
String get separator => context.separator;

/// Returns a new path with the given path parts appended to [current].
///
/// Equivalent to [join()] with [current] as the first argument. Example:
///
///     p.absolute('path', 'to/foo'); // -> '/your/current/dir/path/to/foo'
///
/// Does not [normalize] or [canonicalize] paths.
String absolute(
  String part1, [
  String? part2,
  String? part3,
  String? part4,
  String? part5,
  String? part6,
  String? part7,
  String? part8,
  String? part9,
  String? part10,
  String? part11,
  String? part12,
  String? part13,
  String? part14,
  String? part15,
]) => context.absolute(
  part1,
  part2,
  part3,
  part4,
  part5,
  part6,
  part7,
  part8,
  part9,
  part10,
  part11,
  part12,
  part13,
  part14,
  part15,
);

/// Gets the part of [path] after the last separator.
///
///     p.basename('path/to/foo.dart'); // -> 'foo.dart'
///     p.basename('path/to');          // -> 'to'
///
/// Trailing separators are ignored.
///
///     p.basename('path/to/'); // -> 'to'
String basename(String path) => context.basename(path);

/// Gets the part of [path] after the last separator, and without any trailing
/// file extension.
///
///     p.basenameWithoutExtension('path/to/foo.dart'); // -> 'foo'
///
/// Trailing separators are ignored.
///
///     p.basenameWithoutExtension('path/to/foo.dart/'); // -> 'foo'
String basenameWithoutExtension(String path) =>
    context.basenameWithoutExtension(path);

/// Gets the part of [path] before the last separator.
///
///     p.dirname('path/to/foo.dart'); // -> 'path/to'
///     p.dirname('path/to');          // -> 'path'
///
/// Trailing separators are ignored.
///
///     p.dirname('path/to/'); // -> 'path'
///
/// If an absolute path contains no directories, only a root, then the root
/// is returned.
///
///     p.dirname('/');  // -> '/' (posix)
///     p.dirname('c:\');  // -> 'c:\' (windows)
///
/// If a relative path has no directories, then '.' is returned.
///
///     p.dirname('foo');  // -> '.'
///     p.dirname('');  // -> '.'
String dirname(String path) => context.dirname(path);

/// Gets the file extension of [path]: the portion of [basename] from the last
/// `.` to the end (including the `.` itself).
///
///     p.extension('path/to/foo.dart');    // -> '.dart'
///     p.extension('path/to/foo');         // -> ''
///     p.extension('path.to/foo');         // -> ''
///     p.extension('path/to/foo.dart.js'); // -> '.js'
///
/// If the file name starts with a `.`, then that is not considered the
/// extension:
///
///     p.extension('~/.bashrc');    // -> ''
///     p.extension('~/.notes.txt'); // -> '.txt'
///
/// Takes an optional parameter `level` which makes possible to return
/// multiple extensions having `level` number of dots. If `level` exceeds the
/// number of dots, the full extension is returned. The value of `level` must
/// be greater than 0, else `RangeError` is thrown.
///
///     p.extension('foo.bar.dart.js', 2);   // -> '.dart.js
///     p.extension('foo.bar.dart.js', 3);   // -> '.bar.dart.js'
///     p.extension('foo.bar.dart.js', 10);  // -> '.bar.dart.js'
///     p.extension('path/to/foo.bar.dart.js', 2);  // -> '.dart.js'
String extension(String path, [int level = 1]) =>
    context.extension(path, level);

/// Returns the root of [path], if it's absolute, or the empty string if it's
/// relative.
///
///     // Unix
///     p.rootPrefix('path/to/foo'); // -> ''
///     p.rootPrefix('/path/to/foo'); // -> '/'
///
///     // Windows
///     p.rootPrefix(r'path\to\foo'); // -> ''
///     p.rootPrefix(r'C:\path\to\foo'); // -> r'C:\'
///     p.rootPrefix(r'\\server\share\a\b'); // -> r'\\server\share'
///
///     // URL
///     p.rootPrefix('path/to/foo'); // -> ''
///     p.rootPrefix('https://dart.dev/path/to/foo');
///       // -> 'https://dart.dev'
String rootPrefix(String path) => context.rootPrefix(path);

/// Returns `true` if [path] is an absolute path and `false` if it is a
/// relative path.
///
/// On POSIX systems, absolute paths start with a `/` (forward slash). On
/// Windows, an absolute path starts with `\\`, or a drive letter followed by
/// `:/` or `:\`. For URLs, absolute paths either start with a protocol and
/// optional hostname (e.g. `https://dart.dev`, `file://`) or with a `/`.
///
/// URLs that start with `/` are known as "root-relative", since they're
/// relative to the root of the current URL. Since root-relative paths are still
/// absolute in every other sense, [isAbsolute] will return true for them. They
/// can be detected using [isRootRelative].
bool isAbsolute(String path) => context.isAbsolute(path);

/// Returns `true` if [path] is a relative path and `false` if it is absolute.
/// On POSIX systems, absolute paths start with a `/` (forward slash). On
/// Windows, an absolute path starts with `\\`, or a drive letter followed by
/// `:/` or `:\`.
bool isRelative(String path) => context.isRelative(path);

/// Returns `true` if [path] is a root-relative path and `false` if it's not.
///
/// URLs that start with `/` are known as "root-relative", since they're
/// relative to the root of the current URL. Since root-relative paths are still
/// absolute in every other sense, [isAbsolute] will return true for them. They
/// can be detected using [isRootRelative].
///
/// No POSIX and Windows paths are root-relative.
bool isRootRelative(String path) => context.isRootRelative(path);

/// Joins the given path parts into a single path using the current platform's
/// [separator]. Example:
///
///     p.join('path', 'to', 'foo'); // -> 'path/to/foo'
///
/// If any part ends in a path separator, then a redundant separator will not
/// be added:
///
///     p.join('path/', 'to', 'foo'); // -> 'path/to/foo'
///
/// If a part is an absolute path, then anything before that will be ignored:
///
///     p.join('path', '/to', 'foo'); // -> '/to/foo'
String join(
  String part1, [
  String? part2,
  String? part3,
  String? part4,
  String? part5,
  String? part6,
  String? part7,
  String? part8,
  String? part9,
  String? part10,
  String? part11,
  String? part12,
  String? part13,
  String? part14,
  String? part15,
  String? part16,
]) => context.join(
  part1,
  part2,
  part3,
  part4,
  part5,
  part6,
  part7,
  part8,
  part9,
  part10,
  part11,
  part12,
  part13,
  part14,
  part15,
  part16,
);

/// Joins the given path parts into a single path using the current platform's
/// [separator]. Example:
///
///     p.joinAll(['path', 'to', 'foo']); // -> 'path/to/foo'
///
/// If any part ends in a path separator, then a redundant separator will not
/// be added:
///
///     p.joinAll(['path/', 'to', 'foo']); // -> 'path/to/foo'
///
/// If a part is an absolute path, then anything before that will be ignored:
///
///     p.joinAll(['path', '/to', 'foo']); // -> '/to/foo'
///
/// For a fixed number of parts, [join] is usually terser.
String joinAll(Iterable<String> parts) => context.joinAll(parts);

/// Splits [path] into its components using the current platform's [separator].
///
///     p.split('path/to/foo'); // -> ['path', 'to', 'foo']
///
/// The path will *not* be normalized before splitting.
///
///     p.split('path/../foo'); // -> ['path', '..', 'foo']
///
/// If [path] is absolute, the root directory will be the first element in the
/// array. Example:
///
///     // Unix
///     p.split('/path/to/foo'); // -> ['/', 'path', 'to', 'foo']
///
///     // Windows
///     p.split(r'C:\path\to\foo'); // -> [r'C:\', 'path', 'to', 'foo']
///     p.split(r'\\server\share\path\to\foo');
///       // -> [r'\\server\share', 'foo', 'bar', 'baz']
///
///     // Browser
///     p.split('https://dart.dev/path/to/foo');
///       // -> ['https://dart.dev', 'path', 'to', 'foo']
List<String> split(String path) => context.split(path);

/// Canonicalizes [path].
///
/// This is guaranteed to return the same path for two different input paths
/// if and only if both input paths point to the same location. Unlike
/// [normalize], it returns absolute paths when possible and canonicalizes
/// ASCII case on Windows.
///
/// Note that this does not resolve symlinks.
///
/// If you want a map that uses path keys, it's probably more efficient to use a
/// Map with [equals] and [hash] specified as the callbacks to use for keys than
/// it is to canonicalize every key.
String canonicalize(String path) => context.canonicalize(path);

/// Normalizes [path], simplifying it by handling `..`, and `.`, and
/// removing redundant path separators whenever possible.
///
/// Note that this is *not* guaranteed to return the same result for two
/// equivalent input paths. For that, see [canonicalize]. Or, if you're using
/// paths as map keys use [equals] and [hash] as the key callbacks.
///
///     p.normalize('path/./to/..//file.text'); // -> 'path/file.txt'
String normalize(String path) => context.normalize(path);

/// Attempts to convert [path] to an equivalent relative path from the current
/// directory.
///
///     // Given current directory is /root/path:
///     p.relative('/root/path/a/b.dart'); // -> 'a/b.dart'
///     p.relative('/root/other.dart'); // -> '../other.dart'
///
/// If the [from] argument is passed, [path] is made relative to that instead.
///
///     p.relative('/root/path/a/b.dart', from: '/root/path'); // -> 'a/b.dart'
///     p.relative('/root/other.dart', from: '/root/path');
///       // -> '../other.dart'
///
/// If [path] and/or [from] are relative paths, they are assumed to be relative
/// to the current directory.
///
/// Since there is no relative path from one drive letter to another on Windows,
/// or from one hostname to another for URLs, this will return an absolute path
/// in those cases.
///
///     // Windows
///     p.relative(r'D:\other', from: r'C:\home'); // -> 'D:\other'
///
///     // URL
///     p.relative('https://dart.dev', from: 'https://pub.dev');
///       // -> 'https://dart.dev'
String relative(String path, {String? from}) =>
    context.relative(path, from: from);

/// Returns `true` if [child] is a path beneath `parent`, and `false` otherwise.
///
///     p.isWithin('/root/path', '/root/path/a'); // -> true
///     p.isWithin('/root/path', '/root/other'); // -> false
///     p.isWithin('/root/path', '/root/path') // -> false
bool isWithin(String parent, String child) => context.isWithin(parent, child);

/// Returns `true` if [path1] points to the same location as [path2], and
/// `false` otherwise.
///
/// The [hash] function returns a hash code that matches these equality
/// semantics.
bool equals(String path1, String path2) => context.equals(path1, path2);

/// Returns a hash code for [path] such that, if [equals] returns `true` for two
/// paths, their hash codes are the same.
///
/// Note that the same path may have different hash codes on different platforms
/// or with different [current] directories.
int hash(String path) => context.hash(path);

/// Removes a trailing extension from the last part of [path].
///
///     p.withoutExtension('path/to/foo.dart'); // -> 'path/to/foo'
String withoutExtension(String path) => context.withoutExtension(path);

/// Returns [path] with the trailing extension set to [extension].
///
/// If [path] doesn't have a trailing extension, this just adds [extension] to
/// the end.
///
///     p.setExtension('path/to/foo.dart', '.js') // -> 'path/to/foo.js'
///     p.setExtension('path/to/foo.dart.js', '.map')
///       // -> 'path/to/foo.dart.map'
///     p.setExtension('path/to/foo', '.js') // -> 'path/to/foo.js'
String setExtension(String path, String extension) =>
    context.setExtension(path, extension);

/// Returns the path represented by [uri], which may be a [String] or a [Uri].
///
/// For POSIX and Windows styles, [uri] must be a `file:` URI. For the URL
/// style, this will just convert [uri] to a string.
///
///     // POSIX
///     p.fromUri('file:///path/to/foo') // -> '/path/to/foo'
///
///     // Windows
///     p.fromUri('file:///C:/path/to/foo') // -> r'C:\path\to\foo'
///
///     // URL
///     p.fromUri('https://dart.dev/path/to/foo')
///       // -> 'https://dart.dev/path/to/foo'
///
/// If [uri] is relative, a relative path will be returned.
///
///     p.fromUri('path/to/foo'); // -> 'path/to/foo'
String fromUri(Object? uri) => context.fromUri(uri!);

/// Returns the URI that represents [path].
///
/// For POSIX and Windows styles, this will return a `file:` URI. For the URL
/// style, this will just convert [path] to a [Uri].
///
///     // POSIX
///     p.toUri('/path/to/foo')
///       // -> Uri.parse('file:///path/to/foo')
///
///     // Windows
///     p.toUri(r'C:\path\to\foo')
///       // -> Uri.parse('file:///C:/path/to/foo')
///
///     // URL
///     p.toUri('https://dart.dev/path/to/foo')
///       // -> Uri.parse('https://dart.dev/path/to/foo')
///
/// If [path] is relative, a relative URI will be returned.
///
///     p.toUri('path/to/foo') // -> Uri.parse('path/to/foo')
Uri toUri(String path) => context.toUri(path);

/// Returns a terse, human-readable representation of [uri].
///
/// [uri] can be a [String] or a [Uri]. If it can be made relative to the
/// current working directory, that's done. Otherwise, it's returned as-is. This
/// gracefully handles non-`file:` URIs for [Style.posix] and [Style.windows].
///
/// The returned value is meant for human consumption, and may be either URI-
/// or path-formatted.
///
///     // POSIX at "/root/path"
///     p.prettyUri('file:///root/path/a/b.dart'); // -> 'a/b.dart'
///     p.prettyUri('https://dart.dev/'); // -> 'https://dart.dev'
///
///     // Windows at "C:\root\path"
///     p.prettyUri('file:///C:/root/path/a/b.dart'); // -> r'a\b.dart'
///     p.prettyUri('https://dart.dev/'); // -> 'https://dart.dev'
///
///     // URL at "https://dart.dev/root/path"
///     p.prettyUri('https://dart.dev/root/path/a/b.dart'); // -> r'a/b.dart'
///     p.prettyUri('file:///root/path'); // -> 'file:///root/path'
String prettyUri(Object? uri) => context.prettyUri(uri!);
