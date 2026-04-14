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

    @Test
    func `Sanitizer repairs empty tool arguments using required schema fields`() throws {
        let toolCall = ChatRequestBody.Message.ToolCall(
            id: "tool-1",
            function: .init(name: "scrape_web_page", arguments: "")
        )

        let body = ChatRequestBody(
            model: "fireworks-ai",
            messages: [
                .assistant(content: nil, toolCalls: [toolCall]),
            ],
            tools: [
                .function(
                    name: "scrape_web_page",
                    description: "Scrape a page.",
                    parameters: [
                        "type": "object",
                        "properties": [
                            "url": [
                                "type": "string",
                            ],
                        ],
                        "required": ["url"],
                        "additionalProperties": false,
                    ],
                    strict: true
                ),
            ]
        )

        let sanitized = RequestSanitizer().sanitize(body)
        let data = try JSONEncoder().encode(sanitized)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let messages = try #require(json["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first)
        let toolCalls = try #require(assistant["tool_calls"] as? [[String: Any]])
        let firstToolCall = try #require(toolCalls.first)
        let function = try #require(firstToolCall["function"] as? [String: Any])

        #expect(function["arguments"] as? String == #"{"url":""}"#)
    }

    @Test
    func `Tool argument repair falls back to empty object without schema`() {
        let repaired = ToolCallArgumentRepair.normalize(
            arguments: "",
            forToolNamed: "unknown_tool",
            using: nil
        )

        #expect(repaired == "{}")
    }
}
