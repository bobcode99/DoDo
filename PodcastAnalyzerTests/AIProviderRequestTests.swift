//
//  AIProviderRequestTests.swift
//  PodcastAnalyzerTests
//
//  Request bodies and response parsing that differ per provider API.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("AI provider requests")
struct AIProviderRequestTests {

  private func body(_ client: OpenAICompatibleClient) -> [String: Any] {
    client.requestBody(prompt: "p", systemPrompt: "s", model: "m", maxTokens: 8192)
  }

  @Test("OpenAI sends max_completion_tokens and no temperature")
  func openAIBody() {
    let body = body(.openAI())
    #expect(body["max_completion_tokens"] as? Int == 8192)
    #expect(body["max_tokens"] == nil)
    #expect(body["temperature"] == nil)
  }

  @Test("Groq and xAI send max_completion_tokens and keep temperature")
  func otherCloudBodies() {
    for client in [OpenAICompatibleClient.groq(), .grok()] {
      let body = body(client)
      #expect(body["max_completion_tokens"] as? Int == 8192)
      #expect(body["temperature"] as? Double == 0.7)
    }
  }

  @Test("Local servers keep max_tokens")
  func localBody() {
    let body = body(.lmStudio(baseURL: URL(string: "http://localhost:1234")!))
    #expect(body["max_tokens"] as? Int == 8192)
    #expect(body["max_completion_tokens"] == nil)
  }

  @Test("Gemini puts the system prompt in systemInstruction")
  func geminiBody() {
    let body = GeminiClient(provider: .gemini).requestBody(prompt: "p", systemPrompt: "s", maxTokens: 8192)
    let system = (body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]]
    #expect(system?.first?["text"] as? String == "s")
    let config = body["generationConfig"] as? [String: Any]
    #expect(config?["temperature"] == nil)
  }

  @Test("Gemini joins every text part and skips thoughts")
  func geminiAnswerText() {
    let candidate: [String: Any] = [
      "content": ["parts": [
        ["text": "thinking…", "thought": true],
        ["text": "Hello, "],
        ["text": "world"],
      ]]
    ]
    #expect(GeminiClient.answerText(in: candidate) == "Hello, world")
  }
}
