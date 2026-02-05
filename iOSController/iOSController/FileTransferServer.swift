import Foundation
import Network

/// HTTP Server for serving video files to Vision Pro devices
@MainActor
class FileTransferServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var port: UInt16 = 8081  // Different port from WebSocket
    @Published var activeTransfers: [String: TransferInfo] = [:]
    
    private var listener: NWListener?
    private var servedFiles: [String: ServedFile] = [:]  // fileId -> file info
    
    struct ServedFile {
        let id: String
        let url: URL
        let filename: String
        let fileSize: Int64
        let mimeType: String
    }
    
    struct TransferInfo: Identifiable {
        let id: String
        let filename: String
        var bytesSent: Int64
        let totalBytes: Int64
        var isComplete: Bool
        
        var progress: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesSent) / Double(totalBytes)
        }
    }
    
    init() {}
    
    // MARK: - Server Control
    
    /// Start the HTTP server
    func start() {
        guard !isRunning else { return }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            
            listener?.start(queue: .main)
            print("[FileTransferServer] Starting on port \(port)...")
            
        } catch {
            print("[FileTransferServer] Failed to start: \(error)")
        }
    }
    
    /// Stop the server
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        servedFiles.removeAll()
        activeTransfers.removeAll()
        print("[FileTransferServer] Stopped")
    }
    
    // MARK: - File Management
    
    /// Add a file to be served
    /// Returns the download URL
    func serveFile(url: URL, filename: String) -> String? {
        let fileId = UUID().uuidString
        
        // Get file size
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            print("[FileTransferServer] Cannot read file: \(url.path)")
            return nil
        }
        
        let mimeType = mimeTypeForExtension(url.pathExtension)
        
        let served = ServedFile(
            id: fileId,
            url: url,
            filename: filename,
            fileSize: fileSize,
            mimeType: mimeType
        )
        
        servedFiles[fileId] = served
        
        print("[FileTransferServer] ✅ File registered for serving:")
        print("[FileTransferServer]   ID: \(fileId)")
        print("[FileTransferServer]   Filename: \(filename)")
        print("[FileTransferServer]   Size: \(fileSize) bytes")
        print("[FileTransferServer]   Path: \(url.path)")
        print("[FileTransferServer]   Total served files: \(servedFiles.count)")
        
        // Return the download URL
        // The actual IP will be determined by the client
        return "/download/\(fileId)/\(filename)"
    }
    
    /// Remove a served file
    func removeFile(id: String) {
        servedFiles.removeValue(forKey: id)
    }
    
    /// Get full download URL with IP
    func getDownloadURL(path: String, localIP: String) -> String {
        return "http://\(localIP):\(port)\(path)"
    }
    
    // MARK: - Private Methods
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            if let port = listener?.port {
                self.port = port.rawValue
            }
            print("[FileTransferServer] ✅ Server ready on port \(self.port)")
        case .failed(let error):
            isRunning = false
            print("[FileTransferServer] ❌ Server failed: \(error)")
        case .cancelled:
            isRunning = false
            print("[FileTransferServer] Server cancelled")
        default:
            break
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveHTTPRequest(connection)
                case .failed(let error):
                    print("[FileTransferServer] Connection failed: \(error)")
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }
    
    private func receiveHTTPRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                if let error = error {
                    print("[FileTransferServer] Receive error: \(error)")
                    return
                }
                
                guard let content = content,
                      let request = String(data: content, encoding: .utf8) else {
                    return
                }
                
                self?.handleHTTPRequest(request, connection: connection)
            }
        }
    }
    
    private func handleHTTPRequest(_ request: String, connection: NWConnection) {
        let requestLine = request.components(separatedBy: "\r\n").first ?? ""
        print("[FileTransferServer] ========== HTTP REQUEST ==========")
        print("[FileTransferServer] Request: \(requestLine)")
        print("[FileTransferServer] Served files count: \(servedFiles.count)")
        for (id, file) in servedFiles {
            print("[FileTransferServer]   - \(id): \(file.filename) (\(file.fileSize) bytes)")
        }
        print("[FileTransferServer] ==================================")
        
        // Parse the request line
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendErrorResponse(connection, statusCode: 400, message: "Bad Request")
            return
        }
        
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendErrorResponse(connection, statusCode: 400, message: "Bad Request")
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        
        // Parse Range header for partial content requests
        var rangeStart: Int64?
        var rangeEnd: Int64?
        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                let rangeValue = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if rangeValue.hasPrefix("bytes=") {
                    let range = rangeValue.dropFirst(6)
                    let rangeParts = range.components(separatedBy: "-")
                    if rangeParts.count >= 1, let start = Int64(rangeParts[0]) {
                        rangeStart = start
                    }
                    if rangeParts.count >= 2, !rangeParts[1].isEmpty, let end = Int64(rangeParts[1]) {
                        rangeEnd = end
                    }
                }
                break
            }
        }
        
        // Route the request
        if method == "GET" && path.hasPrefix("/download/") {
            handleDownload(path, connection: connection, rangeStart: rangeStart, rangeEnd: rangeEnd)
        } else if method == "GET" && path == "/health" {
            sendTextResponse(connection, text: "OK")
        } else if method == "GET" && path == "/files" {
            handleFilesList(connection)
        } else {
            sendErrorResponse(connection, statusCode: 404, message: "Not Found")
        }
    }
    
    private func handleDownload(_ path: String, connection: NWConnection, rangeStart: Int64?, rangeEnd: Int64?) {
        print("[FileTransferServer] Processing download request: \(path)")
        
        // Parse: /download/{fileId}/{filename}
        let components = path.components(separatedBy: "/")
        print("[FileTransferServer] Path components: \(components)")
        
        guard components.count >= 3,
              let fileId = components.dropFirst(2).first else {
            print("[FileTransferServer] ❌ Invalid path format")
            sendErrorResponse(connection, statusCode: 404, message: "Invalid path")
            return
        }
        
        print("[FileTransferServer] Looking for fileId: \(fileId)")
        
        guard let served = servedFiles[fileId] else {
            print("[FileTransferServer] ❌ File not found in served files")
            print("[FileTransferServer] Available fileIds: \(servedFiles.keys.joined(separator: ", "))")
            sendErrorResponse(connection, statusCode: 404, message: "File not found")
            return
        }
        
        print("[FileTransferServer] ✅ Found file: \(served.filename) at \(served.url.path)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: served.url.path) else {
            print("[FileTransferServer] ❌ File does not exist on disk: \(served.url.path)")
            sendErrorResponse(connection, statusCode: 404, message: "File not found on disk")
            return
        }
        
        // Open file for reading - DO NOT use defer here because streaming is async!
        guard let fileHandle = try? FileHandle(forReadingFrom: served.url) else {
            print("[FileTransferServer] ❌ Cannot open file for reading")
            sendErrorResponse(connection, statusCode: 500, message: "Cannot open file")
            return
        }
        
        print("[FileTransferServer] ✅ File handle opened successfully")
        
        let fileSize = served.fileSize
        let start = rangeStart ?? 0
        let end = rangeEnd ?? (fileSize - 1)
        let contentLength = end - start + 1
        
        print("[FileTransferServer] Serving \(contentLength) bytes (range: \(start)-\(end) of \(fileSize))")
        
        // Create transfer info
        let transferId = UUID().uuidString
        activeTransfers[transferId] = TransferInfo(
            id: transferId,
            filename: served.filename,
            bytesSent: 0,
            totalBytes: contentLength,
            isComplete: false
        )
        
        // Build response headers
        var headers: String
        if rangeStart != nil {
            headers = "HTTP/1.1 206 Partial Content\r\n"
            headers += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r\n"
        } else {
            headers = "HTTP/1.1 200 OK\r\n"
        }
        headers += "Content-Type: \(served.mimeType)\r\n"
        headers += "Content-Length: \(contentLength)\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        headers += "Connection: close\r\n"
        headers += "\r\n"
        
        // Send headers
        let headerData = Data(headers.utf8)
        print("[FileTransferServer] Sending HTTP headers...")
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("[FileTransferServer] Header send error: \(error)")
                try? fileHandle.close()
                self?.activeTransfers.removeValue(forKey: transferId)
                return
            }
            
            print("[FileTransferServer] Headers sent, starting file stream...")
            
            // Stream the file
            Task { @MainActor in
                self?.streamFile(
                    fileHandle: fileHandle,
                    connection: connection,
                    start: start,
                    bytesToSend: contentLength,
                    transferId: transferId
                )
            }
        })
    }
    
    private func streamFile(fileHandle: FileHandle, connection: NWConnection, start: Int64, bytesToSend: Int64, transferId: String) {
        let chunkSize = 1024 * 1024  // 1MB chunks
        var offset: Int64 = start
        var remaining = bytesToSend
        
        print("[FileTransferServer] Starting stream: offset=\(offset), bytesToSend=\(bytesToSend)")
        
        func closeFileHandle() {
            do {
                try fileHandle.close()
                print("[FileTransferServer] File handle closed")
            } catch {
                print("[FileTransferServer] Error closing file handle: \(error)")
            }
        }
        
        func sendNextChunk() {
            guard remaining > 0 else {
                // Transfer complete
                closeFileHandle()
                Task { @MainActor in
                    self.activeTransfers[transferId]?.isComplete = true
                    print("[FileTransferServer] ✅ Transfer complete: \(self.activeTransfers[transferId]?.filename ?? "unknown")")
                    
                    // Clean up after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.activeTransfers.removeValue(forKey: transferId)
                    }
                }
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                return
            }
            
            do {
                try fileHandle.seek(toOffset: UInt64(offset))
                let readSize = min(Int(remaining), chunkSize)
                guard let data = try fileHandle.read(upToCount: readSize), !data.isEmpty else {
                    print("[FileTransferServer] End of file reached")
                    closeFileHandle()
                    connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                    return
                }
                
                print("[FileTransferServer] Sending chunk: \(data.count) bytes, remaining: \(remaining - Int64(data.count))")
                
                connection.send(content: data, completion: .contentProcessed { [weak self] error in
                    if let error = error {
                        print("[FileTransferServer] Send error: \(error)")
                        closeFileHandle()
                        Task { @MainActor in
                            self?.activeTransfers.removeValue(forKey: transferId)
                        }
                        return
                    }
                    
                    // Update progress
                    Task { @MainActor in
                        self?.activeTransfers[transferId]?.bytesSent += Int64(data.count)
                    }
                    
                    offset += Int64(data.count)
                    remaining -= Int64(data.count)
                    sendNextChunk()
                })
                
            } catch {
                print("[FileTransferServer] File read error: \(error)")
                closeFileHandle()
                Task { @MainActor in
                    self.activeTransfers.removeValue(forKey: transferId)
                }
            }
        }
        
        sendNextChunk()
    }
    
    private func handleFilesList(_ connection: NWConnection) {
        let files = servedFiles.values.map { file in
            [
                "id": file.id,
                "filename": file.filename,
                "size": file.fileSize,
                "mimeType": file.mimeType
            ] as [String : Any]
        }
        
        if let json = try? JSONSerialization.data(withJSONObject: files),
           let jsonString = String(data: json, encoding: .utf8) {
            sendJSONResponse(connection, json: jsonString)
        } else {
            sendErrorResponse(connection, statusCode: 500, message: "JSON Error")
        }
    }
    
    private func sendTextResponse(_ connection: NWConnection, text: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(text.count)\r\nConnection: close\r\n\r\n\(text)"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendJSONResponse(_ connection: NWConnection, json: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n\(json)"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendErrorResponse(_ connection: NWConnection, statusCode: Int, message: String) {
        let statusText: String
        switch statusCode {
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Error"
        }
        
        let body = "{\"error\": \"\(message)\"}"
        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        default: return "application/octet-stream"
        }
    }
}
