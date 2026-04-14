//
//  RemoteResponsesToolCallingLiveTests.swift
//  ChatClientKitTests
//

@testable import ChatClientKit
import Foundation
import Testing

@Suite(.serialized)
struct RemoteResponsesToolCallingLiveTests {
    private enum TransportMode {
        case streaming
        case nonStreaming
    }

    private let prompt = """
    Use the add_numbers tool exactly once with a=2 and b=3.
    For the first assistant turn, emit the tool call and stop.
    After the tool result arrives, answer with the final result and include the number 5.
    """

    private var tools: [ChatRequestBody.Tool] {
        let parameters: [String: AnyCodingValue] = [
            "type": .string("object"),
            "properties": .object([
                "a": .object(["type": .string("integer")]),
                "b": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("a"), .string("b")]),
        ]
        return [
            .function(
                name: "add_numbers",
                description: "Add two integers.",
                parameters: parameters,
                strict: true
            ),
        ]
    }

    @Test(.enabled(if: TestHelpers.isOpenRouterResponsesFixtureConfigured))
    func `OpenRouter responses streaming tool round trip works`() async throws {
        let client = TestHelpers.makeOpenRouterFixtureResponsesClient()
        try await assertToolRoundTripWorks(with: client, transport: .streaming)
    }

    @Test(.enabled(if: TestHelpers.isFireworksResponsesFixtureConfigured))
    func `Fireworks responses tool round trip works`() async throws {
        let client = TestHelpers.makeFireworksFixtureResponsesClient()
        try await assertToolRoundTripWorks(with: client, transport: .nonStreaming)
    }

    private func assertToolRoundTripWorks(
        with client: RemoteResponsesChatClient,
        transport: TransportMode
    ) async throws {
        let firstResponse = try await collectResponse(
            from: client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 256,
                temperature: 0,
                tools: tools
            ),
            transport: transport
        )

        let toolCall = try #require(firstResponse.tools.first)
        #expect(toolCall.name == "add_numbers")
        #expect(toolCall.args.contains("\"a\""))
        #expect(toolCall.args.contains("\"b\""))
        #expect(client.collectedErrors == nil, "Initial tool call produced errors: \(client.collectedErrors ?? "")")

        let assistantToolCall = ChatRequestBody.Message.ToolCall(
            id: toolCall.id,
            function: .init(name: toolCall.name, arguments: toolCall.args)
        )

        let finalResponse = try await collectResponse(
            from: client,
            body: ChatRequestBody(
                messages: [
                    .user(content: .text(prompt)),
                    .assistant(content: nil, toolCalls: [assistantToolCall]),
                    .tool(content: .text("5"), toolCallID: toolCall.id),
                ],
                maxCompletionTokens: 256,
                temperature: 0
            ),
            transport: transport
        )

        let normalized = finalResponse.text.lowercased()
        #expect(!normalized.isEmpty, "Expected final response text after tool output.")
        #expect(normalized.contains("5"), "Expected provider to incorporate the tool result. Content: \(finalResponse.text)")
        #expect(client.collectedErrors == nil, "Tool round trip produced errors: \(client.collectedErrors ?? "")")
    }

    private func collectResponse(
        from client: RemoteResponsesChatClient,
        body: ChatRequestBody,
        transport: TransportMode
    ) async throws -> ChatResponse {
        try await retryingTransientNetworkErrors {
            switch transport {
            case .streaming:
                let stream = try await client.streamingChat(body: body)
                var chunks: [ChatResponseChunk] = []
                for try await chunk in stream {
                    chunks.append(chunk)
                }
                return ChatResponse(chunks: chunks)
            case .nonStreaming:
                let request = try client.makeURLRequest(
                    body: client.resolve(body: body, stream: false)
                )
                let (data, _) = try await client.session.data(for: request)
                let decoder = RemoteResponsesChatResponseDecoder(
                    decoder: client.responseDecoderFactory()
                )
                let chunks = try decoder.decodeResponse(from: data)
                return ChatResponse(chunks: chunks)
            }
        }
    }

    private func retryingTransientNetworkErrors<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts > 0)

        var lastError: Error?
        for attempt in 1 ... maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts, isTransientNetworkError(error) else {
                    throw error
                }
                try await Task.sleep(for: .seconds(Double(attempt)))
            }
        }

        throw lastError ?? CancellationError()
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorResourceUnavailable,
            ].contains(nsError.code)
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isTransientNetworkError(underlying)
        }

        return false
    }
}
