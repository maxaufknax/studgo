import Foundation
// URLSession sitzt auf Linux in einem eigenen Modul. Auf iOS ist der
// Block wirkungslos — dort gibt es FoundationNetworking nicht.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Der Dateibereich: hochladen, umbenennen, löschen, Ordner anlegen.
///
/// **Was die JSON:API hier wirklich kann** — anders als beim Ein- und
/// Austragen zu Veranstaltungen, wo `authorize()` alles außer GET verweigert,
/// ist der Dateibereich vollständig beschreibbar:
///
/// | Route | Zweck |
/// | --- | --- |
/// | `POST /folders/{id}/file-refs` | Hochladen (`multipart/form-data`) |
/// | `POST /folders/{id}/folders` | Unterordner anlegen |
/// | `PATCH /file-refs/{id}` | Umbenennen, Beschreibung ändern |
/// | `DELETE /file-refs/{id}` | Löschen |
/// | `GET /terms-of-use` | Die Lizenzen zur Auswahl |
///
/// Die Hochladeroute ist eine Besonderheit: `NegotiateFileRefsCreate` schaut
/// auf den `Content-Type` und verzweigt. Mit `application/vnd.api+json`
/// erwartet sie eine *Referenz auf eine bereits vorhandene Datei*, nur mit
/// `multipart/form-data` nimmt sie wirklich Bytes entgegen
/// (`FileRefsCreateByUpload`). Wer den JSON:API-Kopf mitschickt, bekommt
/// deshalb eine unverständliche Fehlermeldung über ein fehlendes `data`.
extension StudIPClient {

    // MARK: - Lizenzen

    /// Die Nutzungsbedingungen, unter denen eine Datei stehen kann.
    ///
    /// Stud.IP verlangt sie beim Hochladen über die Weboberfläche zwingend
    /// („Selbst erstelltes Werk"). Die API lässt das Feld zwar weg, dann steht
    /// die Datei aber auf `0` — unbestimmt. Deshalb bietet StudGo die Auswahl
    /// an und schlägt die Vorgabe der Installation vor.
    func termsOfUse() async throws -> [TermsOfUse] {
        try await listAllowingAbsence {
            try await get("/v1/terms-of-use", limit: 50).resources.compactMap(TermsOfUse.init)
        }
    }

    // MARK: - Hochladen

    /// Lädt eine Datei in einen Ordner.
    ///
    /// Der Body wird in eine temporäre Datei geschrieben und von dort
    /// gestreamt, statt im Speicher zusammengebaut zu werden: Eine
    /// Vorlesungsaufzeichnung von 400 MB würde die App sonst beim Hochladen
    /// abschießen.
    ///
    /// `Slug` ist Stud.IPs Weg, den Dateinamen zu setzen
    /// (`RoutesHelperTrait::getFilename`) — ohne diesen Kopf zählt der Name aus
    /// dem Multipart-Teil, den iOS bei manchen Quellen nur als
    /// „file" mitliefert.
    @discardableResult
    func upload(_ fileURL: URL,
                to folder: Folder,
                named name: String? = nil,
                termsID: String? = nil) async throws -> Bool {
        let filename = name ?? fileURL.lastPathComponent
        if isDemo {
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? nil
            DemoStore.shared.addFile(folderID: folder.id, name: filename, size: size ?? 0)
            return true
        }

        let boundary = "StudGo-\(UUID().uuidString)"
        let bodyFile = try Self.multipartBody(fileURL: fileURL,
                                              filename: filename,
                                              boundary: boundary,
                                              fields: termsID.map { ["term-id": $0] } ?? [:])
        defer { try? FileManager.default.removeItem(at: bodyFile) }

        var request = URLRequest(url: url(path: "/v1/folders/\(folder.id)/file-refs", query: []))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        // Der Name muss durch die Kopfzeile passen: Umlaute und Leerzeichen
        // werden prozentkodiert, Stud.IP dekodiert sie mit `rawurldecode`.
        if let encoded = filename.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            request.setValue(encoded, forHTTPHeaderField: "Slug")
        }

        let (data, response) = try await Self.session.upload(for: request, fromFile: bodyFile)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Keine HTTP-Antwort")
        }
        // 201 mit `Location`, kein Inhalt — die Ansicht lädt danach neu.
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { await onUnauthorized?() }
            throw APIError.http(http.statusCode, Self.uploadFailureDetail(data))
        }
        return true
    }

    private static func uploadFailureDetail(_ body: Data) -> String? {
        if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let errors = root["errors"] as? [[String: Any]] {
            let details = errors.compactMap { ($0["detail"] as? String) ?? ($0["title"] as? String) }
            if !details.isEmpty { return details.joined(separator: "\n") }
        }
        return StudIPErrorPage.message(from: body)
    }

    /// Schreibt den Multipart-Körper in eine temporäre Datei.
    private static func multipartBody(fileURL: URL,
                                      filename: String,
                                      boundary: String,
                                      fields: [String: String]) throws -> URL {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("studgo-upload-\(UUID().uuidString).part")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }

        func write(_ text: String) throws {
            try handle.write(contentsOf: Data(text.utf8))
        }

        for (key, value) in fields {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"file\"; filename=\"\(escaped(filename))\"\r\n")
        try write("Content-Type: application/octet-stream\r\n\r\n")

        // Blockweise kopieren statt `Data(contentsOf:)`: Eine große Datei
        // läge sonst vollständig im Speicher.
        let source = try FileHandle(forReadingFrom: fileURL)
        defer { try? source.close() }
        while let chunk = try source.read(upToCount: 512 * 1024), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }

        try write("\r\n--\(boundary)--\r\n")
        return target
    }

    /// Anführungszeichen und Zeilenumbrüche im Dateinamen würden den
    /// Multipart-Kopf zerreißen.
    private static func escaped(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Ändern und Löschen

    func renameFile(_ fileID: String, to name: String) async throws {
        let payload: [String: Any] = [
            "data": [
                "type": "file-refs",
                "id": fileID,
                "attributes": ["name": name],
            ],
        ]
        _ = try await send("PATCH", "/v1/file-refs/\(fileID)", body: payload)
    }

    func deleteFile(_ fileID: String) async throws {
        _ = try await send("DELETE", "/v1/file-refs/\(fileID)", body: [:])
    }

    /// Legt einen Unterordner an.
    ///
    /// `parent` muss **auch** als Beziehung mit, obwohl die Kennung schon im
    /// Pfad steht: `validateFolderResourceObject($json, null, false)` prüft den
    /// Rumpf für sich.
    func createFolder(named name: String,
                      description: String? = nil,
                      in parent: Folder) async throws {
        var attributes: [String: Any] = ["name": name]
        if let description, !description.isEmpty { attributes["description"] = description }
        let payload: [String: Any] = [
            "data": [
                "type": "folders",
                "attributes": attributes,
                "relationships": [
                    "parent": ["data": ["type": "folders", "id": parent.id]],
                ],
            ],
        ]
        _ = try await send("POST", "/v1/folders/\(parent.id)/folders", body: payload)
    }

}

/// Eine Lizenz aus `GET /v1/terms-of-use`.
struct TermsOfUse: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let summary: String?
    let isDefault: Bool

    init?(_ resource: Resource) {
        guard resource.type == "terms-of-use" else { return nil }
        id = resource.id
        name = resource.string("name")?.nilIfEmpty ?? "Ohne Angabe"
        summary = resource.string("description").map(StudipMarkup.plain)?.nilIfEmpty
        isDefault = resource.bool("is-default")
    }
}
