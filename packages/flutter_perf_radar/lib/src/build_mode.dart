// Copyright (c) 2025, tp9imka. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

/// Whether the perf engine should be active.
///
/// True in debug and profile builds where measurement makes sense.
/// Always false in release builds to ensure zero overhead.
const bool kPerfEnabled = kDebugMode || kProfileMode;
