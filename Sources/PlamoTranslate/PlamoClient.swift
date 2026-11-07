import Foundation

/// PFML3 wire format, following the official PLaMo 3 Translate model template.
enum PFML {
    static func prompt(_ request: TranslationRequest) throws -> String {
        for value in [request.text, request.context, request.glossary] {
            guard !value.contains("<|plamo:") else {
                throw AppFailure.message("PFMLの予約トークンは使用できません。 / Reserved PFML tokens are not allowed.")
            }
        }
        var result = "<|plamo:tag|>dataset<|plamo:msg|>translation"
        if !request.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result += "<|plamo:tag|>context<|plamo:msg|>" + request.context
        }
        let terms = try request.glossary.split(separator: "\n").map { line -> (String, String) in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw AppFailure.message("用語集は「原語 = 訳語」の形式で入力してください。 / Use source = target for each glossary entry.")
            }
            return (parts[0], parts[1])
        }
        if !terms.isEmpty {
            result += "<|plamo:tag|>glossary"
            for (source, target) in terms { result += "<|plamo:index|>\(source)<|plamo:item|>\(target)" }
        }
        result += "<|plamo:tag|>input"
        if request.source != "auto" { result += "<|plamo:key|>lang<|plamo:val|>" + Language.find(request.source).plamoCode }
        result += "<|plamo:msg|>" + request.text
        result += "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>" + Language.find(request.target).plamoCode
        if request.target == "ja" { result += "<|plamo:key|>form<|plamo:val|>" + (request.polite ? "polite" : "plain") }
        return result + "<|plamo:msg|>"
    }
}

struct CompletionEvent: Decodable {
    var content: String?
    var stop: Bool?
    var truncated: Bool?
    var stop_type: String?
    var error: ServerError?
    struct ServerError: Decodable { var message: String }
}

struct PlamoClient {
    var session: URLSession = .shared

    static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "http",
              let host = url.host, ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw AppFailure.message("ローカルサーバーのURLを入力してください（例: http://127.0.0.1:8080）。 / Enter a local server URL.")
        }
        return url.appendingPathComponent("completion")
    }

    func translate(_ request: TranslationRequest, onChunk: @escaping @MainActor (String) -> Void) async throws {
        var http = URLRequest(url: try Self.endpoint(request.endpoint))
        http.httpMethod = "POST"
        http.timeoutInterval = 300
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !request.apiToken.isEmpty { http.setValue("Bearer " + request.apiToken, forHTTPHeaderField: "Authorization") }
        http.httpBody = try JSONSerialization.data(withJSONObject: [
            "prompt": try PFML.prompt(request), "stream": true, "n_predict": 4096,
            "temperature": 0, "stop": ["<|plamo:tag|>", "<|plamo:bos|>"],
            "cache_prompt": true
        ])
        let (bytes, response) = try await session.bytes(for: http)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AppFailure.message("PLaMoサーバーからエラーが返されました（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。 / PLaMo server error.")
        }
        var finished = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if data == "[DONE]" { finished = true; break }
            let event = try JSONDecoder().decode(CompletionEvent.self, from: Data(data.utf8))
            if let error = event.error { throw AppFailure.message(error.message) }
            if event.stop_type == "limit" {
                throw AppFailure.message("翻訳の出力上限に達しました。文章を分けて翻訳してください。 / Output limit reached. Split the text and retry.")
            }
            if event.truncated == true {
                throw AppFailure.message("モデルのコンテキスト上限を超えました。文章を短くしてください。 / Model context exceeded. Shorten the text.")
            }
            if let content = event.content, !content.isEmpty { await onChunk(content) }
            if event.stop == true { finished = true; break }
        }
        try Task.checkCancellation()
        guard finished else {
            throw AppFailure.message("翻訳の途中で接続が切れました。再試行してください。 / Connection closed before translation finished.")
        }
    }
}
