package com.haishinkit.kaiwakit

import java.io.IOException

/** An unsuccessful HTTP response, without the credential or server response body. */
class RealtimeRequestException internal constructor(
    val statusCode: Int,
    operation: String,
) : IOException("$operation failed (HTTP $statusCode)")
