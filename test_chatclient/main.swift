import Foundation
import Darwin
import Dispatch
import ChatClientKit
import OAuthKit

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
// let oauthConfig = OAuthConfiguration(
//     clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
//     authorizationEndpoint: URL(string: "https://auth.openai.com/oauth/authorize")!,
//     tokenEndpoint: URL(string: "https://auth.openai.com/oauth/token")!,
//     redirectURI: URL(string: "http://localhost:1455/auth/callback")!,
//     scope: "openid profile email offline_access",
//     additionalParameters: [
//         "id_token_add_organizations": "true",
//         "codex_cli_simplified_flow": "true"
//     ],
//     usePKCE: true,
//     pkceMethod: .sha256
// )

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
