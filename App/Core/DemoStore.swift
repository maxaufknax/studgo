import Foundation

/// Was im Demo-Modus geschrieben wird.
///
/// Der Demo-Modus wäre eine Vitrine, wenn nichts von dem, was man tut, eine
/// Wirkung hätte: Eine geschriebene Nachricht verschwände, ein gelesener
/// Faden bliebe fett, eine gelöschte Datei stünde weiter da. Hier landet
/// deshalb alles Geschriebene und wird beim nächsten Lesen mit
/// zurückgegeben — dieselbe Antwort, die Stud.IP gäbe.
///
/// **Grenzen, mit Absicht:** Der Speicher liegt nur im Arbeitsspeicher. Beim
/// Verlassen der Demo (und bei jedem Neustart der App) ist er leer, und nichts
/// davon berührt jemals die Platte oder das Netz.
///
/// Der `NSLock` ist kein Übereifer: Die Ansichten laden nebenläufig, und zwei
/// Ansichten dürfen nicht gleichzeitig in dieselbe Liste schreiben.
final class DemoStore {

    static let shared = DemoStore()

    private let lock = NSLock()

    // MARK: - Gespeicherte Formen

    struct StoredMessage {
        let id: String
        let subject: String
        let body: String
        let senderID: String
        let recipientIDs: [String]
        let sentAt: Date
        var isRead: Bool
        let outgoing: Bool
    }

    struct StoredComment {
        let id: String
        let threadID: String
        let authorID: String
        let content: String
        let createdAt: Date
    }

    // MARK: - Zustand

    private var messageList: [StoredMessage] = []
    private var commentList: [StoredComment] = []
    private var threadList: [DemoData.DemoThread] = []
    private var forumList: [(parentID: String, id: String, title: String, content: String, date: Date)] = []
    private var folderList: [DemoData.DemoFolder] = []
    private var fileList: [(folderID: String, file: DemoData.DemoFile)] = []
    private var contacts: Set<String> = []
    private var deletedFiles: Set<String> = []
    private var renamedFiles: [String: String] = [:]
    private var hiddenMemberships: Set<String> = []
    private var bookedSlots: Set<String> = []
    private var readThreads: Set<String> = []
    private var counter = 0

    private init() { reset() }

    /// Setzt alles auf den Ausgangszustand zurück — beim Betreten und
    /// Verlassen der Demo.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        messageList = DemoData.messages.map {
            StoredMessage(id: $0.id, subject: $0.subject, body: $0.body,
                          senderID: $0.senderID, recipientIDs: $0.recipientIDs,
                          sentAt: Date().addingTimeInterval(-Double($0.hoursAgo) * 3600),
                          isRead: $0.isRead, outgoing: $0.outgoing)
        }
        commentList = DemoData.comments.map {
            StoredComment(id: $0.id, threadID: $0.threadID, authorID: $0.authorID,
                          content: $0.content,
                          createdAt: Date().addingTimeInterval(-Double($0.minutesAgo) * 60))
        }
        threadList = []
        forumList = []
        folderList = []
        fileList = []
        contacts = ["demo-behrens", "demo-sobczak", "demo-weber"]
        deletedFiles = []
        renamedFiles = [:]
        hiddenMemberships = []
        bookedSlots = []
        readThreads = []
        counter = 0
    }

    private func nextID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }

    // MARK: - Postfach

    func messages(outgoing: Bool) -> [StoredMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messageList.filter { $0.outgoing == outgoing }
    }

    func markMessage(_ id: String, read: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = messageList.firstIndex(where: { $0.id == id }) else { return }
        messageList[index].isRead = read
    }

    func sendMessage(subject: String, body: String, recipients: [String]) {
        lock.lock()
        defer { lock.unlock() }
        messageList.append(StoredMessage(id: nextID("demo-msg-neu"),
                                         subject: subject.isEmpty ? "(kein Betreff)" : subject,
                                         body: body,
                                         senderID: DemoData.userID,
                                         recipientIDs: recipients,
                                         sentAt: Date(),
                                         isRead: true,
                                         outgoing: true))
    }

    // MARK: - Blubber

    func comments(threadID: String) -> [StoredComment] {
        lock.lock()
        defer { lock.unlock() }
        return commentList.filter { $0.threadID == threadID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(threadID: String, content: String) {
        lock.lock()
        defer { lock.unlock() }
        commentList.append(StoredComment(id: nextID("demo-c-neu"),
                                         threadID: threadID,
                                         authorID: DemoData.userID,
                                         content: content,
                                         createdAt: Date()))
        readThreads.insert(threadID)
    }

    func addThread(content: String, courseID: String?) {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID("demo-thread-neu")
        threadList.append(DemoData.DemoThread(id: id,
                                              content: content,
                                              contextType: courseID == nil ? "public" : "course",
                                              contextID: courseID,
                                              name: nil,
                                              authorID: DemoData.userID,
                                              hoursAgo: 0))
    }

    /// Selbst angelegte Fäden — `courseID` grenzt auf eine Veranstaltung ein,
    /// `nil` liefert alle.
    func extraThreads(courseID: String?) -> [DemoData.DemoThread] {
        lock.lock()
        defer { lock.unlock() }
        guard let courseID else { return threadList }
        return threadList.filter { $0.contextID == courseID }
    }

    /// Ungelesene Beiträge — sobald der Faden einmal geöffnet war, keine mehr.
    func unseen(threadID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !readThreads.contains(threadID) else { return 0 }
        return threadID == "demo-thread-lena" ? 1 : 0
    }

    func markThreadRead(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        readThreads.insert(id)
    }

    // MARK: - Forum

    func addForumEntry(parentID: String, title: String, content: String) {
        lock.lock()
        defer { lock.unlock() }
        forumList.append((parentID: parentID, id: nextID("demo-forum-neu"),
                          title: title, content: content, date: Date()))
    }

    func extraForumEntries(parentID: String) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return forumList.filter { $0.parentID == parentID }.map { entry in
            ["type": "forum-entries",
             "id": entry.id,
             "attributes": ["title": entry.title,
                            "content": entry.content,
                            "mkdate": DemoData.stamp(entry.date)]]
        }
    }

    // MARK: - Kontakte

    func contactIDs() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return contacts
    }

    func addContact(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        contacts.insert(id)
    }

    func removeContact(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        contacts.remove(id)
    }

    // MARK: - Dateien

    func extraFolders(parentID: String) -> [DemoData.DemoFolder] {
        lock.lock()
        defer { lock.unlock() }
        return folderList.filter { $0.parentID == parentID }
    }

    func addFolder(parentID: String, name: String, description: String?) {
        lock.lock()
        defer { lock.unlock() }
        let courseID = DemoData.folders.first { $0.id == parentID }?.courseID ?? ""
        folderList.append(DemoData.DemoFolder(id: nextID("demo-f-neu"),
                                              courseID: courseID,
                                              parentID: parentID,
                                              name: name,
                                              description: description,
                                              files: []))
    }

    func extraFiles(folderID: String) -> [DemoData.DemoFile] {
        lock.lock()
        defer { lock.unlock() }
        return fileList.filter { $0.folderID == folderID }.map(\.file)
    }

    func addFile(folderID: String, name: String, size: Int) {
        lock.lock()
        defer { lock.unlock() }
        let file = DemoData.DemoFile(id: nextID("demo-file-neu"),
                                     name: name,
                                     mime: "application/octet-stream",
                                     size: size,
                                     dayOffset: 0)
        fileList.append((folderID: folderID, file: file))
    }

    func isDeleted(fileID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return deletedFiles.contains(fileID)
    }

    func deleteFile(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        deletedFiles.insert(id)
    }

    func renameFile(_ id: String, to name: String) {
        lock.lock()
        defer { lock.unlock() }
        renamedFiles[id] = name
    }

    func fileName(id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return renamedFiles[id] ?? fileList.first { $0.file.id == id }?.file.name
    }

    // MARK: - Mitgliedschaft

    func isVisible(membershipID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !hiddenMemberships.contains(membershipID)
    }

    func setVisibility(membershipID: String, visible: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if visible { hiddenMemberships.remove(membershipID) } else { hiddenMemberships.insert(membershipID) }
    }

    // MARK: - Sprechstunden

    func isBooked(slotID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return bookedSlots.contains(slotID)
    }

    func book(slotID: String) {
        lock.lock()
        defer { lock.unlock() }
        bookedSlots.insert(slotID)
    }

    func cancelBooking(id: String) {
        lock.lock()
        defer { lock.unlock() }
        bookedSlots.remove(id)
    }
}
