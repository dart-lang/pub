# The Pub cache

The Pub cache is where pub stores downloaded packages and globally activated
packages.

The information in this document is informational, and can be used for
understanding the cache, but we strongly encourage all manipulation of the cache
happens though the `dart pub`/`flutter pub` commands to avoid relying on
accidental properties of the cache that might be broken in the future.

See [system_cache](../lib/src/system_cache.dart) for implementation of top-level
cache conventions.

## Location

The global default pub-cache is located at:
 * `$HOME/.pub_cache` on Linux and macOS,
 * `%LOCALAPPDATA%/Pub/Cache` on Windows.

Prior to Flutter 3.8.0, the Flutter SDK declared `PUB_CACHE=$FLUTTER_ROOT/.pub_cache` overriding the default global pub-cache.

The default location of the pub-cache can be overridden using the environment variable `PUB_CACHE`.

For the remainder of this document we refer to the location of the pub-cache as `$PUB_CACHE`.

## Layout

The layout of the pub cache has evolved over time, and where possible we strive
for backwards and forwards compatibility where possible, such that a new and an
old sdk can share the same cache.

Here are the top-level folders you can find in a Pub cache.

```plaintext
$PUB_CACHE/
├── global_packages/  # Globally activated packages
├── active_roots/     # Information about packages that this cache caches for.
├── bin/              # Executables compiled from globally activated packages.
├── git/              # Cloned git packages
├── hosted/           # Hosted package downloads
├── hosted-hashes/    # Hashes of hosted packages
├── log/              # Logs after crashes and --verbose
├── README.md         # Short description of the folder
└── _temp/            # Package downloads are extracted here, and moved atomically.
```

Prior to Dart 2.15.0 pub would also store credentials in the pub-cache. They are now
stored in a platform specific config dir:

* On Linux `$XDG_CONFIG_HOME/dart/pub-credentials.json` if `$XDG_CONFIG_HOME` is
  defined, otherwise `$HOME/.config/dart/pub-credentials.json`
* On macOS: `$HOME/Library/Application Support/dart/pub-credentials.json`
* On Windows: `%APPDATA%/dart/pub-credentials.json`

### Hosted

The `hosted/` folder contains one folder per repository that Pub has retrieved packages from.

See [hosted](../lib/src/source/hosted.dart) for details.

```plaintext
$PUB_CACHE/hosted
├── pub.dartlang.org
├── pub.dev
└── pub.flutter-io.cn
```

Before Dart 2.19 pub would by default download from `pub.dartlang.org`. This was
changed to `pub.dev`. The two sites are mirrors and should always be identical.
We decided to make the switch when we introduced content-hashes, because they
anyway required redownloading of all packages to calculate the hashes.

The url of the repository is encoded to a directory name with a weird URI-like
encoding. This is a mistake that seems costly to fix, but is worth being aware
of.

Each repository folder has a sub-folder per `$package-$version/` that is
downloaded from that repository:

```plaintext
$PUB_CACHE/hosted/pub.dev/
├── .cache/
├── args-2.3.2/
├── retry-1.0.0/
├── yaml-3.1.1/
├── yaml_edit-2.0.2/
└── yaml_edit-2.1.0/
```

A package name can always be used as a file-name (TODO: should we have a length-restriction on package-names? https://github.com/dart-lang/pub/issues/3895).

A serialized version string can always be encoded as a file-name.

These subfolders contain the content of the packages as they are extracted from
the package archives. These are extracted in `.pub_cache/_temp` and moved here
atomically, hence, packages here are always fully extracted.

The `.cache/` folder is storing the last version listing response for each
package:

```plaintext
$PUB_CACHE/hosted/pub.dev/.cache
├── args-versions.json
├── retry-versions.json
├── yaml_edit-versions.json
└── yaml-versions.json
```

These are used as a heuristic to speed up version resolution. They are
timestamped with the time of retrieval.

(This should arguably have been called something like `$PUB_CACHE/hosted-version-listings` to separate cleanly from the package downloads).

Adding further files or folders inside `hosted/` unless the start with a '.' will break
the `dart pub cache clean` command from older SDKs and should be avoided. (It assumes all folders/files are packages that need to be restored).

The `$PUB_CACHE/hosted-hashes/` folder has a file per package-version with the sha256 hash of the downloaded archive:

```plaintext
$PUB_CACHE/hosted-hashes/
└── pub.dev/
    ├── args-2.3.2.sha256
    ├── retry-1.0.0.sha256
    ├── yaml-3.1.1.sha256
    ├── yaml_edit-2.0.2.sha256
    └── yaml_edit-2.1.0.sha256
```

These are used to ensure the integrity of the relation between a `pubspec.lock` file and
the cache.

* If a version-listing shows another hash, the package is redownloaded.
* If a `pubspec.lock` file shows another hash the package is redownloaded.

`$PUB_CACHE/hosted-hashes/` was introduced in Dart 2.19.0.

## Git

The `$PUB_CACHE/git/` folder has checkouts of the git repositories containing git dependencies.

See [git](../lib/src/source/git.dart) for details.

A git dependency is declared using:
 * `url` (required)
 * `ref` (optional, defaults to the default branch)
 * `path` (optional, defaults to `.`)

Note that we have the entire checkout, even though a package can be nested
deeper inside using `path`. Two packages can share the same checkout.

It is laid out as this example:

```plaintext
$PUB_CACHE/git/
├── cache/
│   ├── pana-72b499ded128c6590fbda1b7e87de1c8bbb38a04/
│   └── pub-d666e8aee885cce49978e27a66c99ee08ce3995f/
├── pana-bab826581f3f7a0604022f2043490a3b501e785e/
├── pub-75c671c7d65db43f197b55419a8519906a611730/
└── pub-c4e9ddc888c3aa89ef4462f0c4298929191e32b9/
```

The `$PUB_CACHE/git/cache/` folder contains a "bare" checkout of each git-url (just the ). The
folders are `$PUB_CACHE/git/cache/$name-$hash/` where `$name` is derived from base-name of the
git url (without `.git`). and `$hash` is the sha1 of the git-url. This makes
them recognizable and unique.

The other sub-folders are the actual checkouts. They are clones of respective the `$PUB_CACHE/git/cache/$name-$hash/`
folders checked out at a specific `ref`. The name is `$PUB_CACHE/git/$name-$resolvedRef/` where
`resolvedRef` is the commit-id that `ref` resolves to.

## Global packages

The `$PUB_CACHE/global_packages/` folder contains the globally activated
packages.

See [global_packages](../lib/src/global_packages.dart) for the implementation
the global package conventions.

The folder is laid out like in this example:

```plaintext
$PUB_CACHE/global_packages/
├── stagehand/
│   ├── bin/
│   │   └── stagehand.dart-2.19.0.snapshot
│   ├── .dart_tool/
│   │   └── package_config.json
│   ├── incremental
│   └── pubspec.lock
└── mono_repo/
    ├── bin/
    │   ├── mono_repo.dart-2.18.4.snapshot
    │   ├── mono_repo.dart-3.0.0-0.0.dev.snapshot
    │   └── mono_repo.dart-3.0.0-55.0.dev.snapshot
    ├── .dart_tool/
    │   └── package_config.json
    └── pubspec.lock
```

There can only be one globally activated package with a given name at the same
time.

Each globally installed package has its own folder with a `pubspec.lock` and a
`.dart_tool/package_config.json`.

The `pubspec.lock` holds the current resolution for the activated package.

The `bin/` folder contains precompiled snapshots - these are compilations of
`bin/*.dart` files from the activated packages, suffixed by
`-$sdkVersion.snapshot`. Several snapshots can exist if the same globally
activated package is used by several sdk-versions (TODO: This does have some
limitations, and we should probably rethink this). A re-activation of the
package will delete all the existing snapshots.

For packages activated with `--source=path` the lockfile is special-cased to just point
to the activated path, and `.dart_tool/package_config.json`, snapshots are
stored in that folder.

The `$PUB_CACHE/bin/` folder contains "binstubs" that are small executable
scripts that will run the precompiled snapshots.

By default one binstub is generated per `executable` in the `pubspec.yaml` of an
activated package. The binstub contains decodable information about which
package it belongs to, so it can be deleted when a package is `deactivated` and
a helpful message can be shown in case of conflicts.

If the snapshot doesn't exist, the binstub will attempt to create it by invoking
`dart pub global run`.

```plaintext
$PUB_CACHE/bin/
├── mono_repo
└── stagehand
```

# Active roots
$PUB_CACHE/active_roots/

In order to be able to prune the cache (`dart pub cache gc`) pub keeps a tally of
each time it writes a `.dart_tool/package_config.json` file (an activation).

The directory is laid out such that each file-name is the hex-encoded sha256
hash of the absolute file-uri of the path of the package config.

The first two bytes are used for a subdirectory, to prevent too many files in
one directory.

When implemented `dart pub cache gc` will look through all the package configs,
and mark all cached packages in the cache used by those projects `alive`. If a
package config doesn't exist, it is ignored.

All other packages in the cache are removed.

Packages that are installed in the cache within 1 hour are not deleted. This is
to minimize the risk of race-conditions.  

## Logs

When pub crashes or is run with `--verbose` it will create a
`$PUB_CACHE/log/pub_log.txt` with the dart sdk version, platform, `$PUB_CACHE`,
`$PUB_HOSTED_URL`, `pubspec.yaml`, `pubspec.lock`, current command, verbose log
and stack-trace.
