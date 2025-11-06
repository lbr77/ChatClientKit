import Foundation
import Darwin
import Dispatch
import ChatClientKit
import OAuthKit
// OAuth is not used in this test target

/// Helper to bridge async work into the top-level script.
func runAsync<T>(_ operation: @escaping () async throws -> T) -> Result<T, Error> {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task {
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return result
}
private func loadInstructionsFile() -> String? {
    func readViaOpen(_ path: String) -> String? {
        let fd = open(path, O_RDONLY)
        if fd < 0 { return nil }
        defer { _ = close(fd) }
        var buf = [UInt8](repeating: 0, count: 8192)
        var data = Data()
        while true {
            let n = buf.withUnsafeMutableBytes { ptr -> Int in
                read(fd, ptr.baseAddress, ptr.count)
            }
            if n > 0 {
                data.append(buf, count: n)
            } else {
                break
            }
        }
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    func getCWD() -> String? {
        var buf = [Int8](repeating: 0, count: 4096)
        guard getcwd(&buf, buf.count) != nil else { return nil }
        return String(cString: &buf)
    }

    func resolve(_ p: String) -> String {
        var out = [Int8](repeating: 0, count: 4096)
        return p.withCString { rp in
            realpath(rp, &out) != nil ? String(cString: &out) : p
        }
    }

    func parentPath(_ path: String) -> String? {
        if path == "/" { return nil }
        if let r = path.range(of: "/", options: .backwards) {
            let base = String(path[..<r.lowerBound])
            return base.isEmpty ? "/" : base
        }
        return nil
    }

    let env = ProcessInfo.processInfo.environment
    if let p = env["INSTRUCTIONS_FILE"], !p.isEmpty {
        let rp = resolve(p)
        if let t = readViaOpen(rp) {
            print("[instructions] Loaded from INSTRUCTIONS_FILE: \(rp) (\(t.count) bytes)")
            return t
        } else {
            print("[instructions] INSTRUCTIONS_FILE set but unreadable: \(rp)")
        }
    }

    var tried: [String] = []

    if let cwd = getCWD() {
        var cur: String? = cwd
        for _ in 0...5 {
            if let c = cur {
                let candidate = (c.hasSuffix("/") ? c + "1.md" : c + "/1.md")
                tried.append(candidate)
                if let t = readViaOpen(candidate) {
                    print("[instructions] Loaded from: \(candidate) (\(t.count) bytes)")
                    return t
                }
                cur = parentPath(c)
            }
        }
    }

    if let arg0 = CommandLine.arguments.first, !arg0.isEmpty {
        let exe = resolve(arg0)
        var dir = parentPath(exe)
        for _ in 0...6 {
            if let d = dir {
                let candidate = (d.hasSuffix("/") ? d + "1.md" : d + "/1.md")
                tried.append(candidate)
                if let t = readViaOpen(candidate) {
                    print("[instructions] Loaded from: \(candidate) (\(t.count) bytes)")
                    return t
                }
                dir = parentPath(d)
            }
        }
    }

    print("[instructions] 1.md not found. Tried: \(tried.joined(separator: ", "))")
    return nil
}
/// Try to extract a ChatGPT account identifier from an ID token (JWT)
private func chatGPTAccountId(from idToken: String?) -> String? {
    guard let idToken, !idToken.isEmpty else { return nil }
    let parts = idToken.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    let payloadPart = String(parts[1])
    // Base64URL decode
    var base64 = payloadPart.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let padding = 4 - (base64.count % 4)
    if padding < 4 { base64 += String(repeating: "=", count: padding) }
    guard let data = Data(base64Encoded: base64),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    // Common candidate keys
    let candidateKeys = ["chatgpt_account_id", "chatgpt_user_id", "account_id", "sub"]
    for key in candidateKeys {
        if let value = json[key] as? String, !value.isEmpty { return value }
    }
    return nil
}

// MARK: - Tool Invocation Check

/// 检查“工具调用”是否能被正确触发与解析。
/// 运行方式：传入 `--check-tools` 参数启动此检查逻辑。
/// 逻辑：
/// 1) 向模型声明一个名为 `echo` 的工具（函数）。
/// 2) 提示模型必须调用该工具，并传入 JSON 参数。
/// 3) 在 SSE 流结束时，`RemoteChatClient` 会归并工具调用并抛出 `.tool` 事件；
///    我们对收到的调用做 JSON 解析校验并打印结果。
func runToolInvocationCheck() async {
    // guard let apiKey = getenv("OPENAI_API_KEY") else {
    //     fputs("Missing OPENAI_API_KEY in environment.\n", stderr)
    //     return
    // }
    let oauthConfig = OAuthConfiguration(
        clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
        authorizationEndpoint: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenEndpoint: URL(string: "https://auth.openai.com/oauth/token")!,
        redirectURI: URL(string: "http://localhost:1455/auth/callback")!,
        scope: "openid profile email offline_access",
        additionalParameters: [
            "id_token_add_organizations": "true",
            "codex_cli_simplified_flow": "true"
        ],
        usePKCE: true,
        pkceMethod: .sha256
    )
    let fileStorage = FileTokenStorage(fileName: "oauth_token.json")
    let oauthClient = OAuthClient(configuration: oauthConfig, tokenStorage: fileStorage)
    let existingToken = try? await oauthClient.getValidToken()
    let baseURL = "https://chatgpt.com/backend-api/codex/responses"
    let model = "gpt-5"
    var headers: [String: String] = [
        "Host": "chatgpt.com",
        "Accept": "text/event-stream"
    ]
    if let accountId = chatGPTAccountId(from: existingToken?.idToken) {
        headers["chatgpt-account-id"] = accountId
    }

    var additionalFields: [String: Any] = [
        "store": false,
    ]
    if let fileInstructions = loadInstructionsFile() {
        additionalFields["instructions"] = fileInstructions
    }
    var client = RemoteChatClient(
        model: "gpt-5",
        format: OpenAIResponsesFormat(),
        baseURL: "https://chatgpt.com/backend-api/codex/responses",
        apiKey: existingToken?.accessToken ?? "sk-none",
        additionalHeaders: headers,
        additionalBodyField: additionalFields
    )
    client.debugLogging = true

    // 定义一个简单的 echo 工具，要求参数中包含 message:string
    let echoTool: ChatRequestBody.Tool = .function(
        name: "echo",
        description: "Echo the provided message.",
        parameters: [
            "type": "object",
            "properties": [
                "message": [
                    "type": "string",
                    "description": "Text to echo"
                ]
            ],
            "required": ["message"]
        ],
        strict: false
    )

    // 要求模型必须调用 echo 工具，传入固定消息，便于可重复验证
    let userPrompt = "请调用工具 echo，并传入 {\"message\":\"ping\"}。"
    let user = ChatRequestBody.Message.user(content: .text(userPrompt))

    var request = ChatRequestBody(
        messages: [user],
        maxCompletionTokens: 64,
        temperature: 0,
        tools: [echoTool],
        toolChoice: .required
    )

    do {
        let stream = try await client.streamingChatCompletionRequest(body: request)
        var receivedToolCalls: [ToolCallRequest] = []

        for try await event in stream {
            switch event {
            case let .chatCompletionChunk(chunk):
                // 这里可以观察模型输出的 delta；工具调用最终在流结束时汇总
                if client.debugLogging {
                    let deltas = chunk.choices.map { $0.delta.content ?? "" }.joined()
                    if !deltas.isEmpty {
                        print("[check-tools] delta: \(deltas)")
                    }
                }
            case let .tool(call):
                receivedToolCalls.append(call)
            }
        }

        if receivedToolCalls.isEmpty {
            print("[check-tools] 未捕获到任何工具调用。请确认模型与后端支持 function calling。")
            return
        }

        print("[check-tools] 共捕获到 \(receivedToolCalls.count) 个工具调用：")
        for (idx, call) in receivedToolCalls.enumerated() {
            print("#\(idx + 1) name=\(call.name)")
            print("args(raw)=\(call.args)")

            // 尝试把 args 解析为 JSON 以校验有效性
            if let data = call.args.data(using: .utf8) {
                do {
                    let obj = try JSONSerialization.jsonObject(with: data)
                    print("args(json)=\(obj)")
                    // 简单校验 echo 形状
                    if call.name == "echo",
                       let dict = obj as? [String: Any],
                       let msg = dict["message"] as? String,
                       !msg.isEmpty {
                        print("[check-tools] echo 参数校验通过: message=\(msg)")
                    } else if call.name == "echo" {
                        print("[check-tools] echo 参数缺失或格式不正确")
                    }
                } catch {
                    print("[check-tools] args 不是合法 JSON: \(error)")
                }
            } else {
                print("[check-tools] args 编码为 UTF-8 失败")
            }
        }
    } catch {
        print("[check-tools] 检查失败: \(error)")
        if let collected = client.collectedErrors { print("[check-tools] collected: \(collected)") }
    }
}

_ = runAsync {
    await runToolInvocationCheck()
}
// /// Try to extract a ChatGPT account identifier from an ID token (JWT)
// private func chatGPTAccountId(from idToken: String?) -> String? {
//     guard let idToken, !idToken.isEmpty else { return nil }
//     let parts = idToken.split(separator: ".")
//     guard parts.count >= 2 else { return nil }
//     let payloadPart = String(parts[1])
//     // Base64URL decode
//     var base64 = payloadPart.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
//     let padding = 4 - (base64.count % 4)
//     if padding < 4 { base64 += String(repeating: "=", count: padding) }
//     guard let data = Data(base64Encoded: base64),
//           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
//     else { return nil }

//     // Common candidate keys
//     let candidateKeys = ["chatgpt_account_id", "chatgpt_user_id", "account_id", "sub"]
//     for key in candidateKeys {
//         if let value = json[key] as? String, !value.isEmpty { return value }
//     }
//     return nil
// }

// /// Load instructions content from 1.md in current working directory
// private func loadInstructionsFile() -> String? {
//     func readViaOpen(_ path: String) -> String? {
//         let fd = open(path, O_RDONLY)
//         if fd < 0 { return nil }
//         defer { _ = close(fd) }
//         var buf = [UInt8](repeating: 0, count: 8192)
//         var data = Data()
//         while true {
//             let n = buf.withUnsafeMutableBytes { ptr -> Int in
//                 read(fd, ptr.baseAddress, ptr.count)
//             }
//             if n > 0 {
//                 data.append(buf, count: n)
//             } else {
//                 break
//             }
//         }
//         guard let text = String(data: data, encoding: .utf8),
//               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
//             return nil
//         }
//         return text
//     }

//     func getCWD() -> String? {
//         var buf = [Int8](repeating: 0, count: 4096)
//         guard getcwd(&buf, buf.count) != nil else { return nil }
//         return String(cString: &buf)
//     }

//     func resolve(_ p: String) -> String {
//         var out = [Int8](repeating: 0, count: 4096)
//         return p.withCString { rp in
//             realpath(rp, &out) != nil ? String(cString: &out) : p
//         }
//     }

//     func parentPath(_ path: String) -> String? {
//         if path == "/" { return nil }
//         if let r = path.range(of: "/", options: .backwards) {
//             let base = String(path[..<r.lowerBound])
//             return base.isEmpty ? "/" : base
//         }
//         return nil
//     }

//     let env = ProcessInfo.processInfo.environment
//     if let p = env["INSTRUCTIONS_FILE"], !p.isEmpty {
//         let rp = resolve(p)
//         if let t = readViaOpen(rp) {
//             print("[instructions] Loaded from INSTRUCTIONS_FILE: \(rp) (\(t.count) bytes)")
//             return t
//         } else {
//             print("[instructions] INSTRUCTIONS_FILE set but unreadable: \(rp)")
//         }
//     }

//     var tried: [String] = []

//     if let cwd = getCWD() {
//         var cur: String? = cwd
//         for _ in 0...5 {
//             if let c = cur {
//                 let candidate = (c.hasSuffix("/") ? c + "1.md" : c + "/1.md")
//                 tried.append(candidate)
//                 if let t = readViaOpen(candidate) {
//                     print("[instructions] Loaded from: \(candidate) (\(t.count) bytes)")
//                     return t
//                 }
//                 cur = parentPath(c)
//             }
//         }
//     }

//     if let arg0 = CommandLine.arguments.first, !arg0.isEmpty {
//         let exe = resolve(arg0)
//         var dir = parentPath(exe)
//         for _ in 0...6 {
//             if let d = dir {
//                 let candidate = (d.hasSuffix("/") ? d + "1.md" : d + "/1.md")
//                 tried.append(candidate)
//                 if let t = readViaOpen(candidate) {
//                     print("[instructions] Loaded from: \(candidate) (\(t.count) bytes)")
//                     return t
//                 }
//                 dir = parentPath(d)
//             }
//         }
//     }

//     print("[instructions] 1.md not found. Tried: \(tried.joined(separator: ", "))")
//     return nil
// }

// // Create OAuth configuration for OpenAI (per Wei-Shaw/claude-relay-service)


// // Create OAuth client with file-based storage for persistence
// let fileStorage = FileTokenStorage(fileName: "oauth_token.json")
// let oauthClient = OAuthClient(configuration: oauthConfig, tokenStorage: fileStorage)

// _ = runAsync {
//     do {
//         // 1) Try using an existing valid token (skip OAuth if present)
//         if let existingToken = try? await oauthClient.getValidToken() {
//             print("Found existing token, skipping OAuth flow. Token: \(existingToken.accessToken.prefix(12))…")

//             var headers: [String: String] = [
//                 "Host": "chatgpt.com",
//                 "Accept": "text/event-stream"
//             ]
//             if let accountId = chatGPTAccountId(from: existingToken.idToken) {
//                 headers["chatgpt-account-id"] = accountId
//             }

//             var additionalFields: [String: Any] = [
//                 "store": false,
//             ]
//             if let fileInstructions = loadInstructionsFile() {
//                 additionalFields["instructions"] = fileInstructions
//             }
//             var client = RemoteChatClient(
//                 model: "gpt-5",
//                 format: OpenAIResponsesFormat(),
//                 baseURL: "https://chatgpt.com/backend-api/codex/responses",
//                 apiKey: existingToken.accessToken,
//                 additionalHeaders: headers,
//                 additionalBodyField: additionalFields
//             )
//             client.debugLogging = true
//             await testChatClient(client)
//             return
//         }

//         // 2) No valid token, start OAuth flow
//         let authURL = try oauthClient.buildAuthorizationURL()
//         print("Authorization URL: \(authURL)")
//         print("Please visit the URL above and paste the callback URL here:")

//         guard let callbackURLString = readLine(),
//               let callbackURL = URL(string: callbackURLString) else {
//             print("Invalid callback URL")
//             return
//         }

//         print("Received callback URL: \(callbackURL)")

//         // Parse the callback URL to extract authorization code and state
//         guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
//             print("Failed to create URLComponents from: \(callbackURL)")
//             return
//         }

//         print("URL components parsed successfully")
//         print("Query items: \(components.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: "&") ?? "none")")

//         guard let queryItems = components.queryItems else {
//             print("No query items found in callback URL")
//             return
//         }

//         var authCode: String?
//         var state: String?

//         for item in queryItems {
//             print("Processing query item: \(item.name) = \(item.value ?? "nil")")
//             switch item.name {
//             case "code":
//                 authCode = item.value
//                 print("Found authorization code: \(authCode ?? "nil")")
//             case "state":
//                 state = item.value
//                 print("Found state: \(state ?? "nil")")
//             case "error":
//                 print("OAuth error: \(item.value ?? "unknown")")
//                 return
//             default:
//                 break
//             }
//         }

//         guard let code = authCode else {
//             print("No authorization code found in callback URL")
//             return
//         }

//         print("Authorization code: \(code)")

//         // Exchange authorization code for access token
//         do {
//             let token = try await oauthClient.exchangeCodeForToken(code: code, state: state)
//             print("Access token obtained successfully!")
//             print("Token type: \(token.tokenType)")
//             print("Expires in: \(token.expiresIn ?? 0) seconds")
//             print("Scope: \(token.scope ?? "none")")
//         } catch {
//             print("Failed to exchange code for token: \(error)")
//             return
//         }

//         // Use cached/just-stored token
//         do {
//             let validToken = try await oauthClient.getValidToken()
//             print("Valid token retrieved: \(validToken.accessToken.prefix(20))...")

//             var headers: [String: String] = [
//                 "Host": "chatgpt.com",
//                 "Accept": "text/event-stream"
//             ]
//             if let accountId = chatGPTAccountId(from: validToken.idToken) {
//                 headers["chatgpt-account-id"] = accountId
//             }

//             var additionalFields: [String: Any] = [
//                 "store": false,
//             ]
//             if let fileInstructions = loadInstructionsFile() {
//                 additionalFields["instructions"] = fileInstructions
//             }
//             var client = RemoteChatClient(
//                 model: "gpt-5",
//                 format: OpenAIResponsesFormat(),
//                 baseURL: "https://chatgpt.com/backend-api/codex/responses",
//                 apiKey: validToken.accessToken,
//                 additionalHeaders: headers,
//                 additionalBodyField: additionalFields
//             )
//             client.debugLogging = true

//             await testChatClient(client)

//         } catch {
//             print("Failed to get valid token: \(error)")
//         }

//     } catch {
//         print("OAuth error: \(error)")
//     }
// }

// // Test function for chat client
// func testChatClient(_ client: RemoteChatClient) async {
//     print("\n=== Testing Chat Client ===")
    
//     do {
//         let testMessage = ChatRequestBody.Message.user(
//             content: .text("Hello? Can you just say hi back to me?"),
//             name: nil
//         )
//         let chatRequest = ChatRequestBody(
//             messages: [testMessage],
//             maxCompletionTokens: 100,
//             temperature: 0.7
//         )
        
//         print("Sending test message (streaming)...")
//         let stream = try await client.streamingChatCompletionRequest(body: chatRequest)

//         var content = ""
//         var reasoning = ""
//         for try await event in stream {
//             switch event {
//             case let .chatCompletionChunk(chunk):
//                 for choice in chunk.choices {
//                     if let c = choice.delta.content { content += c }
//                     if let r = choice.delta.reasoningContent { reasoning += r }
//                 }
//             case let .tool(call):
//                 print("[tool] \(call.name): \(call.args)")
//             }
//         }

//         print("Response received:")
//         if !reasoning.isEmpty { print("Reasoning: \(reasoning)") }
//         print("Content: \(content.isEmpty ? "no content" : content)")
        
        
//     } catch {
//         print("Chat test failed: \(error)")
//         if let collectedError = client.collectedErrors {
//             print("Collected errors: \(collectedError)")
//         }
//     }
// }
