import Foundation
import XCTest
@testable import BlackGod

final class NexusDataVaultTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testConfirmedWipeRemovesExistingLegacyAndSessionEpisodesWhileKeepingMemoryAndSkills() throws {
        let library = NexusSessionLibrary(root: folder)
        let first = try library.bootstrap().activeID
        try library.conversationStore(for: first).save([ChatMessage(role: "user", content: "旧会话秘密")])
        let second = try library.create(title: "另一个会话")
        try library.conversationStore(for: second.id).save([ChatMessage(role: "assistant", content: "旧答案")])
        let sessionEpisode = library.conversationStore(for: first).episodeURL
        let secondEpisode = library.conversationStore(for: second.id).episodeURL
        let legacyNames = ["nexus-conversation.json", "nexus-conversation.agent.json", "nexus-conversation.episodes.json",
                           "nexus-shortcuts.agent.json", "nexus-shortcuts.agent.episodes.json"]
        let removedFiles = legacyNames.map { folder.appendingPathComponent($0) } + [sessionEpisode, secondEpisode]
        for url in removedFiles {
            try Data("existing-private-episode-or-checkpoint".utf8).write(to: url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "必须先有真实文件，不能测试不存在的夹具")
        }
        let memory = folder.appendingPathComponent("nexus-memory.json")
        let skills = folder.appendingPathComponent("nexus-skills.json")
        let memoryBytes = Data("confirmed-memory-fixture".utf8)
        let skillsBytes = Data("user-skill-fixture".utf8)
        try memoryBytes.write(to: memory)
        try skillsBytes.write(to: skills)

        try NexusDataVault(root: folder).wipeConversations(confirm: "确认删除")

        for url in removedFiles { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.conversationURL(for: first).deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.conversationURL(for: second.id).deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: memory), memoryBytes)
        XCTAssertEqual(try Data(contentsOf: skills), skillsBytes)
        let fresh = try library.bootstrap()
        XCTAssertEqual(fresh.sessions.count, 1)
        XCTAssertNotEqual(fresh.activeID, first)
        XCTAssertNotEqual(fresh.activeID, second.id)
        XCTAssertTrue(try library.conversationStore(for: fresh.activeID).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.conversationStore(for: fresh.activeID).episodeURL.path))
    }

    func testWrongWipeConfirmationLeavesExistingEpisodeAndConversationBytesUntouched() throws {
        let library = NexusSessionLibrary(root: folder)
        let current = try library.bootstrap().activeID
        let chatURL = library.conversationURL(for: current)
        try library.conversationStore(for: current).save([ChatMessage(role: "user", content: "保留这个会话")])
        let episodeURL = folder.appendingPathComponent("nexus-conversation.episodes.json")
        let episodeBytes = Data("existing-private-episode".utf8)
        try episodeBytes.write(to: episodeURL)
        let chatBytes = try Data(contentsOf: chatURL)
        XCTAssertThrowsError(try NexusDataVault(root: folder).wipeConversations(confirm: "删除")) { error in
            XCTAssertEqual(error as? NexusDataVaultError, .confirmMismatch)
        }
        XCTAssertEqual(try Data(contentsOf: episodeURL), episodeBytes)
        XCTAssertEqual(try Data(contentsOf: chatURL), chatBytes)
        XCTAssertEqual(try library.activeID(), current)
    }
}
