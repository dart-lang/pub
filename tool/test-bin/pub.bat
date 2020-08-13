rem Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
rem for details. All rights reserved. Use of this source code is governed by a
rem BSD-style license that can be found in the LICENSE file.

rem Runs the pub snapshot with dart from PATH (or the snapshot if present).

if "%PUB_SNAPSHOT_FILE%"=="" (
    dart %0\..\..\..\bin\pub.dart %*
) else (
    dart %PUB_SNAPSHOT_FILE %*
)
