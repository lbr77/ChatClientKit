//
//  ResponsesE2ETests.swift
//  ChatClientKitTests
//

@testable import ChatClientKit
import Foundation
import Testing

struct ResponsesE2ETests {
    static let apiKey: String? = TestHelpers.loadAPIKey(named: "OPENROUTER_API_KEY")
    static let model = "moonshotai/kimi-k2.5"

    static func makeClient(model: String = ResponsesE2ETests.model) -> RemoteResponsesChatClient {
        RemoteResponsesChatClient(
            model: model,
            baseURL: "https://openrouter.ai/api",
            path: "/v1/responses",
            apiKey: apiKey ?? "missing",
            additionalHeaders: [
                "HTTP-Referer": "https://flowdown.ai/",
                "X-Title": "FlowDown",
            ]
        )
    }

    @Test(.enabled(if: apiKey != nil))
    func `Streaming basic text response`() async throws {
        let client = Self.makeClient()

        let stream = try await client.streamingChat(
            body: ChatRequestBody(
                messages: [
                    .system(content: .text("You are a helpful assistant. Reply briefly.")),
                    .user(content: .text("What is 2+2? Answer in one word.")),
                ],
                temperature: 0.1
            )
        )

        var chunks: [ChatResponseChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        let response = ChatResponse(chunks: chunks)
        let errors = client.collectedErrors
        print("[E2E] text response: '\(response.text)', reasoning: '\(response.reasoning)', tools: \(response.tools.count), errors: \(errors ?? "none")")
        print("[E2E] chunk count: \(chunks.count), chunks: \(chunks)")

        #expect(errors == nil, "Errors collected: \(errors ?? "")")
        #expect(!response.text.isEmpty, "Expected non-empty text response")
    }

    @Test(.enabled(if: apiKey != nil))
    func `Streaming multi-turn conversation`() async throws {
        let client = Self.makeClient()

        let stream = try await client.streamingChat(
            body: ChatRequestBody(
                messages: [
                    .user(content: .text("My name is Alice.")),
                    .assistant(content: .text("Nice to meet you, Alice!")),
                    .user(content: .text("What is my name? Reply in one word.")),
                ],
                temperature: 0.1
            )
        )

        var chunks: [ChatResponseChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        let response = ChatResponse(chunks: chunks)
        let errors = client.collectedErrors
        print("[E2E] multi-turn response: '\(response.text)', errors: \(errors ?? "none")")

        #expect(errors == nil, "Errors collected: \(errors ?? "")")
        #expect(!response.text.isEmpty, "Expected non-empty text response")
        #expect(response.text.lowercased().contains("alice"), "Expected response to contain 'Alice', got: \(response.text)")
    }

    @Test(.enabled(if: apiKey != nil))
    func `Streaming long text output does not timeout`() async throws {
        let client = Self.makeClient()

        let stream = try await client.streamingChat(
            body: ChatRequestBody(
                messages: [
                    .system(content: .text("You are a knowledgeable assistant.")),
                    .user(content: .text("Write a detailed explanation of how HTTP/2 works, including multiplexing, server push, header compression, and flow control. Be thorough.")),
                ],
                maxCompletionTokens: 2048,
                temperature: 0.3
            )
        )

        var totalText = ""
        var chunkCount = 0
        for try await chunk in stream {
            if let text = chunk.textValue {
                totalText += text
                chunkCount += 1
            }
        }

        let errors = client.collectedErrors
        print("[E2E] long output: \(totalText.count) chars, \(chunkCount) chunks, errors: \(errors ?? "none")")

        #expect(errors == nil, "Errors collected: \(errors ?? "")")
        #expect(totalText.count > 200, "Expected substantial text output, got \(totalText.count) chars")
        #expect(chunkCount > 10, "Expected many streaming chunks, got \(chunkCount)")
    }

    @Test(.enabled(if: apiKey != nil))
    func `Non-streaming basic response`() async throws {
        let client = Self.makeClient()

        let response = try await client.chat(
            body: ChatRequestBody(
                messages: [
                    .user(content: .text("What is the capital of France? One word.")),
                ],
                temperature: 0.1
            )
        )

        let errors = client.collectedErrors
        print("[E2E] non-streaming: '\(response.text)', errors: \(errors ?? "none")")

        #expect(errors == nil, "Errors collected: \(errors ?? "")")
        #expect(!response.text.isEmpty, "Expected non-empty response")
        #expect(response.text.lowercased().contains("paris"), "Expected 'Paris', got: \(response.text)")
    }
}
