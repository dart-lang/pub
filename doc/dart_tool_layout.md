# Layout of the `.dart_tool/pub` folder

The pub client creates `.dart_tool/package_config.json` as described by
[https://github.com/dart-lang/language/blob/main/accepted/2.8/language-versioning/package-config-file-v2.md].

But furthermore pub can use a folder called `.dart_tool/pub` for storing
artifacts. The organization of that folder is what this document is trying to describe.

The information in this document is informational, and can be used for
understanding the cache, but we strongly encourage all manipulation of the
`.dart_tool/pub` folder happens though the `dart pub`/`flutter pub` commands to
avoid relying on accidental properties that might be broken in the future.

## Precompilation cache

```tree
.dart_tool/
├── package_config.json
├── pub
│   ├── bin
│   │   ├── pub
│   │   │   └── pub.dart-3.1.0.snapshot.incremental
│   │   └── test
│   │       └── test.dart-3.2.0-36.0.dev.snapshot

```

When `dart run <package>:<executable>` is called, pub will try to find `<executable>` in
the package `<package>` and compile it as a "dill" file (using
`package:frontend_server_client`).

The output will be stored in The dill file will be stored in
`.dart_tool/pub/bin/<package>/<executable>.dart-<sdk-version>.snapshot`.

This can be used to run the executable by invoking (done implicitly by `dart run`):

```
dart .dart_tool/pub/bin/<package>/<executable>.dart-<sdk-version>.snapshot
```

But the dill-file is also fed to the compiler for incremental compilation. This
can in many cases greatly speed up the compilation when no change has happened.

If the compilation fails, pub avoids leaving a `.snapshot` file, but instead leaves a
`.dart_tool/pub/bin/<package>/<executable>.dart-<sdk-version>.snapshot.incremental` file.

This file cannot be executed. But it can still give the benefit of incremental
compilation when changes have happened to the code.

Earlier versions of the dart sdk would put this "incremental" file in:

`.dart_tool/pub/incremental/<package>/<executable>.dart-incremental.dill`.

As we don't expect many of those files to linger, we don't attempt to clean them up.

We use the `<sdk-version>` to enable different sdk-versions to each have their
own snapshot, so they don't step on each others toes when you switch from one
sdk to another. The downside is that there is no mechanism for deleting
snapshots of old sdks. We might want change that logic.

One could argue that a "snapshot", is a different thing from a "dill" file in
Dart VM terms. But both can be invoked by the VM, and run rather quickly without
much more pre-compilation. In the future we might want to use true "snapshots"
for executables from immutable packages, as they don't benefit from incremental compilation.
