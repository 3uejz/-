class_name HttpTransport
extends Node
## 真实 HTTP 传输（Godot HTTPRequest，异步）。
##
## 与 `ApiClient` 的同步 transport 契约不同，这里 `send()` 是协程。推荐用法
## （由网关 / Net autoload 组合）：
##     var req := api.build_request("POST", "/auth/login", {"body": {...}})
##     var resp: Dictionary = await http.send(req)
##     var result: Dictionary = api.handle_response(resp)
## 返回 resp = { ok:bool, status:int, headers:Dictionary, body:String, error:String }。

const RESULT_NAMES := {
	HTTPRequest.RESULT_SUCCESS: "",
	HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "chunked body size mismatch",
	HTTPRequest.RESULT_CANT_CONNECT: "cannot connect",
	HTTPRequest.RESULT_CANT_RESOLVE: "cannot resolve host",
	HTTPRequest.RESULT_CONNECTION_ERROR: "connection error",
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "tls handshake error",
	HTTPRequest.RESULT_NO_RESPONSE: "no response",
	HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "body size limit exceeded",
	HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: "body decompress failed",
	HTTPRequest.RESULT_REQUEST_FAILED: "request failed",
	HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: "download file cannot open",
	HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: "download file write error",
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "redirect limit reached",
	HTTPRequest.RESULT_TIMEOUT: "timeout",
}

const METHOD_MAP := {
	"GET": HTTPClient.METHOD_GET,
	"POST": HTTPClient.METHOD_POST,
	"PUT": HTTPClient.METHOD_PUT,
	"PATCH": HTTPClient.METHOD_PATCH,
	"DELETE": HTTPClient.METHOD_DELETE,
	"HEAD": HTTPClient.METHOD_HEAD,
	"OPTIONS": HTTPClient.METHOD_OPTIONS,
}

func send(req: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = maxf(1.0, float(req.get("timeout_ms", ApiClient.DEFAULT_TIMEOUT_MS)) / 1000.0)
	add_child(http)
	var url := str(req.get("url", ""))
	var method_name := str(req.get("method", "GET")).to_upper()
	var method: int = METHOD_MAP.get(method_name, HTTPClient.METHOD_GET)
	var headers := PackedStringArray()
	for key in (req.get("headers", {}) as Dictionary).keys():
		headers.append("%s: %s" % [str(key), str(req["headers"][key])])
	var body := str(req.get("body", ""))
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "headers": {}, "body": "", "error": "request setup failed (%d)" % err}
	var completed: Array = await http.request_completed
	http.queue_free()
	var res_code := int(completed[0])
	var status := int(completed[1])
	var raw_headers: PackedStringArray = completed[2]
	var raw_body: PackedByteArray = completed[3]
	if res_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"status": status,
			"headers": _parse_headers(raw_headers),
			"body": raw_body.get_string_from_utf8(),
			"error": str(RESULT_NAMES.get(res_code, "http error %d" % res_code)),
		}
	return {
		"ok": true,
		"status": status,
		"headers": _parse_headers(raw_headers),
		"body": raw_body.get_string_from_utf8(),
		"error": "",
	}

func _parse_headers(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for line in raw:
		var idx := line.find(":")
		if idx <= 0:
			continue
		out[line.substr(0, idx).strip_edges()] = line.substr(idx + 1).strip_edges()
	return out
