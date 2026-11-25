package com.chorequest.applock

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * The two calls App Lock's watcher makes itself, while ChoreQuest's screen
 * may be closed: the next minute of a child's earned time, and its own
 * report (AL-3, AL-4). Everything else goes through the app's API client.
 *
 * Blocking; called on the watcher's network thread only. A status of 0
 * means the server could not be reached.
 */
object AppLockHttp {
    data class Answer(val status: Int, val body: JSONObject?)

    fun post(url: String, body: JSONObject, token: String? = null): Answer {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 15_000
                doOutput = true
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Content-Type", "application/json")
                if (token != null) setRequestProperty("Authorization", "Bearer $token")
            }
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val text = stream?.bufferedReader()?.use { it.readText() }
            Answer(status, text?.let { runCatching { JSONObject(it) }.getOrNull() })
        } catch (_: Exception) {
            Answer(0, null)
        } finally {
            connection?.disconnect()
        }
    }
}
