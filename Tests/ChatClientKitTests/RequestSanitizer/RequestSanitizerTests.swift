//
//  RequestSanitizerTests.swift
//  ChatClientKitTests
//
//  Created by GPT-5 Codex on 2025/12/07.
//

@testable import ChatClientKit
import Foundation
import Testing

struct RequestSanitizerTests {
    @Test
    func `Sanitizer preserves tool call structure`() {
        let toolCall = ChatRequestBody.Message.ToolCall(
            id: "tool-1",
            function: .init(name: "search_web", arguments: #"{"q":"hello"}"#)
        )

        let body = ChatRequestBody(
            model: "moonshotai/kimi-k2.5",
            messages: [
                .user(content: .text("please search")),
                .assistant(content: nil, toolCalls: [toolCall]),
            ]
        )

        let sanitized = RequestSanitizer().sanitize(body)
        let messages = sanitized.messages

        #expect(messages.count >= 2)
        #expect(messages[0].role == "user")
        #expect(messages[1].role == "assistant")
    }
}
